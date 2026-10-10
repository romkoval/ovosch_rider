#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "ovosch_ble.h"
#include "ovosch_window.h"

using namespace godot;

void initialize_ovosch_ble_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(ovosch::OvoschBle);
	GDREGISTER_CLASS(ovosch::OvoschWindow);
}

void uninitialize_ovosch_ble_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
// Точка входа GDExtension (entry_symbol в ovosch_ble.gdextension).
GDExtensionBool GDE_EXPORT ovosch_ble_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_ovosch_ble_module);
	init_obj.register_terminator(uninitialize_ovosch_ble_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
