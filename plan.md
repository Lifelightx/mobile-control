# Developer Control Hub

## Vision

Developer Control Hub is a secure LAN-based desktop management platform that allows a mobile application to monitor and control a developer's workstation.

Unlike traditional remote desktop software, the goal is not to mirror the screen. Instead, it provides developer-focused automation, system management, Docker controls, project launching, terminal access, file management, and extensibility through plugins.

---

# Goals

## Primary Goals

* Control a laptop from a mobile application.
* Provide real-time system monitoring.
* Execute developer workflows remotely.
* Build a modular plugin architecture.
* Ensure secure communication over the local network.
* Design for future cloud support.

---

## Non-Goals (Phase 1)

* Full desktop streaming
* Mouse and keyboard sharing
* Video conferencing
* Internet-accessible remote desktop

---

# Technology Stack

## Mobile

* Flutter
* Dart
* Material 3
* BLoC
* Dio
* WebSocket
* Flutter Secure Storage
* Local Authentication
* mDNS Discovery

---

## Desktop Agent

* Node.js
* TypeScript
* Fastify
* WebSocket (ws)
* Zod
* SQLite
* systeminformation
* node-pty
* dockerode
* simple-git
* chokidar

---

## Communication

* REST API
* WebSocket
* HTTPS
* mDNS (Automatic Discovery)

---

## Security

* JWT Authentication
* Refresh Tokens
* Device Pairing
* TLS
* Permission-based Commands
* Audit Logs

---

# High-Level Architecture

```
Flutter Mobile App
        │
REST + WebSocket
        │
──────── LAN ────────
        │
Desktop Agent
        │
Plugin Manager
        │
──────────────────────────
System Plugin
Docker Plugin
Terminal Plugin
Git Plugin
Files Plugin
Media Plugin
Clipboard Plugin
Automation Plugin
Notification Plugin
```

---

# Repository Structure

```
developer-control-hub/

mobile/
    flutter_app/

agent/
    src/
        plugins/
        routes/
        websocket/
        auth/
        services/
        database/

shared/
    api/
    types/

docs/

scripts/

.github/
```

---

# Development Roadmap

# Phase 1

## Foundation

### Objectives

* Project setup
* Authentication
* Device pairing
* Automatic discovery
* Basic dashboard

### Features

* Mobile connects to laptop
* Laptop registration
* JWT authentication
* Secure pairing
* WebSocket connection
* Health check endpoint

Deliverable:

A connected mobile application showing laptop status.

---

# Phase 2

## System Monitoring

### Features

* CPU Usage
* RAM Usage
* Storage
* Battery
* Temperature
* Network
* Uptime

### APIs

```
GET /system

GET /system/cpu

GET /system/memory

GET /system/storage
```

---

# Phase 3

## Application Manager

Features

* List installed applications
* Open application
* Kill application
* Running processes

Examples

```
Open VS Code

Open Chrome

Open Spotify

Open Terminal
```

---

# Phase 4

## Terminal

Features

* Interactive terminal
* Live output
* Multiple sessions
* Session history

API

```
POST /terminal/session

POST /terminal/input

GET /terminal/history
```

WebSocket

```
terminal:data

terminal:exit

terminal:error
```

---

# Phase 5

## File Manager

Features

* Browse folders
* Upload
* Download
* Rename
* Delete
* Copy
* Move
* Search

Future

* File previews
* ZIP download

---

# Phase 6

## Docker Manager

Features

* Running containers
* Container logs
* Restart
* Stop
* Start
* Stats

Future

* Docker Compose
* Images
* Volumes
* Networks

---

# Phase 7

## Git Manager

Features

* Current branch
* Git status
* Pull
* Push
* Commit
* Stash

Future

* Merge
* Cherry-pick
* Rebase
* GitHub Integration

---

# Phase 8

## Project Launcher

Example

```
Backend Project

↓

Open VS Code

↓

Open Terminal

↓

docker compose up

↓

npm install

↓

npm run dev

↓

Open Browser
```

Configuration

```
{
    "name": "Backend",
    "commands": [
        "code .",
        "docker compose up -d",
        "npm run dev"
    ]
}
```

---

# Phase 9

## Automation Engine

Concept

```
IF

CPU > 90%

THEN

Notify User
```

Another

```
IF

Docker Container Stops

THEN

Restart

Notify User
```

Future

* Cron Jobs
* Event Triggers
* Custom Scripts

---

# Phase 10

## Clipboard Sync

Features

* Phone → Laptop
* Laptop → Phone
* Clipboard history

---

# Phase 11

## Notifications

Examples

