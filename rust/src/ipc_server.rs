/// Unix Domain Socket IPC server.
///
/// Listens on /run/devcontrol/input.sock, accepts framed binary packets from
/// the Node input service, decodes them, and dispatches to the virtual devices.
///
/// Framing: each message is prefixed with a 4-byte big-endian length, followed
/// by the raw InputPacket bytes. This lets us handle multiple packets in a
/// single read/write cycle.

use anyhow::Result;
use std::path::Path;
use tokio::io::{AsyncReadExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tracing::{error, info, warn};

use crate::input_device::{VirtualKeyboard, VirtualMouse};
use crate::protocol::{InputPacket, Opcode};

pub const SOCKET_PATH: &str = "/run/devcontrol/input.sock";

/// Start the Unix Domain Socket server. Runs forever.
pub async fn run_server(
    mut mouse: VirtualMouse,
    mut keyboard: VirtualKeyboard,
) -> Result<()> {
    // Remove stale socket file
    if Path::new(SOCKET_PATH).exists() {
        std::fs::remove_file(SOCKET_PATH)?;
    }

    // Ensure parent directory exists
    if let Some(parent) = Path::new(SOCKET_PATH).parent() {
        std::fs::create_dir_all(parent)?;
    }

    let listener = UnixListener::bind(SOCKET_PATH)?;
    info!("[IPC] Listening on {}", SOCKET_PATH);

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                info!("[IPC] Node input service connected");
                // We have a single Node client; handle it inline (no multi-client needed)
                if let Err(e) = handle_connection(stream, &mut mouse, &mut keyboard).await {
                    warn!("[IPC] Connection error: {}. Waiting for reconnect.", e);
                }
                info!("[IPC] Connection closed. Waiting for Node to reconnect.");
            }
            Err(e) => {
                error!("[IPC] Accept error: {}", e);
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            }
        }
    }
}

/// Read framed packets from the stream and dispatch input events.
/// Frame format: [u32 length BE][packet bytes...]
async fn handle_connection(
    stream: UnixStream,
    mouse: &mut VirtualMouse,
    keyboard: &mut VirtualKeyboard,
) -> Result<()> {
    let mut reader = BufReader::new(stream);

    loop {
        // Read 4-byte frame length
        let mut len_buf = [0u8; 4];
        match reader.read_exact(&mut len_buf).await {
            Ok(_) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                return Ok(()); // Clean disconnect
            }
            Err(e) => return Err(e.into()),
        }

        let frame_len = u32::from_be_bytes(len_buf) as usize;

        if frame_len == 0 || frame_len > 65536 {
            warn!("[IPC] Invalid frame length: {}. Closing.", frame_len);
            return Ok(());
        }

        // Read packet bytes
        let mut packet_buf = vec![0u8; frame_len];
        reader.read_exact(&mut packet_buf).await?;

        match InputPacket::decode(&packet_buf) {
            Ok(packet) => dispatch(packet, mouse, keyboard),
            Err(e) => warn!("[IPC] Decode error: {}", e),
        }
    }
}

/// Dispatch a decoded packet to the appropriate device.
fn dispatch(packet: InputPacket, mouse: &mut VirtualMouse, keyboard: &mut VirtualKeyboard) {
    let result = match packet.opcode {
        Opcode::MouseMove => {
            packet.parse_mouse_move().and_then(|(dx, dy)| mouse.move_rel(dx, dy))
        }
        Opcode::MouseDown => {
            packet.parse_mouse_button().and_then(|btn| mouse.button(btn, true))
        }
        Opcode::MouseUp => {
            packet.parse_mouse_button().and_then(|btn| mouse.button(btn, false))
        }
        Opcode::MouseScroll => {
            packet.parse_scroll().and_then(|(dx, dy)| mouse.scroll(dx, dy))
        }
        Opcode::KeyDown => {
            packet.parse_key().and_then(|code| keyboard.key_down(code))
        }
        Opcode::KeyUp => {
            packet.parse_key().and_then(|code| keyboard.key_up(code))
        }
    };

    if let Err(e) = result {
        warn!("[Dispatch] {:?} error: {}", packet.opcode, e);
    }
}
