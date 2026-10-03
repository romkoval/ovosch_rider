// CoreBluetooth-backend контракта BleBackend для macOS и iOS (T-022, REQ-DEV-01 крит. 6,
// REQ-DEV-02 крит. 6–7, REQ-NFR-06 крит. 2). Реализация — apple_backend.mm (Objective-C++, ARC).
// Заголовок намеренно не содержит Objective-C типов: его можно включать из чистого C++.
#pragma once

#include <memory>

#include "../../ble_backend.h"

namespace ovosch {

// Backend поверх CBCentralManager. Все колбэки CoreBluetooth приходят на выделенной
// dispatch_queue; BleListener (OvoschBle) сам переправляет события в главный поток.
std::unique_ptr<BleBackend> create_apple_backend();

} // namespace ovosch
