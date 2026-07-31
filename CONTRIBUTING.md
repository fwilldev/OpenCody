# Contributing to OpenCody

Thanks for your interest in contributing to OpenCody! This document will help you get set up.

## Prerequisites

- Xcode 16+ (Swift 5.9)
- iOS 18+ deployment target
- An Apple Developer account (free tier works for device testing)

## Getting Started

1. **Fork & clone** the repository
2. **Open** `OpenCody - An OpenCode Client.xcodeproj` in Xcode
3. **Set your Development Team** in Xcode:
   - Select the project in the navigator
   - For each target (main app, tests, UI tests), go to **Signing & Capabilities**
   - Select your personal team from the dropdown
4. **Build & run** on a simulator or device

> **Note:** The `DEVELOPMENT_TEAM` field in `project.pbxproj` is intentionally left empty. Xcode will prompt you to select your own team on first build.

## Project Structure

```
OpenCody - An OpenCode Client/
├── Models/API/          # API response models (Session, Message, Part, etc.)
├── Services/            # Networking, Keychain, EventService, ConnectionManager
│   ├── API/             # Per-resource API services
│   └── Network/         # APIClient, SSEClient, endpoint definitions
├── ViewModels/          # Observable view models
├── Views/               # SwiftUI views organized by feature
│   ├── Chat/            # Chat interface, message bubbles, parts rendering
│   ├── Dashboard/       # Project list, session cards
│   ├── Settings/        # Providers, MCP, licenses, privacy policy
│   ├── Server/          # Server connection management
│   ├── Navigation/      # App routing
│   └── iPad/            # iPad-specific layout
└── Design/              # Theme, glass morphism components
```

## Architecture

- **Pure SwiftUI** — no UIKit bridges
- **No third-party dependencies** — only native Apple frameworks (StoreKit, SwiftUI, Foundation)
- **SSE-based real-time updates** via `EventService` + `SSEClient`
- **Keychain** for credential storage (never UserDefaults for secrets)

## Code Style

- Follow existing patterns in the codebase
- Use the `Theme` system for colors, spacing, and fonts
- Use `GlassCard`, `GlassButton`, `GlassTextField` for UI components
- Keep views small and composable

## StoreKit / Tip Jar

The `Products.storekit` file is included for local StoreKit testing. The product IDs (`tip_jar`, `mid_tip_jar`, `big_tip_jar`) are configured in App Store Connect for the production app. For local development, the StoreKit configuration file works out of the box in the simulator.

## Submitting Changes

1. Create a feature branch from `main`
2. Make your changes with clear, focused commits
3. Ensure the project builds without warnings
4. Open a Pull Request with a description of what changed and why

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
