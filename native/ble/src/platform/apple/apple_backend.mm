// CoreBluetooth-backend (macOS 10.13+/iOS 10+): реализация BleBackend поверх CBCentralManager.
//
// Устройство:
// - AppleBackend (C++) — публичный интерфейс BleBackend и доставка событий в BleListener;
// - OvoschBleCentralDelegate (Objective-C) — делегат CBCentralManager/CBPeripheral, владеет
//   центральным менеджером, словарём периферий по id и состоянием ожидающих чтений.
// Идентификатор устройства — peripheral.identifier.UUIDString. Сильные ссылки на все
// обнаруженные и подключённые периферии держатся в словаре до dispose/деструктора
// (CoreBluetooth требует удерживать CBPeripheral, иначе соединение рвётся).
// Все колбэки — на очереди ovosch.ble; is_available()/get_adapter_state() потокобезопасны
// (атомарное состояние), доступ к listener — под мьютексом.
//
// Нормализация UUID — как BleUuids.normalize в GDScript: 16-битные → "XXXX" (верхний регистр),
// 128-битные на базе Bluetooth Base UUID → их 16-битная часть, прочие 128-битные — полная
// строка в верхнем регистре. GDScript-слой нормализует входящие UUID повторно.

#import <CoreBluetooth/CoreBluetooth.h>
#import <Foundation/Foundation.h>

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

#include "apple_backend.h"

namespace ovosch {
class AppleBackend;
}

// ---------------------------------------------------------------------------
// Вспомогательные функции конвертации
// ---------------------------------------------------------------------------

static std::string ovosch_to_std(NSString *s) {
	if (s == nil) {
		return std::string();
	}
	const char *utf8 = [s UTF8String];
	return utf8 != nullptr ? std::string(utf8) : std::string();
}

static NSString *ovosch_to_ns(const std::string &s) {
	return [NSString stringWithUTF8String:s.c_str()];
}

