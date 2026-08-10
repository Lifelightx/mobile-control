# Developer Control Hub — Bluetooth Fallback Transport Plan

## Document Status

- **Status:** Planned
- **Primary Transport:** Wi-Fi / WebSocket
- **Secondary Transport:** Bluetooth Classic / RFCOMM
- **Desktop:** Node.js Agent on Linux
- **Mobile:** Flutter App with native Android Bluetooth integration
- **Goal:** Keep the existing Developer Control Hub functionality working when Wi-Fi is unavailable, without duplicating business logic.

---

# 1. Objective

Add Bluetooth communication as a **secondary transport** for the Developer Control Hub.

The system should behave like this:

```text
                 Developer Control Hub
                         |
                  Transport Manager
                    /           \
                   /             \
              Wi-Fi             Bluetooth
           WebSocket            RFCOMM
              |                   |
              +---------+---------+
                        |
                 Shared Protocol
                        |
                 Message Router
                        |
        +---------------+----------------+
        |       |       |       |        |
     System  Terminal Docker Files Clipboard
```

### Core principle

Bluetooth must be a **transport**, not a second application protocol.

Existing features such as Terminal, Docker, Clipboard, Notifications, Automation, and File Manager must not contain Bluetooth-specific business logic.

---

# 2. Current System

The current Developer Control Hub already contains:

- LAN discovery using mDNS/Zeroconf
- Secure pairing
- JWT authentication
- WebSocket communication
- SQLite persistence
- System monitoring
- Application/process manager
- Interactive terminal
- File manager
- Docker manager
- Automation engine
- Clipboard synchronization
- Notification mirroring
- Missed notification synchronization

The Bluetooth implementation must integrate without breaking these features.

---

# 3. Target Architecture

## Desktop Agent

```text
Node.js Agent
│
├── Transport
│   ├── TransportManager
│   │
│   ├── WiFiTransport
│   │   └── WebSocket Server
│   │
│   └── BluetoothTransport
│       └── RFCOMM Server
│
├── Protocol
│   ├── Frame Encoder
│   ├── Frame Decoder
│   ├── Message Encoder
│   └── Message Decoder
│
├── Authentication
│
├── Message Router
│
└── Feature Services
    ├── System
    ├── Process
    ├── Terminal
    ├── Files
    ├── Docker
    ├── Clipboard
    ├── Notifications
    └── Automation
```

## Flutter App

```text
Flutter App
│
├── ControlHubClient
│
├── TransportManager
│   │
│   ├── WiFiTransport
│   │   └── WebSocket
│   │
│   └── BluetoothTransport
│       └── Native Android Bluetooth
│
├── Protocol
│
└── Feature Screens
    ├── Dashboard
    ├── Apps
    ├── Terminal
    ├── Files
    ├── Docker
    ├── Clipboard
    ├── Notifications
    └── Automation
```

---

# 4. Why Bluetooth Classic RFCOMM

Bluetooth Classic RFCOMM is preferred over BLE for the fallback transport because the application needs a reliable stream for:

- Terminal input/output
- Docker logs
- File transfers
- Notifications
- Clipboard synchronization
- Commands and responses
- General request/response traffic

BLE should not be used as the primary transport for these workloads.

The intended architecture is:

```text
Wi-Fi
  -> WebSocket
  -> Shared Protocol

Bluetooth
  -> RFCOMM
  -> Shared Protocol
```

---

# 5. Phase 1 — Transport Abstraction

## Objective

Separate the existing WebSocket implementation from application logic.

### Tasks

- Create a common `Transport` interface.
- Create `TransportManager`.
- Move existing WebSocket functionality behind `WiFiTransport`.
- Ensure all existing features communicate through `ControlHubClient` / transport abstraction.
- Remove direct WebSocket dependencies from feature services.

### Example interface

```typescript
export interface Transport {
  readonly type: TransportType;

  connect(): Promise<void>;
  disconnect(): Promise<void>;

  send(data: Buffer): Promise<void>;

  onData(handler: (data: Buffer) => void): void;
  onClose(handler: () => void): void;

  isConnected(): boolean;
}
```

