# Input Subsystem

## Production-Grade Low-Latency Mouse & Keyboard Architecture

---

# Objective

Build a production-grade input subsystem capable of remotely controlling a Linux desktop from a mobile application with latency comparable to a wireless mouse.

This subsystem is responsible **only** for:

* Mouse movement
* Mouse buttons
* Scroll wheel
* Keyboard
* Shortcut keys
* Drag & Drop
* Gesture translation

No authentication, pairing, REST API, plugins, or discovery are included here.

---

# Design Principles

* <10 ms LAN latency
* Zero shell commands
* Binary protocol
* Relative mouse movement
* Lossless keyboard events
* Event coalescing
* Backpressure aware
* Platform abstraction
* Native input injection
* Extensible for Windows/macOS later

---

# Architecture

```text
Flutter Input Layer
        │
Gesture Engine
        │
Binary Encoder
        │
Binary WebSocket
──────────────────────────────────────
Node Input Service
        │
Packet Decoder
        │
Input Scheduler
        │
Input Queue
        │
Unix Domain Socket
──────────────────────────────────────
Rust Input Daemon
        │
Input Driver
        │
uinput
        │
Linux Desktop
```

---

# Components

## Flutter

Responsibilities

* Capture touch
* Detect gestures
* Capture keyboard
* Encode binary packets
* Send packets
* Receive acknowledgements

---

## Node Input Service

Responsibilities

* Decode packets
* Validate packet sequence
* Queue events
* Coalesce mouse movement
* Preserve keyboard ordering
* Send events to native daemon

Node never injects input.

---

## Rust Input Daemon

Responsibilities

* Create virtual mouse
* Create virtual keyboard
* Inject events using uinput
* Guarantee event ordering
* Flush events immediately

---

# Development Phases

---

# Phase 1

## Binary Protocol

Design

Packet Header

```text
Version
Opcode
Sequence
Timestamp
Payload Length
Payload
```

Deliverables

* Encoder
* Decoder
* Unit tests

---

# Phase 2

## Mouse Movement

Features

* Relative movement
* Sensitivity
* Acceleration
* Smoothing

Supported

```text
Move
```

Not Supported

```text
Absolute Position
```

Deliverable

Smooth cursor movement.

---

# Phase 3

## Mouse Buttons

Support

* Left
* Right
* Middle

Events

```text
Button Down

Button Up

Click

Double Click
```

Deliverable

Reliable clicks.

---

# Phase 4

## Scroll

Support

* Vertical
* Horizontal

Features

* Smooth scrolling
* Momentum

Deliverable

Native scrolling experience.

---

# Phase 5

## Drag & Drop

State Machine

```text
Idle

↓

Left Down

↓

Moving

↓

Left Up
```

Deliverable

Natural drag behaviour.

---

# Phase 6

## Keyboard

Support

* Key Down
* Key Up
* Text Input

Deliverable

Reliable typing.

---

# Phase 7

## Modifier Keys

Support

Ctrl

Alt

Shift

Meta

Caps Lock

Num Lock

Deliverable

Shortcuts work correctly.

---

# Phase 8

## Shortcuts

Support

Ctrl+C

Ctrl+V

Ctrl+Z

Ctrl+Shift+T

Alt+Tab

Alt+F4

Custom shortcuts

---

# Phase 9

## Gesture Engine

One Finger

Cursor

Two Finger

Scroll

Tap

Click

Double Tap

Double Click

Long Press

Drag

Two Finger Tap

Right Click

Three Finger

Reserved

---

# Phase 10

## Event Scheduler

Purpose

Prevent event flooding.

Mouse events

Lossy

Keyboard events

Reliable

---

# Phase 11

## Mouse Coalescing

Incoming

```text
Move

Move

Move

Move
```

Outgoing

```text
Single Move
```

Algorithm

Accumulate dx/dy until next scheduler tick.

---

# Phase 12

## Scheduler

Tick Rate

240 Hz

Each tick

* Flush mouse queue
* Flush click queue
* Flush scroll queue

Keyboard bypasses scheduler.

---

# Phase 13

## Queue Design

Mouse Queue

Lossy

Scroll Queue

Lossy

Keyboard Queue

Reliable

Shortcut Queue

Reliable

---

# Phase 14

## Native Daemon

Responsibilities

* Read IPC
* Decode packet
* Inject input
* Flush events

No networking.

No authentication.

No JSON.

---

# Phase 15

## IPC

Transport

Unix Domain Socket

Socket

```text
/run/devcontrol/input.sock
```

Messages

Binary

---

# Phase 16

## Performance

Target

Mouse

240 Hz

Keyboard

Immediate

Scheduler

240 Hz

Injection

<1 ms

Total

<10 ms

---

# Phase 17

## Error Recovery

Lost packet

Ignore

Broken socket

Reconnect

Daemon restart

Reconnect automatically

Duplicate packet

Discard

Out-of-order packet

Discard

---

# Phase 18

## Testing

Mouse movement

Stress test

240 Hz

Click spam

1000 clicks

Keyboard

100,000 keys

Drag

Continuous movement

Shortcut

All modifiers

---

# Future

* Multi-touch gestures
* Drawing tablet mode
* Gamepad emulation
* Macro recording
* Gesture customization
* Pressure sensitivity
* Stylus support

---

# Directory Structure

```text
input/

flutter/
    gesture/
    encoder/
    transport/

node/
    decoder/
    scheduler/
    queue/
    ipc/

rust/
    protocol/
    keyboard/
    mouse/
    scroll/
    uinput/
```

---

# Definition of Done

The subsystem is complete when:

* Cursor movement feels identical to a physical touchpad.
* Keyboard input is lossless.
* Drag-and-drop is stable.
* Ctrl/Alt/Shift combinations work correctly.
* Continuous movement at 240 Hz does not increase CPU usage significantly.
* The Node service can be restarted without affecting the native input daemon.
* The native daemon can be restarted independently of the networking layer.
* The input subsystem is reusable by any future transport (WebRTC, QUIC, Bluetooth, USB) without modification.
