# Cogi — Product Requirements Document

**Version:** 1.0
**Scope:** V1
**Platforms:** macOS + Android
**Repository:** Single monorepo
**Backend:** None
**Cloud:** None
**Maximum devices:** 5 per group

---

## 1. Product

**Cogi** is a small, open-source clipboard synchronization utility for macOS and Android.

It allows up to **5 trusted devices** to exchange **plain-text clipboard content over the same local network**.

Cogi requires:

* no account
* no login
* no backend
* no database server
* no cloud
* no internet connection
* no third-party authentication

Devices are paired once using a **QR code**. After pairing, they automatically discover and reconnect to trusted peers on the local network.

---

## 2. V1 Goals

Cogi V1 must support:

* macOS ↔ macOS clipboard sync
* macOS ↔ Android clipboard sync
* Android ↔ Android clipboard sync where Android permits clipboard access
* manual text sending
* local clipboard history
* Copy and Delete actions for history items
* QR-based pairing
* automatic LAN discovery
* encrypted peer communication
* automatic reconnection
* up to 5 devices
* persistent device trust

---

## 3. Explicitly Out of Scope

Do **not** implement:

* Firebase
* Clerk
* Supabase
* any backend
* cloud storage
* user accounts
* email/password authentication
* Google/Apple login
* internet-wide synchronization
* Windows/PC
* Linux
* iOS
* file sync
* image sync
* HTML/rich-text sync
* browser extensions
* subscriptions/payments
* cloud clipboard history

V2 may investigate Firebase/cloud synchronization, but **V1 must remain completely local**.

---

# 4. Platforms & Technology

## macOS

Use:

* Swift
* SwiftUI
* AppKit where required
* Network.framework
* Bonjour/mDNS
* NSPasteboard
* Keychain
* native cryptographic APIs

Cogi should primarily be a **menu bar/status bar application**, not a normal Dock application.

## Android

Use:

* Kotlin
* Jetpack Compose
* ClipboardManager
* Android network discovery APIs
* Android Keystore
* native networking APIs
* simple local persistence

Do **not** use Flutter.

---

# 5. Android Clipboard Limitation

This is an important V1 requirement.

### Android 10+

Normal applications cannot freely read clipboard contents while running in the background.

Therefore:

> **Cogi must NOT promise continuous background clipboard monitoring on Android.**

Cogi must not use:

* Accessibility Service
* hidden APIs
* root
* undocumented workarounds
* other mechanisms intended to bypass Android clipboard privacy restrictions

### Android behavior

When Cogi has permitted clipboard access / is in the appropriate foreground state:

```text
Android app
    ↓
ClipboardManager
    ↓
Detect text
    ↓
Cogi sync
```

When Cogi is unable to access the clipboard because Android has restricted it:

```text
Other app copies text
        ↓
Cogi cannot read it
        ↓
No automatic Android → peer sync
```

This is an OS limitation, not a networking limitation.

### Important distinction

Android can still:

* receive clipboard events from other devices
* store received events in Cogi history
* allow the user to tap Copy
* manually send text
* communicate with trusted peers

A foreground service may be considered for **connection persistence**, but it must **not** be treated as a solution for Android clipboard access restrictions.

---

# 6. Monorepo

```text
cogi/
├── README.md
├── PRD.md
│
├── protocol/
│   ├── PROTOCOL.md
│   └── schemas/
│
├── macos/
│   └── Cogi/
│
├── android/
│   └── Cogi/
│
└── docs/
    ├── architecture.md
    ├── pairing.md
    └── networking.md
```

Keep the repository simple.

Do not create unnecessary enterprise architecture or excessive abstraction layers.

---

# 7. Architecture

Each installation is a peer.

```text
             Cogi Group
          max 5 devices

        ┌──────────────┐
        │   MacBook    │
        └──────┬───────┘
               │
       ┌───────┴───────┐
       │ Local Network │
       └───────┬───────┘
               │
        ┌──────┴───────┐
        │              │
     Android         Mac Mini
```

Every device can:

* send
* receive
* discover peers
* maintain trust
* store local history

There is **no designated sender or receiver**.

---

# 8. Application Components

Keep the architecture small:

```text
UI
 │
 ▼
Sync Manager
 ├── Clipboard Manager
 ├── Pairing Manager
 ├── Device Manager
 ├── Discovery Manager
 ├── Connection Manager
 ├── Security Manager
 └── Local Storage
```

These are conceptual responsibilities, not requirements to create a separate class/module for every item.

**Do not over-engineer.**

---