* Build completed
* Docker container exited
* Battery low
* Git pull finished
* Backup completed

---

# Phase 12

## Plugin System

Plugin Interface

```ts
interface Plugin {
    id: string;

    init(): Promise<void>;

    registerRoutes(app): Promise<void>;

    registerSockets(io): Promise<void>;

    dispose(): Promise<void>;
}
```

Plugins

```
system

docker

terminal

files

git

clipboard

notifications

automation

mongodb

kubernetes
```

---



# Mobile Screens

* Splash
* Pair Device
* Login
* Dashboard
* System Monitor
* Terminal
* Docker
* Git
* File Manager
* Automations
* Notifications
* Settings

---


# Phase 13

## Biometric Laptop Unlock

### Goal

Allow a trusted mobile device to unlock the paired laptop after successful biometric authentication on the phone.

---

## User Flow

1. User opens the mobile application.
2. Taps **Unlock Laptop**.
3. Phone requests fingerprint authentication.
4. Android/iOS validates the fingerprint locally.
5. If successful, the app generates a signed unlock request.
6. The laptop agent validates:

   * Device identity
   * JWT
   * Device certificate
   * Request timestamp
   * Request signature
7. If all checks pass, the laptop unlocks the active user session.

---

## Security Requirements

* Fingerprint data never leaves the phone.
* The application only receives a biometric success/failure result.
* Every paired phone has a unique device certificate.
* All communication uses HTTPS/TLS.
* Unlock requests expire after 30 seconds.
* Every unlock request includes:

  * Nonce
  * Timestamp
  * JWT
  * Digital signature
* Replay attacks are rejected.
* Every unlock attempt is recorded in the audit log.

---

## API

```http
POST /auth/unlock
```

Request

```json
{
  "deviceId": "...",
  "timestamp": "...",
  "nonce": "...",
  "signature": "..."
}
```

Response

```json
{
  "success": true
}
```

---

## Mobile UI

```text
───────────────
Developer Hub

🔒 Laptop Locked

[ Unlock Laptop ]
───────────────
```

After tapping:

```text
Authenticate with Fingerprint
```

Then:

```text
Laptop Unlocked Successfully
```

---

## Desktop Agent

Responsibilities

* Verify JWT
* Verify device certificate
* Validate timestamp
* Validate request signature
* Verify nonce
* Check user permissions
* Unlock desktop session
* Write audit log

---

## Future Enhancements

* Face ID support (iOS)
* Android Face Unlock support (where available)
* Apple Watch / Wear OS trusted-device unlock
* Proximity-based auto unlock
* Auto-lock when the paired phone leaves the Wi-Fi network
* Require both the same Wi-Fi network and biometric authentication for maximum security

# Database

SQLite

Tables

```
devices

users

audit_logs

terminal_sessions

automation_rules

saved_commands

notifications

settings
```

---

# API Design

REST

```
GET

POST

PUT

DELETE
```

Realtime

```
WebSocket

System Updates

Logs

Terminal Output

Notifications

Automation Events
```

---

# Security Checklist

* JWT Authentication
* Refresh Tokens
* HTTPS
* TLS Certificates
* Secure Pairing
* Token Rotation
* Command Validation
* Command Allowlist
* Permission System
* Audit Logging
* Rate Limiting
* Input Validation

---

# Testing

## Unit

* Services
* Plugins
* Authentication

## Integration

* REST APIs
* WebSocket
* Database

## End-to-End

* Pairing
* Login
* Docker
* Terminal
* File Upload
* Notifications

---

# Stretch Goals

* AI Assistant
* Voice Commands
* Wake-on-LAN
* SSH Manager
* Kubernetes Dashboard
* MongoDB Replica Dashboard
* Multi-PC Management
* Plugin Marketplace
* Screen Streaming (WebRTC)
* Remote Keyboard
* Remote Touchpad

---

# Future AI Features

Examples

```
"Open my backend workspace."

"Restart MongoDB."

"Show Docker logs."

"Deploy my application."

"Run database backup."

"Check replica lag."

"Summarize today's system events."
```

The AI layer should translate natural language into validated plugin actions rather than executing arbitrary shell commands directly.

---

# Success Criteria

* Mobile app pairs with desktop in under 30 seconds.
* Automatic LAN discovery without manual IP entry.
* Dashboard updates in real time with latency under 500 ms.
* Terminal streaming feels responsive for interactive use.
* Plugin architecture allows new capabilities without modifying the core agent.
* All privileged actions are authenticated, authorized, and recorded in audit logs.
* The platform is useful enough to become part of the daily development workflow.
