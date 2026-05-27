# Hermes Android App

> **Work in progress** — Mobile client for connecting to a remote [Hermes Agent](https://hermes-agent.nousresearch.com) dashboard.

## Overview

The Hermes Android App is a Flutter-based mobile client that connects to a remote Hermes Agent dashboard over HTTP/WebSocket. It supports managing multiple concurrent sessions, viewing session history, and interacting with the Hermes Agent from your Android device.

## Features

- **Remote Connection Management** — Save, edit, and switch between multiple remote Hermes dashboards
- **Session History** — Browse and view existing sessions via the REST API
- **Dark Mode** — Material 3 dark theme by default
- **Multi-Session Support** — Tab-based navigation between active conversations

## Architecture

```
┌─────────────┐       HTTPS/WS       ┌─────────────────────┐
│             │ ─────────────────────>│  Hermes Dashboard   │
│  Android App │   REST API + PTY    │  (port 9119)        │
│             │                      │                   │
└─────────────┘                      └─────────────────────┐
                                                           │
                                                           ▼
                                                  ┌─────────────────────┐
                                                  │  Hermes Agent Core  │
                                                  │  (LLM + Tools)      │
                                                  └─────────────────────┘
```

### Tech Stack

- **Flutter 3.44** / **Dart 3.12**
- **Material 3** dark theme
- **SharedPreferences** for local connection persistence
- **HTTP** for REST API communication
- **WebSocket** (PTY) for real-time chat interaction

## Prerequisites

- Flutter 3.44+
- Dart 3.12+
- Android SDK 36+

## Development

```bash
cd hermes-android
flutter pub get
flutter run -d android
```

### Building the APK

```bash
flutter build apk --debug
```

## Connection Configuration

To connect to a local Hermes dashboard:

1. Ensure your dashboard is running with `hermes dashboard --insecure`
2. Add a connection with your host and port (default: `9119`)
3. Tap the connection to browse sessions

## Project Structure

```
lib/
├── core/
│   ├── models/
│   │   └── connection.dart      # Connection data model
│   ├── services/
│   │   └── connection_manager.dart # Connection persistence + API client
│   └── screens/                   # Screen widgets (coming)
└── main.dart                      # App entry point
```

## License

MIT