```typescript
export enum TransportType {
  WIFI = "wifi",
  BLUETOOTH = "bluetooth",
}
```

### Acceptance Criteria

- All existing functionality works exactly as before.
- No feature service directly depends on WebSocket.
- Transport can be replaced without changing business logic.

---

# 6. Phase 2 — Shared Message Protocol

## Objective

Create a transport-independent application protocol.

## Message Envelope

```json
{
  "version": 1,
  "id": "01J...",
  "type": "request",
  "action": "docker.container.list",
  "timestamp": 1786270000000,
  "payload": {}
}
```

## Response

```json
{
  "version": 1,
  "id": "01J...",
  "type": "response",
  "action": "docker.container.list",
  "timestamp": 1786270000100,
  "payload": {}
}
```

## Event

```json
{
  "version": 1,
  "id": "01J...",
  "type": "event",
  "action": "system.telemetry",
  "timestamp": 1786270000200,
  "payload": {
    "cpu": 34.2,
    "memory": 67.1
  }
}
```

### Required Fields

- `version`
- `id`
- `type`
- `action`
- `timestamp`
- `payload`

### Acceptance Criteria

The same message must work over:

```text
WebSocket
RFCOMM
```

without changing the message structure.

---

# 7. Phase 3 — RFCOMM Framing

## Objective

Implement message framing because RFCOMM is a byte stream and does not guarantee application-level message boundaries.

Do not assume:

```typescript
socket.on("data", data => {
  JSON.parse(data.toString());
});
```

is safe.

## Frame Format

```text
+------------------+----------------------+
| 4-byte length    | payload              |
| unsigned integer | JSON / binary data   |
+------------------+----------------------+
```

Example:

```text
[4-byte payload length][payload]
```

## Receiver

```text
Read 4 bytes
    ↓
Determine payload length
    ↓
Read exactly N bytes
    ↓
Decode payload
    ↓
Dispatch message
```

## Requirements

- Handle fragmented frames.
- Handle multiple frames in one read.
- Validate maximum frame size.
- Reject malformed lengths.
- Prevent memory exhaustion.
- Support binary payloads.
- Unit test partial reads and combined frames.

---

# 8. Phase 4 — Linux Bluetooth Server

## Objective

Implement Bluetooth Classic RFCOMM on the Linux desktop agent.

Architecture:

```text
Node.js
   ↓
BluetoothTransport
   ↓
RFCOMM
   ↓
BlueZ
   ↓
Linux Bluetooth Adapter
```

## Tasks

- Detect Bluetooth adapter.
- Detect Bluetooth availability.
- Configure service identity.
- Create RFCOMM server.
- Accept incoming connections.
- Associate connection with a Control Hub device.
- Implement connection lifecycle.
- Implement framing.
- Implement heartbeat.
- Implement disconnect handling.

## Suggested Module

```text
agent/src/transport/bluetooth/

├── bluetooth-server.ts
├── bluetooth-transport.ts
├── bluetooth-device.ts
├── bluetooth-framing.ts
└── bluetooth-errors.ts
```

## Initial Test

Before integrating the complete application protocol:

```text
Android
   ↕
Bluetooth RFCOMM
   ↕
Linux Agent
```

Exchange:

```text
PING
PONG
```

Then test:

```text
JSON
Binary
Large payload
Fragmented payload
Multiple messages
```

---

# 9. Phase 5 — Android Bluetooth Client

## Objective

Implement a reliable Android RFCOMM client.

Recommended structure:

```text
Flutter
   ↓
BluetoothTransport
   ↓
MethodChannel
   ↓
Kotlin BluetoothService
   ↓
BluetoothSocket
```

## Native Responsibilities

Kotlin should handle:

- Bluetooth adapter access
- Permission handling
- Device discovery
- Paired device lookup
- RFCOMM connection
- Input stream
- Output stream
- Connection lifecycle
- Reconnection
- Bluetooth errors