# 9. Device Identity

Each installation generates:

```text
deviceId
deviceName
publicKey
privateKey
```

Example device names:

```text
MacBook Pro
Mac Mini
Pixel
Android Phone
```

The user can rename their device.

The private key:

* is generated locally
* never leaves the device
* is stored using Keychain on macOS
* is stored using Android Keystore on Android

---

# 10. Group

A Cogi group contains up to **5 trusted devices**.

Group information includes:

```text
groupId
trusted devices
device public identities
```

A sixth device must not be accepted.

If the group is full:

```text
Maximum 5 devices reached.
Remove a device before adding another.
```

---

# 11. Pairing

Pairing establishes **persistent trust**.

It is separate from the network connection.

### Create Group

```text
Create New Group
      ↓
Generate group
      ↓
Show QR code
      ↓
Wait for device
```

### Join Group

```text
Join Existing Group
      ↓
Scan QR
      ↓
Secure pairing handshake
      ↓
Store trust information
      ↓
Connected
```

The QR code must never contain a private key.

The QR payload should contain only the information necessary to bootstrap pairing, such as:

```text
protocolVersion
groupId
deviceId
publicKey
pairing information/token
```

Exact encoding belongs in `protocol/PROTOCOL.md`.

QR scanning is normally required **only once**.

---

# 12. Discovery

After pairing, devices automatically discover each other on the local network using:

**Bonjour/mDNS or equivalent native LAN discovery.**

Flow:

```text
Start Cogi
   ↓
Start discovery
   ↓
Find Cogi peers
   ↓
Check trusted identity
   ↓
Secure connection
```

Being visible through discovery does **not** mean a device is trusted.

Unpaired devices must not receive clipboard data.

---

# 13. Connections

Network connections are temporary.

Pairing is persistent.

A device should automatically reconnect after:

* app restart
* computer restart
* phone restart
* Wi-Fi reconnect
* temporary network interruption
* IP address change

Use sensible retry/backoff behavior.

Do not aggressively poll the network.

---

# 14. Security

Clipboard content may contain:

* passwords
* API keys
* tokens
* source code
* private messages
* financial information

Therefore Cogi must:

1. Send clipboard data only to trusted peers.
2. Never send clipboard data to a third-party server in V1.
3. Never store clipboard data remotely.
4. Keep private keys on-device.
5. Authenticate trusted peers.
6. Encrypt peer communication.
7. Validate incoming messages.
8. Prevent duplicate/replayed events where appropriate.

Do not implement custom cryptography.

Use established platform cryptographic primitives/protocols.

---

# 15. Clipboard Scope

V1 supports **plain text only**.

Supported:

```text
text
```

Not supported:

```text
image
file
HTML
rich text
screenshots
binary clipboard objects
```

The protocol must include a `type` field so future clipboard types can be added.

---

# 16. macOS Clipboard

Use `NSPasteboard`.

Cogi should detect clipboard changes made by normal applications such as:

* Safari
* Chrome
* VS Code
* Terminal
* Xcode
* Slack
* Notes
* other applications

No application-specific integrations are required.

Cogi observes the system pasteboard and does not own it.

---

# 17. Clipboard Synchronization

When a supported clipboard change occurs:

```text
System Clipboard
      ↓
Clipboard Manager
      ↓
Create ClipboardEvent
      ↓
Sync Manager
      ↓
Trusted connected peers
```

Example:

```json
{
  "eventId": "uuid",
  "originDeviceId": "device-a",
  "timestamp": 1790000000,
  "type": "text",
  "payload": "Hello World"
}
```

The exact wire format is defined in `protocol/PROTOCOL.md`.

---

# 18. Bidirectional Sync

All supported peers are equal.

Examples:

```text
Mac A → Mac B
Mac A → Android
Android → Mac A
Android → Android
Mac B → Mac A
```

The architecture must never assume:

```text
Mac = sender
Android = receiver
```

---

# 19. Remote Clipboard Behavior

When a device receives an event:

1. Validate the peer.
2. Validate the event.
3. Check `eventId`.
4. Add the item to local history.
5. Optionally update the system clipboard according to the product setting.
6. Prevent rebroadcast loops.
7. Send an acknowledgement.

For the initial implementation, prioritize:

> **Receive → save to history → user chooses Copy.**

Automatic replacement of the system clipboard should not be the first synchronization feature implemented.

---

# 20. Clipboard Loop Prevention

Every event contains:

```text
eventId
originDeviceId
```

Example:

```text
Mac A
   ↓
event ABC123
   ↓
Mac B
```