// Нормализация UUID к виду BleUuids.normalize (см. шапку файла).
static NSString *ovosch_normalize_uuid(NSString *raw) {
	NSString *u = [[raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
	if ([u hasPrefix:@"0X"]) {
		u = [u substringFromIndex:2];
	}
	static NSString *const kBaseSuffix = @"-0000-1000-8000-00805F9B34FB";
	if ([u length] == 36 && [u hasPrefix:@"0000"] && [u hasSuffix:kBaseSuffix]) {
		return [u substringWithRange:NSMakeRange(4, 4)];
	}
	if ([u length] == 8 && [u hasPrefix:@"0000"]) {
		return [u substringFromIndex:4];
	}
	return u;
}

static NSString *ovosch_cbuuid_string(CBUUID *uuid) {
	return ovosch_normalize_uuid([uuid UUIDString]);
}

static CBUUID *ovosch_cbuuid_from(const std::string &s) {
	NSString *norm = ovosch_normalize_uuid(ovosch_to_ns(s));
	if ([norm length] == 0) {
		return nil;
	}
	return [CBUUID UUIDWithString:norm];
}

static std::vector<uint8_t> ovosch_bytes_from(NSData *data) {
	if (data == nil || [data length] == 0) {
		return std::vector<uint8_t>();
	}
	const uint8_t *ptr = static_cast<const uint8_t *>([data bytes]);
	return std::vector<uint8_t>(ptr, ptr + [data length]);
}

// Параметры сканирования: с дубликатами рекламы. Без них CoreBluetooth сообщает устройство
// один раз за сеанс, и GDScript-сканер через 10 с считает его пропавшим, а автоподключение
// ждёт device_found, которого не будет. Поток событий прореживает OvoschBle (ScanThrottle).
static NSDictionary<NSString *, id> *ovosch_scan_options() {
	return @{ CBCentralManagerScanOptionAllowDuplicatesKey : @YES };
}

static NSString *ovosch_read_key(CBPeripheral *peripheral, CBCharacteristic *characteristic) {
	return [NSString stringWithFormat:@"%@/%@", [[peripheral identifier] UUIDString], ovosch_cbuuid_string([characteristic UUID])];
}

// ---------------------------------------------------------------------------
// Objective-C делегат
// ---------------------------------------------------------------------------

@interface OvoschBleCentralDelegate : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>

// Сырой указатель на владельца; обнуляется в деструкторе AppleBackend под его мьютексом.
@property(nonatomic, assign) ovosch::AppleBackend *owner;
@property(nonatomic, strong) CBCentralManager *central;
@property(nonatomic, strong) dispatch_queue_t queue;
// id → CBPeripheral (все обнаруженные и подключённые).
@property(nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *peripherals;
// id → число сервисов, у которых ещё не открыты характеристики.
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *pendingCharacteristicDiscoveries;
// "id/char" — ожидающие ответа чтения (отличает characteristic_read от notification).
@property(nonatomic, strong) NSMutableSet<NSString *> *pendingReads;
// id периферий, отключение которых запросили мы (reason = REQUESTED).
@property(nonatomic, strong) NSMutableSet<NSString *> *requestedDisconnects;
// Фильтр сканирования, отложенного до poweredOn (nil — сканирование не запрошено).
@property(nonatomic, strong) NSArray<CBUUID *> *pendingScanServices;
@property(nonatomic, assign) BOOL scanRequested;

- (instancetype)initWithOwner:(ovosch::AppleBackend *)owner;
- (CBPeripheral *)peripheralForId:(NSString *)identifier;
- (CBCharacteristic *)characteristicOf:(CBPeripheral *)peripheral service:(NSString *)serviceUUID characteristic:(NSString *)charUUID;

@end

// ---------------------------------------------------------------------------
// C++ backend
// ---------------------------------------------------------------------------

namespace ovosch {

class AppleBackend final : public BleBackend {
public:
	AppleBackend();
	~AppleBackend() override;

	// --- BleBackend ---
	void set_listener(BleListener *listener) override;
	bool is_available() const override;
	AdapterState get_adapter_state() const override;
	void start_scan(const std::vector<std::string> &service_uuids) override;
	void stop_scan() override;
	void connect_peripheral(const std::string &id) override;
	void disconnect_peripheral(const std::string &id) override;
	void discover_services(const std::string &id) override;
	void subscribe(const std::string &id, const std::string &service_uuid, const std::string &char_uuid) override;
	void unsubscribe(const std::string &id, const std::string &service_uuid, const std::string &char_uuid) override;
	void write(const std::string &id, const std::string &service_uuid, const std::string &char_uuid,
			const std::vector<uint8_t> &bytes, bool with_response) override;
	void read_characteristic(const std::string &id, const std::string &service_uuid, const std::string &char_uuid) override;

	// --- вызовы из делегата (очередь ovosch.ble) ---
	void handle_adapter_state(CBManagerState state);
	void handle_discovered(CBPeripheral *peripheral, NSDictionary *advertisement, NSNumber *rssi);
	void handle_connected(CBPeripheral *peripheral);
	void handle_connect_failed(CBPeripheral *peripheral, NSError *error);
	void handle_disconnected(CBPeripheral *peripheral, NSError *error);
	void handle_services_discovered(CBPeripheral *peripheral, NSError *error);
	void handle_characteristics_discovered(CBPeripheral *peripheral, CBService *service, NSError *error);
	void handle_value_updated(CBPeripheral *peripheral, CBCharacteristic *characteristic, NSError *error);
	void handle_write_done(CBPeripheral *peripheral, CBCharacteristic *characteristic, NSError *error);
	void handle_notify_state(CBPeripheral *peripheral, CBCharacteristic *characteristic, NSError *error);

private:
	// Доставка события слушателю под мьютексом (слушатель может быть снят параллельно).
	template <typename F>
	void notify(F &&fn) {
		std::lock_guard<std::mutex> lock(listener_mutex_);
		if (listener_ != nullptr) {
			fn(listener_);
		}
	}
	void emit_error(const std::string &id, ErrorCode code, const std::string &message);
	void emit_services(CBPeripheral *peripheral);
	static ErrorCode map_error(NSError *error, ErrorCode fallback);
	static std::string describe(NSError *error, const char *context);
	CBPeripheral *peripheral_or_error(const std::string &id, bool must_be_connected);
	CBCharacteristic *characteristic_or_error(CBPeripheral *peripheral, const std::string &id,
			const std::string &service_uuid, const std::string &char_uuid);

	OvoschBleCentralDelegate *delegate_;
	BleListener *listener_ = nullptr;
	std::mutex listener_mutex_;
	std::atomic<int> adapter_state_;
};

AppleBackend::AppleBackend() :
		adapter_state_(static_cast<int>(AdapterState::UNKNOWN)) {
	delegate_ = [[OvoschBleCentralDelegate alloc] initWithOwner:this];
}

AppleBackend::~AppleBackend() {
	{
		std::lock_guard<std::mutex> lock(listener_mutex_);
		listener_ = nullptr;
	}
	OvoschBleCentralDelegate *delegate = delegate_;
	delegate_ = nil;
	if (delegate != nil) {
		// Снимаем владельца и рвём соединения синхронно на очереди CoreBluetooth,
		// чтобы колбэки не обратились к уже разрушенному объекту.
		dispatch_sync([delegate queue], ^{
			[delegate setOwner:nullptr];
			if ([[delegate central] isScanning]) {
				[[delegate central] stopScan];
			}
			for (CBPeripheral *p in [[delegate peripherals] allValues]) {
				if ([p state] == CBPeripheralStateConnected || [p state] == CBPeripheralStateConnecting) {
					[[delegate central] cancelPeripheralConnection:p];
				}
				[p setDelegate:nil];
			}
			[[delegate peripherals] removeAllObjects];
			[[delegate central] setDelegate:nil];
		});
	}
}

// ---------------------------------------------------------------------------
// BleBackend
// ---------------------------------------------------------------------------

void AppleBackend::set_listener(BleListener *listener) {
	std::lock_guard<std::mutex> lock(listener_mutex_);
	listener_ = listener;
}

bool AppleBackend::is_available() const {
	return adapter_state_.load() == static_cast<int>(AdapterState::POWERED_ON);
}

AdapterState AppleBackend::get_adapter_state() const {
	return static_cast<AdapterState>(adapter_state_.load());
}

void AppleBackend::start_scan(const std::vector<std::string> &service_uuids) {
	NSMutableArray<CBUUID *> *filter = [NSMutableArray arrayWithCapacity:service_uuids.size()];
	for (const std::string &s : service_uuids) {
		CBUUID *uuid = ovosch_cbuuid_from(s);
		if (uuid != nil) {
			[filter addObject:uuid];
		}
	}
	OvoschBleCentralDelegate *delegate = delegate_;
	dispatch_async([delegate queue], ^{
		[delegate setScanRequested:YES];
		[delegate setPendingScanServices:([filter count] > 0 ? filter : nil)];
		if ([[delegate central] state] == CBManagerStatePoweredOn) {
			[[delegate central] scanForPeripheralsWithServices:[delegate pendingScanServices]
													   options:ovosch_scan_options()];
		}
		// Иначе сканирование стартует в centralManagerDidUpdateState при poweredOn.
	});
}

void AppleBackend::stop_scan() {
	OvoschBleCentralDelegate *delegate = delegate_;
	dispatch_async([delegate queue], ^{
		[delegate setScanRequested:NO];
		[delegate setPendingScanServices:nil];
		if ([[delegate central] isScanning]) {
			[[delegate central] stopScan];
		}
	});
}

void AppleBackend::connect_peripheral(const std::string &id_arg) {
	// Копии аргументов до dispatch_async: блок захватывает C++-ссылку `const std::string &` как
	// ссылку, а к моменту выполнения блока строка вызывающей стороны уже разрушена — id приходил
	// пустым («peripheral not found: »), и после connected ничего не работало.
	const std::string id = id_arg;
	OvoschBleCentralDelegate *delegate = delegate_;
	NSString *identifier = ovosch_to_ns(id);
	dispatch_async([delegate queue], ^{
		CBPeripheral *p = [delegate peripheralForId:identifier];
		if (p == nil) {
			emit_error(id, ErrorCode::DEVICE_NOT_FOUND, "CoreBluetooth: peripheral not found: " + id);
			return;
		}
		if ([[delegate central] state] != CBManagerStatePoweredOn) {
			emit_error(id, ErrorCode::ADAPTER_UNAVAILABLE, "CoreBluetooth: Bluetooth is not powered on");
			return;
		}
		[[delegate requestedDisconnects] removeObject:identifier];
		[p setDelegate:delegate];
		[[delegate central] connectPeripheral:p options:nil];
	});
}

void AppleBackend::disconnect_peripheral(const std::string &id_arg) {
	// Копии аргументов для блока dispatch_async (см. connect_peripheral).
	const std::string id = id_arg;
	OvoschBleCentralDelegate *delegate = delegate_;
	NSString *identifier = ovosch_to_ns(id);
	dispatch_async([delegate queue], ^{
		CBPeripheral *p = [[delegate peripherals] objectForKey:identifier];
		if (p == nil) {
			return;
		}
		[[delegate requestedDisconnects] addObject:identifier];
		[[delegate central] cancelPeripheralConnection:p];
	});
}

void AppleBackend::discover_services(const std::string &id_arg) {
	// Копии аргументов для блока dispatch_async (см. connect_peripheral).
	const std::string id = id_arg;
	OvoschBleCentralDelegate *delegate = delegate_;
	dispatch_async([delegate queue], ^{
		CBPeripheral *p = peripheral_or_error(id, true);
		if (p == nil) {
			return;
		}
		[[delegate pendingCharacteristicDiscoveries] removeObjectForKey:[[p identifier] UUIDString]];
		[p discoverServices:nil];
	});
}

void AppleBackend::subscribe(const std::string &id_arg, const std::string &service_uuid_arg, const std::string &char_uuid_arg) {
	// Копии аргументов для блока dispatch_async (см. connect_peripheral).
	const std::string id = id_arg;
	const std::string service_uuid = service_uuid_arg;
	const std::string char_uuid = char_uuid_arg;
	OvoschBleCentralDelegate *delegate = delegate_;
	dispatch_async([delegate queue], ^{
		CBPeripheral *p = peripheral_or_error(id, true);
		if (p == nil) {
			return;
		}
		CBCharacteristic *c = characteristic_or_error(p, id, service_uuid, char_uuid);
		if (c == nil) {
			return;
		}
		[p setNotifyValue:YES forCharacteristic:c];
	});
}

void AppleBackend::unsubscribe(const std::string &id_arg, const std::string &service_uuid_arg, const std::string &char_uuid_arg) {
	// Копии аргументов для блока dispatch_async (см. connect_peripheral).
	const std::string id = id_arg;
	const std::string service_uuid = service_uuid_arg;
	const std::string char_uuid = char_uuid_arg;
	OvoschBleCentralDelegate *delegate = delegate_;
	dispatch_async([delegate queue], ^{
		CBPeripheral *p = [[delegate peripherals] objectForKey:ovosch_to_ns(id)];
		if (p == nil || [p state] != CBPeripheralStateConnected) {
			return;
		}
		CBCharacteristic *c = [delegate characteristicOf:p service:ovosch_to_ns(service_uuid) characteristic:ovosch_to_ns(char_uuid)];
		if (c != nil) {
			[p setNotifyValue:NO forCharacteristic:c];
		}
	});
}

void AppleBackend::write(const std::string &id_arg, const std::string &service_uuid_arg, const std::string &char_uuid_arg,
		const std::vector<uint8_t> &bytes, bool with_response) {
	// Копии аргументов для блока dispatch_async (см. connect_peripheral).
	const std::string id = id_arg;
	const std::string service_uuid = service_uuid_arg;
	const std::string char_uuid = char_uuid_arg;
	OvoschBleCentralDelegate *delegate = delegate_;
	NSData *data = [NSData dataWithBytes:(bytes.empty() ? nullptr : bytes.data()) length:bytes.size()];
	dispatch_async([delegate queue], ^{
		CBPeripheral *p = peripheral_or_error(id, true);
		if (p == nil) {
			return;
		}
		CBCharacteristic *c = characteristic_or_error(p, id, service_uuid, char_uuid);
		if (c == nil) {
			return;
		}
		CBCharacteristicWriteType type = with_response ? CBCharacteristicWriteWithResponse : CBCharacteristicWriteWithoutResponse;
		[p writeValue:data forCharacteristic:c type:type];
		if (!with_response) {
			// Write Command подтверждения не имеет: считаем доставленным сразу после постановки.
			std::string ch = ovosch_to_std(ovosch_cbuuid_string([c UUID]));
			notify([&](BleListener *l) { l->on_write_done(id, ch, true); });
		}
	});
}

void AppleBackend::read_characteristic(const std::string &id_arg, const std::string &service_uuid_arg, const std::string &char_uuid_arg) {
	// Копии аргументов для блока dispatch_async (см. connect_peripheral).
	const std::string id = id_arg;
	const std::string service_uuid = service_uuid_arg;
	const std::string char_uuid = char_uuid_arg;
	OvoschBleCentralDelegate *delegate = delegate_;
	dispatch_async([delegate queue], ^{
		CBPeripheral *p = peripheral_or_error(id, true);
		if (p == nil) {
			return;
		}
		CBCharacteristic *c = characteristic_or_error(p, id, service_uuid, char_uuid);
		if (c == nil) {
			return;
		}
		[[delegate pendingReads] addObject:ovosch_read_key(p, c)];
		[p readValueForCharacteristic:c];
	});
}

// ---------------------------------------------------------------------------
// События CoreBluetooth
// ---------------------------------------------------------------------------

void AppleBackend::handle_adapter_state(CBManagerState state) {
	AdapterState mapped = AdapterState::UNKNOWN;
	switch (state) {
		case CBManagerStateUnsupported:
			mapped = AdapterState::UNSUPPORTED;
			break;
		case CBManagerStateUnauthorized:
			mapped = AdapterState::UNAUTHORIZED;
			break;
		case CBManagerStatePoweredOff:
			mapped = AdapterState::POWERED_OFF;
			break;
		case CBManagerStatePoweredOn:
			mapped = AdapterState::POWERED_ON;
			break;
		case CBManagerStateUnknown:
		case CBManagerStateResetting:
		default:
			mapped = AdapterState::UNKNOWN;
			break;
	}
	adapter_state_.store(static_cast<int>(mapped));
	notify([&](BleListener *l) { l->on_adapter_state_changed(mapped); });

	OvoschBleCentralDelegate *delegate = delegate_;
	if (delegate == nil) {
		return;
	}
	if (mapped == AdapterState::POWERED_ON) {
		if ([delegate scanRequested] && ![[delegate central] isScanning]) {
			[[delegate central] scanForPeripheralsWithServices:[delegate pendingScanServices]
													   options:ovosch_scan_options()];
		}
	} else if (mapped == AdapterState::UNSUPPORTED || mapped == AdapterState::UNAUTHORIZED || mapped == AdapterState::POWERED_OFF) {
		if ([delegate scanRequested]) {
			emit_error("", ErrorCode::ADAPTER_UNAVAILABLE, "CoreBluetooth: Bluetooth is unavailable (state " + std::to_string(static_cast<int>(mapped)) + ")");
		}
	}
}

void AppleBackend::handle_discovered(CBPeripheral *peripheral, NSDictionary *advertisement, NSNumber *rssi) {
	OvoschBleCentralDelegate *delegate = delegate_;
	NSString *identifier = [[peripheral identifier] UUIDString];
	[[delegate peripherals] setObject:peripheral forKey:identifier];

	NSString *name = [advertisement objectForKey:CBAdvertisementDataLocalNameKey];
	if (name == nil) {
		name = [peripheral name];
	}
	std::vector<std::string> services;
	NSArray *adv_services = [advertisement objectForKey:CBAdvertisementDataServiceUUIDsKey];
	for (CBUUID *uuid in adv_services) {
		services.push_back(ovosch_to_std(ovosch_cbuuid_string(uuid)));
	}
	int rssi_value = rssi != nil ? [rssi intValue] : 0;
	if (rssi_value == 127) {
		rssi_value = 0; // 127 — «RSSI недоступен» по спецификации CoreBluetooth.
	}
	std::string id = ovosch_to_std(identifier);
	std::string name_str = ovosch_to_std(name);
	notify([&](BleListener *l) { l->on_device_found(id, name_str, rssi_value, services); });
}

void AppleBackend::handle_connected(CBPeripheral *peripheral) {
	std::string id = ovosch_to_std([[peripheral identifier] UUIDString]);
	notify([&](BleListener *l) { l->on_connected(id); });
}

void AppleBackend::handle_connect_failed(CBPeripheral *peripheral, NSError *error) {
	std::string id = ovosch_to_std([[peripheral identifier] UUIDString]);
	emit_error(id, map_error(error, ErrorCode::CONNECTION_FAILED), describe(error, "connect failed"));
}

void AppleBackend::handle_disconnected(CBPeripheral *peripheral, NSError *error) {
	OvoschBleCentralDelegate *delegate = delegate_;
	NSString *identifier = [[peripheral identifier] UUIDString];
	std::string id = ovosch_to_std(identifier);
	// Сбрасываем состояние ожиданий этой периферии.
	NSMutableSet<NSString *> *stale = [NSMutableSet set];
	for (NSString *key in [delegate pendingReads]) {
		if ([key hasPrefix:identifier]) {
			[stale addObject:key];
		}
	}
	[[delegate pendingReads] minusSet:stale];
	[[delegate pendingCharacteristicDiscoveries] removeObjectForKey:identifier];

	DisconnectReason reason = DisconnectReason::LINK_LOSS;
	if ([[delegate requestedDisconnects] containsObject:identifier]) {
		[[delegate requestedDisconnects] removeObject:identifier];
		reason = DisconnectReason::REQUESTED;
	} else if (error != nil) {
		if ([[error domain] isEqualToString:CBErrorDomain] && [error code] == CBErrorConnectionTimeout) {
			reason = DisconnectReason::TIMEOUT;
		} else if ([[error domain] isEqualToString:CBErrorDomain] && [error code] == CBErrorPeripheralDisconnected) {
			reason = DisconnectReason::LINK_LOSS;
		} else {
			reason = DisconnectReason::ERROR;
		}
	}
	notify([&](BleListener *l) { l->on_disconnected(id, reason); });
}

void AppleBackend::handle_services_discovered(CBPeripheral *peripheral, NSError *error) {
	OvoschBleCentralDelegate *delegate = delegate_;
	std::string id = ovosch_to_std([[peripheral identifier] UUIDString]);
	if (error != nil) {
		emit_error(id, map_error(error, ErrorCode::SERVICE_NOT_FOUND), describe(error, "discoverServices"));
		return;
	}
	NSArray<CBService *> *services = [peripheral services];
	if (services == nil || [services count] == 0) {
		emit_services(peripheral);
		return;
	}
	[[delegate pendingCharacteristicDiscoveries] setObject:@([services count]) forKey:[[peripheral identifier] UUIDString]];
	for (CBService *service in services) {
		[peripheral discoverCharacteristics:nil forService:service];
	}
}

void AppleBackend::handle_characteristics_discovered(CBPeripheral *peripheral, CBService *service, NSError *error) {
	OvoschBleCentralDelegate *delegate = delegate_;
	NSString *identifier = [[peripheral identifier] UUIDString];
	if (error != nil) {
		emit_error(ovosch_to_std(identifier), map_error(error, ErrorCode::CHARACTERISTIC_NOT_FOUND),
				describe(error, "discoverCharacteristics"));
	}
	NSNumber *pending = [[delegate pendingCharacteristicDiscoveries] objectForKey:identifier];
	NSInteger left = pending != nil ? [pending integerValue] - 1 : 0;
	if (left > 0) {
		[[delegate pendingCharacteristicDiscoveries] setObject:@(left) forKey:identifier];
		return;
	}
	[[delegate pendingCharacteristicDiscoveries] removeObjectForKey:identifier];
	emit_services(peripheral);
}

void AppleBackend::handle_value_updated(CBPeripheral *peripheral, CBCharacteristic *characteristic, NSError *error) {
	OvoschBleCentralDelegate *delegate = delegate_;
	std::string id = ovosch_to_std([[peripheral identifier] UUIDString]);
	std::string ch = ovosch_to_std(ovosch_cbuuid_string([characteristic UUID]));
	NSString *key = ovosch_read_key(peripheral, characteristic);
	bool was_read = [[delegate pendingReads] containsObject:key];
	if (was_read) {
		[[delegate pendingReads] removeObject:key];
	}
	if (error != nil) {
		emit_error(id, map_error(error, ErrorCode::READ_FAILED), describe(error, was_read ? "readValue" : "notification"));
		return;
	}
	std::vector<uint8_t> bytes = ovosch_bytes_from([characteristic value]);
	if (was_read) {
		notify([&](BleListener *l) { l->on_characteristic_read(id, ch, bytes); });
	} else {
		notify([&](BleListener *l) { l->on_notification(id, ch, bytes); });
	}
}

void AppleBackend::handle_write_done(CBPeripheral *peripheral, CBCharacteristic *characteristic, NSError *error) {
	std::string id = ovosch_to_std([[peripheral identifier] UUIDString]);
	std::string ch = ovosch_to_std(ovosch_cbuuid_string([characteristic UUID]));
	bool ok = error == nil;
	// Один отказ — одно событие write_done(false); повтор решает GDScript (REQ-NFR-01 крит. 2).
	// Сигнал error(WRITE_FAILED) здесь не шлётся: BleTrainer считал бы его вторым отказом.
	if (!ok) {
		NSLog(@"ovosch_ble: %@", ovosch_to_ns(describe(error, "writeValue")));
	}
	notify([&](BleListener *l) { l->on_write_done(id, ch, ok); });
}

void AppleBackend::handle_notify_state(CBPeripheral *peripheral, CBCharacteristic *characteristic, NSError *error) {
	if (error == nil) {
		return;
	}
	std::string id = ovosch_to_std([[peripheral identifier] UUIDString]);
	emit_error(id, ErrorCode::SUBSCRIBE_FAILED, describe(error, "setNotifyValue"));
}

// ---------------------------------------------------------------------------
// Внутреннее
// ---------------------------------------------------------------------------

void AppleBackend::emit_error(const std::string &id, ErrorCode code, const std::string &message) {
	notify([&](BleListener *l) { l->on_error(id, code, message); });
}

void AppleBackend::emit_services(CBPeripheral *peripheral) {
	std::string id = ovosch_to_std([[peripheral identifier] UUIDString]);
	std::vector<ServiceInfo> services;
	for (CBService *service in [peripheral services]) {
		ServiceInfo info;
		info.uuid = ovosch_to_std(ovosch_cbuuid_string([service UUID]));
		for (CBCharacteristic *c in [service characteristics]) {
			info.characteristic_uuids.push_back(ovosch_to_std(ovosch_cbuuid_string([c UUID])));
		}
		services.push_back(info);
	}
	notify([&](BleListener *l) { l->on_services_discovered(id, services); });
}

ErrorCode AppleBackend::map_error(NSError *error, ErrorCode fallback) {
	if (error == nil) {
		return fallback;
	}
	if ([[error domain] isEqualToString:CBErrorDomain]) {
		switch ([error code]) {
			case CBErrorConnectionTimeout:
				return ErrorCode::TIMEOUT;
			case CBErrorConnectionFailed:
			case CBErrorPeripheralDisconnected:
				return ErrorCode::CONNECTION_FAILED;
			case CBErrorNotConnected:
				return ErrorCode::NOT_CONNECTED;
			case CBErrorUnknownDevice:
				return ErrorCode::DEVICE_NOT_FOUND;
			default:
				return fallback;
		}
	}
	return fallback;
}

std::string AppleBackend::describe(NSError *error, const char *context) {
	std::string out = std::string("CoreBluetooth: ") + context;
	if (error != nil) {
		out += ": " + ovosch_to_std([error localizedDescription]) + " (" + ovosch_to_std([error domain]) + " " +
				std::to_string(static_cast<long>([error code])) + ")";
	}
	return out;
}

CBPeripheral *AppleBackend::peripheral_or_error(const std::string &id, bool must_be_connected) {
	OvoschBleCentralDelegate *delegate = delegate_;
	CBPeripheral *p = [[delegate peripherals] objectForKey:ovosch_to_ns(id)];
	if (p == nil) {
		emit_error(id, ErrorCode::DEVICE_NOT_FOUND, "CoreBluetooth: peripheral not found: " + id);
		return nil;
	}
	if (must_be_connected && [p state] != CBPeripheralStateConnected) {
		emit_error(id, ErrorCode::NOT_CONNECTED, "CoreBluetooth: peripheral is not connected: " + id);
		return nil;
	}
	return p;
}

CBCharacteristic *AppleBackend::characteristic_or_error(CBPeripheral *peripheral, const std::string &id,
		const std::string &service_uuid, const std::string &char_uuid) {
	OvoschBleCentralDelegate *delegate = delegate_;
	CBCharacteristic *c = [delegate characteristicOf:peripheral service:ovosch_to_ns(service_uuid) characteristic:ovosch_to_ns(char_uuid)];
	if (c == nil) {
		bool has_service = false;
		NSString *wanted = ovosch_normalize_uuid(ovosch_to_ns(service_uuid));
		for (CBService *s in [peripheral services]) {
			if ([ovosch_cbuuid_string([s UUID]) isEqualToString:wanted]) {
				has_service = true;
				break;
			}
		}
		emit_error(id, has_service ? ErrorCode::CHARACTERISTIC_NOT_FOUND : ErrorCode::SERVICE_NOT_FOUND,
				"CoreBluetooth: " + std::string(has_service ? "characteristic " + char_uuid : "service " + service_uuid) +
						" not found (call discover_services first)");
	}
	return c;
}

#ifdef OVOSCH_BLE_HAS_PLATFORM_BACKEND
std::unique_ptr<BleBackend> create_platform_backend() {
	return create_apple_backend();
}
#endif

std::unique_ptr<BleBackend> create_apple_backend() {
	return std::unique_ptr<BleBackend>(new AppleBackend());
}

} // namespace ovosch

// ---------------------------------------------------------------------------
// Реализация делегата
// ---------------------------------------------------------------------------

@implementation OvoschBleCentralDelegate

- (instancetype)initWithOwner:(ovosch::AppleBackend *)owner {
	self = [super init];
	if (self) {
		_owner = owner;
		_queue = dispatch_queue_create("ovosch.ble", DISPATCH_QUEUE_SERIAL);
		_peripherals = [NSMutableDictionary dictionary];
		_pendingCharacteristicDiscoveries = [NSMutableDictionary dictionary];
		_pendingReads = [NSMutableSet set];
		_requestedDisconnects = [NSMutableSet set];
		_pendingScanServices = nil;
		_scanRequested = NO;
		_central = [[CBCentralManager alloc] initWithDelegate:self queue:_queue options:nil];
	}
	return self;
}

- (CBPeripheral *)peripheralForId:(NSString *)identifier {
	CBPeripheral *p = [_peripherals objectForKey:identifier];
	if (p != nil) {
		return p;
	}
	// Запомненное устройство, которого ещё не было в рекламе: пробуем получить по идентификатору.
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:identifier];
	if (uuid == nil) {
		return nil;
	}
	NSArray<CBPeripheral *> *known = [_central retrievePeripheralsWithIdentifiers:@[ uuid ]];
	if ([known count] == 0) {
		return nil;
	}
	p = [known objectAtIndex:0];
	[_peripherals setObject:p forKey:identifier];
	return p;
}

- (CBCharacteristic *)characteristicOf:(CBPeripheral *)peripheral service:(NSString *)serviceUUID characteristic:(NSString *)charUUID {
	NSString *wantedService = ovosch_normalize_uuid(serviceUUID);
	NSString *wantedChar = ovosch_normalize_uuid(charUUID);
	for (CBService *s in [peripheral services]) {
		if ([wantedService length] > 0 && ![ovosch_cbuuid_string([s UUID]) isEqualToString:wantedService]) {
			continue;
		}
		for (CBCharacteristic *c in [s characteristics]) {
			if ([ovosch_cbuuid_string([c UUID]) isEqualToString:wantedChar]) {
				return c;
			}
		}
	}
	return nil;
}

// --- CBCentralManagerDelegate ---

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
	if (_owner != nullptr) {
		_owner->handle_adapter_state([central state]);
	}
}

- (void)centralManager:(CBCentralManager *)central
	didDiscoverPeripheral:(CBPeripheral *)peripheral
		advertisementData:(NSDictionary<NSString *, id> *)advertisementData
					 RSSI:(NSNumber *)RSSI {
	if (_owner != nullptr) {
		_owner->handle_discovered(peripheral, advertisementData, RSSI);
	}
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
	[peripheral setDelegate:self];
	if (_owner != nullptr) {
		_owner->handle_connected(peripheral);
	}
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
	if (_owner != nullptr) {
		_owner->handle_connect_failed(peripheral, error);
	}
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
	if (_owner != nullptr) {
		_owner->handle_disconnected(peripheral, error);
	}
}

// --- CBPeripheralDelegate ---

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
	if (_owner != nullptr) {
		_owner->handle_services_discovered(peripheral, error);
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
	if (_owner != nullptr) {
		_owner->handle_characteristics_discovered(peripheral, service, error);
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
	if (_owner != nullptr) {
		_owner->handle_value_updated(peripheral, characteristic, error);
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
	if (_owner != nullptr) {
		_owner->handle_write_done(peripheral, characteristic, error);
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
	if (_owner != nullptr) {
		_owner->handle_notify_state(peripheral, characteristic, error);
	}
}

@end