Flutter should handle:

- Transport abstraction
- Application protocol
- Authentication state
- UI state
- Feature behavior

## Android Permission Requirements

Handle the permissions required by the Android version in use, including Bluetooth scan/connect permissions on modern Android versions.

Do not request permissions unnecessarily.

---

# 10. Phase 6 — Bluetooth Discovery

## Objective

Allow the mobile application to discover the desktop agent over Bluetooth.

## Discovery Flow

```text
Open Developer Control Hub
        ↓
Check Wi-Fi
        ↓
Wi-Fi unavailable?
        ↓
Check known Bluetooth devices
        ↓
Agent found?
   /            \
 yes             no
  |               |
  ↓               ↓
Connect       Bluetooth discovery
```

## Important Rules

- Do not continuously scan.
- Prefer already paired devices.
- Cache known devices.
- Identify the Control Hub agent using a stable application-level ID.
- Do not use Bluetooth MAC address as the permanent application identity.
- Show transport type in the UI.

Example:

```text
Developer Control Hub
Connected
Transport: Bluetooth
```

---

# 11. Phase 7 — Authentication Over Bluetooth

Bluetooth pairing must not replace application authentication.

Use two security layers:

```text
Bluetooth Security
       +
Developer Control Hub Authentication
```

## Handshake

```json
{
  "type": "auth",
  "protocolVersion": 1,
  "transport": "bluetooth",
  "deviceId": "phone-01",
  "token": "...",
  "nonce": "..."
}
```

## Authentication Flow

```text
Bluetooth Connection
        ↓
Protocol Handshake
        ↓
Validate Version
        ↓
Identify Device
        ↓
Validate Authentication
        ↓
Validate Trust
        ↓
Create Session
        ↓
CONNECTED
```

## Requirements

- Reuse existing authentication where possible.
- Do not automatically trust every paired Bluetooth device.
- Maintain trusted device records.
- Reject unauthenticated commands.
- Record authentication failures.
- Prevent replay of old authentication messages.

---

# 12. Phase 8 — Transport Manager

## Objective

Automatically select the best available transport.

## Priority

```text
1. Wi-Fi
2. Bluetooth
3. Offline
```

## Connection State

```typescript
enum ConnectionState {
  DISCONNECTED,
  DISCOVERING,
  CONNECTING,
  AUTHENTICATING,
  CONNECTED,
  RECONNECTING,
  SWITCHING_TRANSPORT,
}
```

## Transport Selection

```text
                Start
                  |
                  v
           Wi-Fi available?
             /          \
           yes           no
            |             |
            v             v
      Connect Wi-Fi   Bluetooth
            |             |
         Success?       Available?
         /     \         /     \
       yes      no     yes      no
        |        |      |        |
        v        +------v        v
    CONNECTED       CONNECTED   OFFLINE
      Wi-Fi         Bluetooth
```

---

# 13. Phase 9 — Automatic Fallback

## Scenario 1: Wi-Fi unavailable

```text
Wi-Fi unavailable
       ↓
Bluetooth available
       ↓
Connect Bluetooth
       ↓
Authenticate
       ↓
Resume session
```

## Scenario 2: Wi-Fi connection drops

```text
Wi-Fi connected
       ↓
Connection lost
       ↓
Reconnect Wi-Fi
       ↓
If retry threshold exceeded
       ↓
Bluetooth fallback
```

## Scenario 3: Wi-Fi returns

```text
Bluetooth active
       ↓
Wi-Fi becomes available
       ↓
Connect Wi-Fi
       ↓
Authenticate
       ↓
Switch active transport
       ↓
Close Bluetooth
```

## Important

Do not switch transports immediately on every transient network error.

Use:

- Connection timeout
- Retry count
- Exponential backoff
- Jitter
- Health checks

---

# 14. Phase 10 — Session Management

## Objective

Make transport switching and reconnection reliable.

Create:

```text
sessionId
```

Example:

```json
{
  "sessionId": "01JABC..."
}
```

On reconnection:

```json
{
  "type": "resume",
  "sessionId": "01JABC..."
}
```

## Session Requirements

- Unique session ID.
- Connection state.
- Last activity.
- Last received sequence.
- Last acknowledged sequence.
- Active transport.
- Device ID.
- Authentication state.

---

# 15. Phase 11 — Message Reliability

Add:

- Message IDs
- Sequence numbers
- Request timeout
- Response correlation
- Duplicate detection
- Heartbeat
- Connection timeout
- Backpressure
- Maximum message size

Example:

```text
Request
  ↓
messageId
  ↓
Agent
  ↓
Response
  ↓
same messageId
```

## Request Timeout

Example policy:

```text
Normal request:       10 seconds
Terminal command:     configurable
File operation:       configurable
Authentication:       10 seconds
Heartbeat:            5 seconds
```

Avoid hardcoding timeouts inside individual feature modules.

---

# 16. Phase 12 — Bluetooth Bandwidth Management

Bluetooth will be slower than Wi-Fi.

Introduce message priorities:

```typescript
enum MessagePriority {
  CRITICAL = 0,
  NORMAL = 1,
  BULK = 2,
}
```

## Critical

- Authentication
- Commands
- Responses
- Session control

## Normal

- Telemetry
- Notifications
- Clipboard
- Process information

## Bulk

- Files
- Docker logs
- Large responses

---

# 17. Phase 13 — Bluetooth-Aware Telemetry

Do not send the same telemetry frequency over Bluetooth.

## Wi-Fi

```text
CPU:       every 1 second
Memory:    every 1 second
Docker:    every 1 second
```

## Bluetooth

```text
CPU:       every 3-5 seconds
Memory:    every 3-5 seconds
Docker:    every 5 seconds
```

The exact interval should be configurable.

---

# 18. Phase 14 — Terminal Support

The terminal should continue to use the same PTY implementation.

```text
PTY
 ↓
Terminal Stream
 ↓
Transport
 ↓
Flutter xterm
```

The PTY layer must not know whether the transport is:

```text
Wi-Fi
Bluetooth
```

## Test

- Start terminal.
- Type command.
- Receive output.
- Handle ANSI colors.
- Handle large output.
- Handle Ctrl+C.
- Handle disconnect.
- Reconnect.
- Verify terminal session behavior.

---

# 19. Phase 15 — Docker Support

All existing Docker functionality must work over Bluetooth:

- List containers
- Start
- Stop
- Restart
- Inspect
- Stats
- Logs

## Docker Logs

Docker logs can generate high traffic.

Bluetooth mode should support:

- Throttling
- Bounded buffers
- Backpressure
- Log truncation
- Explicit stream cancellation

Do not allow unlimited log buffering in memory.

---

# 20. Phase 16 — File Transfer

Use chunked binary transfer.

## Start

```json
{
  "type": "file.start",
  "fileId": "01J...",
  "name": "backup.zip",
  "size": 524288000,
  "sha256": "..."
}
```

## Chunks

```text
chunk 0
chunk 1
chunk 2
...
```

## Completion

```json
{
  "type": "file.complete",
  "fileId": "01J...",
  "sha256": "..."
}
```

## Requirements

- Fixed chunk size.
- Sequence numbers.
- Checksum.
- Progress.
- Cancellation.
- Timeout.
- Resume support.
- Duplicate chunk detection.
- Disk-space validation.
- Maximum file size.
- Temporary file.
- Atomic final rename.

Do not write directly to the destination file while an untrusted transfer is incomplete.

---

# 21. Phase 17 — Clipboard

Clipboard synchronization works over Bluetooth with the existing protocol.

Example:

```text
Phone
 ↓
clipboard.set
 ↓
Bluetooth
 ↓
Agent
 ↓
Linux Clipboard
```

And:

```text
Linux Clipboard
 ↓
clipboard.changed
 ↓
Bluetooth
 ↓
Phone
```