If Mac B places the received text into its clipboard, Cogi must know that the clipboard change originated from event `ABC123`.

It must not send the same event back to Mac A.

Prevent:

```text
A → B → A → B → A ...
```

Maintain a suitable recent-event/deduplication mechanism locally.

---

# 21. Clipboard History

Every device maintains its **own local history**.

There is no central history.

History items should contain at minimum:

```text
text
timestamp
source/device information where useful
eventId where useful
```

Example:

```text
Recent

Hello World
10:32 PM

npm install express
10:29 PM

https://github.com/example
10:25 PM
```

---

# 22. History Actions

Every history item must have:

### Copy

Copies the item to the device's system clipboard.

### Delete

Removes the item from local history.

Example:

```text
Hello World

[Copy] [Delete]
```

Deleting history is local and does not need to send a deletion event to other devices.

---

# 23. Manual Send

Both platforms must support manually sending text without first copying it.

```text
┌──────────────────────────┐
│ Type something...        │
└──────────────────────────┘

                    [Send]
```

Flow:

```text
Text input
    ↓
Create ClipboardEvent
    ↓
Send to trusted connected peers
    ↓
Add to local history
```

Manual sending works independently of Android's clipboard restrictions.

---

# 24. Offline Behavior

V1 does not provide cloud/offline synchronization.

If a peer is offline:

```text
Mac ───── X ───── Android
```

Cogi must not upload the clipboard anywhere.

Local history remains available.

When the peer reconnects, normal synchronization resumes.

A sophisticated offline event queue is **not required for V1**.

---

# 25. Protocol

Create a platform-independent protocol in:

```text
protocol/PROTOCOL.md
```

Protocol must be versioned.

Example:

```text
protocolVersion: 1
```

Initial message types:

```text
HELLO
PAIR_REQUEST
PAIR_RESPONSE
PAIR_CONFIRM
DEVICE_INFO
PING
PONG
CLIPBOARD_EVENT
ACK
GOODBYE
```

The protocol must be transport-agnostic enough that a future transport can be introduced without changing the clipboard event model.

---

# 26. ACK

A successfully processed event should receive an acknowledgement.

```text
Device A
   │
   │ CLIPBOARD_EVENT ABC123
   ▼
Device B
   │
   │ ACK ABC123
   ▼
Device A
```

ACKs are useful for delivery confirmation and duplicate handling.

---

# 27. Local Storage

Persist locally:

```text
device identity
device name
group information
trusted devices
application settings
clipboard history
```

Private keys must use:

### macOS

Keychain

### Android

Android Keystore

Normal application data can use appropriate lightweight local persistence.

Do not introduce a server database.

---

# 28. macOS UI

Cogi should primarily appear as a menu bar utility.

Example:

```text
Cogi
● Connected

Devices
────────────────
MacBook Pro       ●
Android Phone     ●
Mac Mini          ○

Send
────────────────
[ Type something... ] [Send]

Recent
────────────────
Hello World       [Copy] [Delete]
npm install       [Copy] [Delete]
https://...       [Copy] [Delete]

Settings
```

Keep the UI compact.

---

# 29. Android UI

Primary screen:

```text
Cogi

● Connected

Devices
────────────────
MacBook Pro       ●
Mac Mini          ●

Recent
────────────────
Hello World       [Copy] [Delete]
npm install       [Copy] [Delete]

[ Type something... ]

[ Send ]
```

Settings should provide pairing/device management.

---

# 30. Device Management

Users should be able to:

* see paired devices
* see connected/offline state
* rename their own device
* add a device
* remove/unpair a device

Removing a device revokes its trust.

A removed device must no longer receive clipboard data.

---

# 31. First Launch

```text
Welcome to Cogi

[ Create New Group ]

[ Join Existing Group ]
```

### Create

```text
Generate group
↓
Show QR
↓
Wait for devices
```

### Join

```text
Scan QR
↓
Pair
↓
Connected
```

---

# 32. Existing Device Startup

When Cogi starts:

```text
Load device identity
        ↓
Load trusted group
        ↓
Load settings/history
        ↓
Start LAN discovery
        ↓
Find trusted peers
        ↓
Establish secure connections
        ↓
Start platform-appropriate clipboard monitoring
        ↓
Sync
```

No login is required.

No QR scan is required unless adding/re-pairing a device.

---

# 33. Performance

Target:

**Near-real-time LAN synchronization.**

Desired:

```text
Copy
 ↓
Detect
 ↓
Transmit
 ↓
Receive
 ↓
History update
```

