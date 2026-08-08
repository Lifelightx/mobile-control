# Developer Control Hub

Developer Control Hub is a secure LAN-based desktop management platform that allows a mobile application to monitor and control a developer's workstation. 

This repository contains the Phase 1 (Foundation) implementation of the desktop agent and the mobile application.

---

## Repository Structure

```
saturday/
├── agent/                # Desktop Agent (Fastify, TypeScript, SQLite)
│   ├── src/
│   │   ├── auth/         # Pairing, JWT authentication
│   │   ├── database/     # SQLite DB setup
│   │   ├── services/     # mDNS publishing & hardware stats
│   │   ├── utils/        # Networking helpers
│   │   └── index.ts      # Main Fastify/WS server
│   ├── package.json
│   └── tsconfig.json
├── mobile/               # Mobile Application (Flutter, Dart)
│   └── flutter_app/      # Flutter application files
│       ├── lib/
│       │   ├── bloc/     # BLoC state management
│       │   ├── screens/  # Material 3 screens (Pairing, Dashboard)
│       │   └── main.dart # App entry gate
│       └── pubspec.yaml
└── README.md
```

---

## Getting Started

### Prerequisites
- Node.js (v20+ recommended, tested on v24.14.0)
- Flutter (v3.10+ recommended, tested on v3.38.6)

---

### 1. Launch the Desktop Agent

Initialize the Desktop Agent configuration, start mDNS network discovery, and run the REST/WebSocket gateway:

```bash
cd agent
# Install dependencies (already completed)
npm install

# Run the agent in development watch mode
npm run dev

# Or build and start for production
npm run build
npm start
```

When started, the agent will:
1. Spin up an HTTP server on `http://0.0.0.0:3000`.
2. Generate and output a secure **8-character pairing code** to the console.
3. Start advertising the service as `_devcontrol._tcp` using mDNS.
4. Stream live CPU/RAM/Battery metrics to authenticated WebSocket clients.

---

### 2. Launch the Mobile Client

Run the Flutter client on your mobile device or emulator:

```bash
cd mobile/flutter_app

# Fetch dependencies (already completed)
flutter pub get

# Run the app
flutter run
```

#### How it connects:
1. **Auto-Discovery**: The app automatically scans the local network using mDNS and lists discovered workstations.
2. **Pairing**: Tap the discovered host, enter the pairing code displayed in the agent terminal, and pair. The app will securely persist your pairing token.
3. **Manual Override**: If discovery is disabled on your network, tap "Configure Manually" to enter the IP, Port, and Pairing Code.
4. **Live Dashboard**: Once paired, the app redirects to the real-time telemetry dashboard.
5. **Auto-Reconnect**: The next time you open the app, it automatically attempts to re-authenticate and restore connection to your saved workstation.

---

## Testing

To run the automated tests:

### Test Desktop Agent
```bash
cd agent
npm run test
```

### Test Flutter Client
```bash
cd mobile/flutter_app
flutter test
```
