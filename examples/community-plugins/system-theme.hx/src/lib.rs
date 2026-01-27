use steel::steel_vm::ffi::{FFIModule, FFIValue, RegisterFFIFn};

steel::declare_module!(system_theme_module);

pub fn system_theme_module() -> FFIModule {
    let mut module = FFIModule::new("steel/system_theme");
    module.register_fn("detect", detect);
    module
}

fn detect() -> FFIValue {
    let detected = ::dark_light::detect();
    let theme = match detected {
        Ok(dark_light::Mode::Dark) => "dark",
        Ok(dark_light::Mode::Light) | _ => "light",
    };
    FFIValue::StringV(theme.into())
}
