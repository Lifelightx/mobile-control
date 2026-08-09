mod input_device;
mod ipc_server;
mod protocol;

use anyhow::Result;
use tracing::info;
use tracing_subscriber::EnvFilter;

use input_device::{VirtualKeyboard, VirtualMouse};
use ipc_server::run_server;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize structured logging (RUST_LOG=info by default)
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    info!("[Daemon] DevControl Input Daemon starting...");

    // Create virtual devices
    let mouse = VirtualMouse::new().expect(
        "Failed to create virtual mouse. Is /dev/uinput accessible? \
         Try: sudo chmod 0660 /dev/uinput && sudo chown root:input /dev/uinput",
    );
    let keyboard = VirtualKeyboard::new().expect("Failed to create virtual keyboard.");

    info!("[Daemon] Virtual mouse and keyboard created.");
    info!("[Daemon] Waiting for Node input service on {}...", ipc_server::SOCKET_PATH);

    // Run IPC server — blocks until process is killed
    run_server(mouse, keyboard).await?;

    Ok(())
}