Keep the existing clipboard history behavior.

---

# 22. Phase 18 — Notification Mirroring

Notification mirroring should continue to work over Bluetooth.

```text
Linux D-Bus
     ↓
Notification Service
     ↓
Message Router
     ↓
Bluetooth
     ↓
Flutter
     ↓
Native Notification
```

When disconnected:

```text
Notification
    ↓
SQLite
    ↓
Reconnect
    ↓
Missed Notification Sync
```

The existing missed-notification mechanism should remain transport-independent.

---

# 23. Phase 19 — Automation

Automations must continue executing locally on the desktop.

Bluetooth should only be used for:

- Creating automation
- Updating automation
- Deleting automation
- Enabling/disabling rules
- Receiving automation events

Do not make automation execution depend on the phone connection.

Correct architecture:

```text
Desktop Agent
     |
Automation Engine
     |
     +---- executes locally
     |
     +---- sends event if mobile connected
```

This ensures automations continue working while the phone is disconnected.

---

# 24. Phase 20 — Database Changes

Add Bluetooth-specific information without coupling application identity to Bluetooth hardware addresses.

Possible schema:

```sql
CREATE TABLE bluetooth_devices (
    id TEXT PRIMARY KEY,
    device_name TEXT,
    device_address TEXT,
    trusted INTEGER NOT NULL DEFAULT 0,
    last_seen_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
```

Add transport information to audit logs:

```text
transport = wifi
transport = bluetooth
```

Example:

```text
device_id: phone-01
transport: bluetooth
event: docker.container.restart
timestamp: ...
```

---

# 25. Phase 21 — Security Hardening

Before production:

## Authentication

- Device authentication
- Token validation
- Session validation
- Session expiration
- Replay protection

## Bluetooth

- Authenticated pairing
- Encrypted Bluetooth connection
- Trusted device list
- Device revocation

## Protocol

- Maximum frame size
- Input validation
- Schema validation
- Rate limiting
- Request limits
- Binary payload limits

## File System

- Path traversal protection
- Canonical path validation
- Permission checks
- File size limits
- Atomic writes

## Terminal

- Authentication required
- Explicit user authorization
- Audit logging
- Session cleanup

Bluetooth is not a magical security blanket. A paired device should still be treated as an untrusted application client until the Control Hub authentication succeeds.

---

# 26. Phase 22 — Observability

Add transport metrics.

## Metrics

```text
controlhub_transport_connections_total
controlhub_transport_disconnects_total
controlhub_transport_messages_total
controlhub_transport_bytes_sent
controlhub_transport_bytes_received
controlhub_transport_latency_ms
controlhub_transport_reconnects_total
controlhub_transport_switches_total
```

## Labels

```text
transport=wifi
transport=bluetooth
```

## Logs

Example:

```text
INFO  Transport connected
      transport=bluetooth
      device=phone-01

INFO  Transport switched
      from=bluetooth
      to=wifi

WARN  Bluetooth connection lost
      reason=timeout
```

---

# 27. Phase 23 — Testing Strategy

## Unit Tests

Test:

- Frame encoder
- Frame decoder
- Partial frames
- Multiple frames
- Invalid frame length
- Message encoding
- Message decoding
- Sequence handling
- Duplicate detection
- Transport selection

## Integration Tests

```text
Flutter
   ↕
Bluetooth
   ↕
Linux Agent
```

Test:

- Authentication
- System info
- Telemetry
- Process manager
- Clipboard
- Docker
- Terminal
- File transfer
- Notifications
- Automation

## Failure Tests

Test:

- Bluetooth disabled
- Bluetooth adapter removed
- Device disconnected
- Phone sleeps
- Agent restarts
- App restarts
- Wi-Fi disappears
- Wi-Fi returns
- Bluetooth disappears
- Authentication failure
- Invalid message
- Large message
- Slow consumer
- Network/transport interruption during file transfer

---

# 28. Transport Switching Test Matrix

