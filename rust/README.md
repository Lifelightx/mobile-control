# DevControl Input Daemon

Rust binary that creates virtual mouse and keyboard devices via Linux `uinput`
and exposes them over a Unix Domain Socket for the Node agent.

## Prerequisites

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Allow access to /dev/uinput (choose one)
sudo chmod 0660 /dev/uinput
sudo chown root:input /dev/uinput
sudo usermod -aG input $USER   # then re-login
```

## Build

```bash
cd saturday/rust
cargo build --release
```

Binary will be at `target/release/devcontrol-input`.

## Run

```bash
# The socket is created at /run/devcontrol/input.sock
# That directory needs to exist
sudo mkdir -p /run/devcontrol
sudo chown $USER /run/devcontrol

# Start the daemon (keep running in background)
./target/release/devcontrol-input
```

Or as a systemd service (`/etc/systemd/system/devcontrol-input.service`):

```ini
[Unit]
Description=DevControl Input Daemon
After=network.target

[Service]
ExecStart=/path/to/devcontrol-input
Restart=always
RestartSec=1
User=YOUR_USER
Group=input
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now devcontrol-input
```

## Architecture

```
Flutter → binary WebSocket → Node /ws/input
                                 │
                           BinaryDecoder
                                 │
                    ┌────────────┴────────────┐
                    │                         │
               MouseQueue              KeyboardQueue
             ScrollQueue               (immediate)
            (240 Hz tick)
                    │
               IpcClient (Unix socket)
                    │
          Rust devcontrol-input
                    │
            /dev/uinput
                    │
           Linux Desktop Input
```

## Socket Protocol

Each message sent by Node to the daemon is length-framed:

```
[4 bytes: u32 BE length][N bytes: InputPacket]
```

`InputPacket` uses the same layout as the Flutter `BinaryEncoder`:

```
[0]    u8   Version (1)
[1]    u8   Opcode
[2-3]  u16  Sequence
[4-7]  u32  Timestamp (ms)
[8-11] u32  Payload length
[12..] Payload
```