Target synchronization latency:

**typically <500 ms**, with **<1 second** as the practical V1 target under normal LAN conditions.

Avoid unnecessary polling or artificial delays.

---

# 34. Reliability

V1 must handle:

* app restart
* device restart
* Wi-Fi disconnect/reconnect
* IP changes
* peer temporarily offline
* rapid clipboard changes
* duplicate events
* simultaneous events
* Unicode text
* long text
* empty/unsupported clipboard content
* multiple connected devices

---

# 35. V1 Development Order

Build the smallest working system first.

### Phase 1 — macOS clipboard

```text
Swift
→ NSPasteboard
→ detect text
```

### Phase 2 — Mac ↔ Mac

Establish basic LAN communication.

### Phase 3 — Protocol

Implement:

```text
HELLO
PING/PONG
CLIPBOARD_EVENT
ACK
```

### Phase 4 — Android

Make:

```text
Mac ↔ Android
```

work.

### Phase 5 — Pairing

Implement:

```text
QR
device identity
public-key trust
persistent pairing
```

### Phase 6 — Security

Add authenticated encrypted communication.

### Phase 7 — Group

Support up to 5 devices.

### Phase 8 — History

Add local history + Copy/Delete.

### Phase 9 — Manual Send

Add text input + Send.

### Phase 10 — UI

Build the macOS menu bar UI and Android UI.

### Phase 11 — Reliability

Test reconnection, duplicates, multiple devices and Android restrictions.

---

# 36. V1 Acceptance Criteria

Cogi V1 is complete when:

### Pairing

* [ ] Mac can create a group.
* [ ] Android can join using QR.
* [ ] Mac can join another Mac using QR.
* [ ] Maximum 5 devices.
* [ ] Pairing survives restart.

### Discovery

* [ ] Trusted devices discover automatically.
* [ ] Trusted devices reconnect automatically.
* [ ] Untrusted devices cannot receive clipboard data.

### Clipboard

* [ ] macOS clipboard monitoring works.
* [ ] Android clipboard monitoring works where Android permits it.
* [ ] Mac → Mac works.
* [ ] Mac → Android works.
* [ ] Android → Mac works where Android clipboard access permits capture.
* [ ] Multiple peers can receive the same event.
* [ ] Clipboard loops are prevented.

### History

* [ ] Received items appear locally.
* [ ] Sent items appear locally.
* [ ] Copy works.
* [ ] Delete works.

### Manual Send

* [ ] Mac can manually send text.
* [ ] Android can manually send text.
* [ ] Connected peers receive it.

### Security

* [ ] Private keys never leave devices.
* [ ] Peer communication is encrypted.
* [ ] Unpaired devices cannot access clipboard data.
* [ ] No clipboard data is sent to a cloud/server.

### Android

* [ ] No attempt is made to bypass Android clipboard restrictions.
* [ ] Background clipboard capture is not promised.
* [ ] Receiving/manual-send functionality remains usable despite clipboard restrictions.

---

# 37. Engineering Rules

The coding agent must:

1. Keep V1 simple.
2. Prefer native OS APIs.
3. Avoid unnecessary dependencies.
4. Avoid unnecessary abstractions.
5. Never introduce a backend.
6. Never introduce Firebase in V1.
7. Never introduce authentication services.
8. Keep the protocol platform-independent.
9. Keep pairing separate from connections.
10. Keep discovery separate from trust.
11. Keep clipboard logic separate from UI.
12. Never expose private keys.
13. Never send data to untrusted peers.
14. Prevent clipboard loops using event IDs.
15. Enforce the 5-device limit.
16. Do not bypass Android OS restrictions.
17. Build working functionality before polishing architecture.
18. Prefer a small understandable codebase over enterprise-style architecture.

---

# 38. V2 — Future Only

V2 may investigate **Firebase** as an optional cloud synchronization layer.

Potential capabilities:

* user accounts
* Firebase Authentication
* devices on different networks
* internet-wide synchronization
* cloud-assisted offline synchronization
* cloud device management

None of this belongs in V1.

Do not build Firebase abstractions just for the sake of future-proofing.

The only V1 requirement is that the **clipboard/event model remains clean enough to support another transport later**.

---

# 39. Final Definition

> **Cogi is a lightweight native macOS and Android utility that lets up to five trusted devices exchange plain-text clipboard content directly over the same local network using QR-based pairing, automatic LAN discovery, encrypted peer-to-peer communication, local clipboard history, and manual text sending — without accounts, servers, databases, cloud infrastructure, or internet dependency.**