| Scenario | Expected Transport |
|---|---|
| Wi-Fi available | Wi-Fi |
| Wi-Fi unavailable, Bluetooth available | Bluetooth |
| Wi-Fi drops | Bluetooth after retry policy |
| Wi-Fi returns | Wi-Fi |
| Bluetooth unavailable | Wi-Fi only |
| Both unavailable | Offline |
| Bluetooth connection drops | Reconnect / Wi-Fi |
| Agent restarts | Reconnect |
| App restarts | Reconnect + authenticate |
| Authentication fails | Reject connection |

---

# 29. Feature Compatibility Matrix

| Feature | Wi-Fi | Bluetooth | Notes |
|---|---:|---:|---|
| System info | Yes | Yes | |
| Live telemetry | Yes | Yes | Lower frequency on BT |
| Process manager | Yes | Yes | |
| Terminal | Yes | Yes | Stream |
| File browsing | Yes | Yes | |
| File upload | Yes | Yes | Chunked |
| File download | Yes | Yes | Chunked |
| Docker control | Yes | Yes | |
| Docker stats | Yes | Yes | Lower frequency |
| Docker logs | Yes | Yes | Throttled |
| Clipboard | Yes | Yes | |
| Notifications | Yes | Yes | |
| Automation | Yes | Yes | Executes locally |
| Screen streaming | Yes | No | Not suitable for BT fallback |
| Video | Yes | No | Not suitable for BT fallback |

---

# 30. Recommended Project Structure

## Node.js Agent

```text
src/
├── transport/
│   ├── transport.ts
│   ├── transport-manager.ts
│   ├── transport-state.ts
│   │
│   ├── wifi/
│   │   └── websocket-transport.ts
│   │
│   └── bluetooth/
│       ├── bluetooth-server.ts
│       ├── bluetooth-transport.ts
│       ├── bluetooth-device.ts
│       ├── bluetooth-framing.ts
│       └── bluetooth-errors.ts
│
├── protocol/
│   ├── envelope.ts
│   ├── encoder.ts
│   ├── decoder.ts
│   ├── frame-decoder.ts
│   └── message-validator.ts
│
├── auth/
│   ├── authentication-service.ts
│   └── session-service.ts
│
├── router/
│   └── message-router.ts
│
└── services/
    ├── system/
    ├── process/
    ├── terminal/
    ├── files/
    ├── docker/
    ├── clipboard/
    ├── notifications/
    └── automation/
```

## Flutter

```text
lib/
├── transport/
│   ├── transport.dart
│   ├── transport_manager.dart
│   ├── transport_state.dart
│   │
│   ├── wifi/
│   │   └── websocket_transport.dart
│   │
│   └── bluetooth/
│       ├── bluetooth_transport.dart
│       └── bluetooth_platform.dart
│
├── protocol/
│   ├── message.dart
│   ├── encoder.dart
│   ├── decoder.dart
│   └── frame_decoder.dart
│
├── auth/
├── services/
└── screens/
```

---

# 31. Recommended Implementation Order

Do not implement all Bluetooth functionality at once.

Follow this order:

```text
Phase 1
Transport abstraction
        ↓
Phase 2
Shared protocol + framing
        ↓
Phase 3
Linux RFCOMM server
        ↓
Phase 4
Android RFCOMM client
        ↓
Phase 5
Authentication
        ↓
Phase 6
Transport Manager
        ↓
Phase 7
Automatic Wi-Fi → Bluetooth fallback
        ↓
Phase 8
Session resumption
        ↓
Phase 9
Terminal
        ↓
Phase 10
Docker
        ↓
Phase 11
Clipboard
        ↓
Phase 12
Notifications
        ↓
Phase 13
File transfers
        ↓
Phase 14
Reliability
        ↓
Phase 15
Security hardening
        ↓
Phase 16
Observability
        ↓
Production testing
```

---

# 32. Milestone Definitions

## Milestone 1 — Transport Layer

- [ ] `Transport` interface
- [ ] `TransportManager`
- [ ] Existing WebSocket wrapped as `WiFiTransport`
- [ ] Feature services no longer depend directly on WebSocket
- [ ] Existing tests pass

