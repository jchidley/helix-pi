use system_theme_hx::system_theme_module;

fn main() {
    system_theme_module()
        .emit_package_to_file("libsystem_theme_hx", "system-theme-hx.scm")
        .unwrap()
}
