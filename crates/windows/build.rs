fn main() {
    slint_build::compile("src/app.slint").expect("the Slint UI should compile");

    #[cfg(target_os = "windows")]
    {
        let mut resource = winresource::WindowsResource::new();
        resource.set_icon("app-icon.ico");
        resource.set("ProductName", "WatchBridge");
        resource.set("FileDescription", "WatchBridge desktop client");
        resource
            .compile()
            .expect("the Windows resources should compile");
    }
}