## Milestone 2 — Bluetooth Proof of Concept

- [ ] Linux Bluetooth adapter detected
- [ ] RFCOMM server starts
- [ ] Android connects
- [ ] PING/PONG works
- [ ] JSON messages work
- [ ] Binary data works

## Milestone 3 — Protocol

- [ ] Message envelope
- [ ] Frame encoder
- [ ] Frame decoder
- [ ] Partial frame support
- [ ] Multiple frame support
- [ ] Maximum frame size
- [ ] Validation

## Milestone 4 — Authentication

- [ ] Bluetooth connection authentication
- [ ] Device identification
- [ ] Trusted device validation
- [ ] Session creation
- [ ] Session expiration
- [ ] Audit logging

## Milestone 5 — Fallback

- [ ] Wi-Fi primary
- [ ] Bluetooth secondary
- [ ] Automatic fallback
- [ ] Wi-Fi recovery
- [ ] Transport switching
- [ ] UI transport indicator

## Milestone 6 — Feature Integration

- [ ] Dashboard
- [ ] Process manager
- [ ] Terminal
- [ ] Docker
- [ ] Clipboard
- [ ] Notifications
- [ ] Automation
- [ ] File manager

## Milestone 7 — Production Hardening

- [ ] Heartbeat
- [ ] Retry policy
- [ ] Backoff
- [ ] Session resume
- [ ] Backpressure
- [ ] File transfer resume
- [ ] Metrics
- [ ] Security audit
- [ ] Failure testing

---

# 33. Definition of Done

Bluetooth fallback is considered complete only when all of the following are true:

- [ ] Wi-Fi remains the preferred transport.
- [ ] Bluetooth automatically becomes the fallback transport.
- [ ] Existing authentication works over Bluetooth.
- [ ] Existing feature APIs remain unchanged.
- [ ] Terminal works over Bluetooth.
- [ ] Docker control works over Bluetooth.
- [ ] Clipboard works over Bluetooth.
- [ ] Notifications work over Bluetooth.
- [ ] File transfers work with chunking and integrity verification.
- [ ] Wi-Fi recovery automatically switches back from Bluetooth.
- [ ] Sessions can reconnect safely.
- [ ] Duplicate messages are handled.
- [ ] Invalid frames are rejected.
- [ ] Bluetooth failures do not crash the agent.
- [ ] Bluetooth failures do not crash the Flutter app.
- [ ] Security controls are enforced independently of Bluetooth pairing.
- [ ] Transport metrics are available.
- [ ] Audit logs identify the active transport.
- [ ] Failure scenarios have automated/integration coverage.

---

# 34. Non-Goals

The first Bluetooth implementation should **not** attempt to:

- Replace Wi-Fi.
- Stream video.
- Stream the desktop screen.
- Run the entire application over BLE.
- Duplicate business logic.
- Treat Bluetooth pairing as application authentication.
- Keep unlimited logs in memory.
- Send large files as JSON.
- Constantly scan for Bluetooth devices.

---

# 35. Final Architecture Goal

The final system should look like:

```text
                         Mobile App
                             |
                      ControlHubClient
                             |
                      TransportManager
                         /         \
                        /           \
                   Wi-Fi           Bluetooth
                  WebSocket         RFCOMM
                      |               |
                      +-------+-------+
                              |
                       Shared Protocol
                              |
                       Authentication
                              |
                        Session Manager
                              |
                        Message Router
                              |
        +---------------------+----------------------+
        |          |           |          |          |
      System    Terminal     Docker     Files    Clipboard
        |          |           |          |          |
        +----------+-----------+----------+----------+
                              |
                       Desktop Agent
```

The key architectural rule is:

> **Features depend on the message/service layer. The message layer depends on the transport abstraction. The transport abstraction decides whether communication happens over Wi-Fi or Bluetooth.**

That separation is what makes the fallback maintainable as the project grows.