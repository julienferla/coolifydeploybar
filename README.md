# CoolifyDeployBar

[![GitHub — repository](https://img.shields.io/badge/GitHub-repository-181717?style=flat&logo=github)](https://github.com/julienferla/coolifydeploybar)
[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-🍺_Buy_me_a_beer-EA4AAA?style=flat&logo=github-sponsors)](https://github.com/sponsors/julienferla)

> macOS menu bar companion for [Coolify](https://coolify.io): watch deployment queue and open your Coolify dashboard with a Bearer token.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License MIT](https://img.shields.io/badge/license-MIT-green)

## Features

- **Deployment queue** — polls Coolify HTTP API v1 for queued / in-progress deployments
- **Settings** — base URL (e.g. `https://coolify.example.com`) and API token (stored in UserDefaults)
- **Menu bar** — `MenuBarExtra` popover + system Settings scene for configuration

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ or Swift 5.9 toolchain (for local builds)
- A Coolify instance with a **personal access token** (Bearer) and API v1 enabled

## Getting started

```bash
git clone https://github.com/julienferla/coolifydeploybar.git
cd coolifydeploybar
swift build
swift run CoolifyDeployBar
```

Open the project in Xcode:

```bash
xed .
```

Then run with **⌘R**.

### Configuration

1. Open **Settings** (CoolifyDeployBar menu or system Settings).
2. Set **Coolify base URL** (no trailing slash), e.g. `https://coolify.example.com`.
3. Paste your **API token** (same value you would send as `Authorization: Bearer …`).

API reference: [Coolify API](https://coolify.io/docs/api-reference/authorization).

## Releases (DMG)

Maintainers:

1. Bump **`CFBundleShortVersionString`** / **`CFBundleVersion`** in [`Packaging/Info.plist`](Packaging/Info.plist) when you cut a release (the DMG script also sets short version from the Git tag).
2. Create a **GitHub Release** (publish). Tag may be `v1.0.0` or `1.0.0`.
3. Workflow [`.github/workflows/release-dmg.yml`](.github/workflows/release-dmg.yml) builds on `macos-14` and uploads **`CoolifyDeployBar-<version>.dmg`** to that release.

Local DMG (Xcode / Swift notarized separately if you ship outside GitHub):

```bash
make dmg
# → dist/CoolifyDeployBar-<version>.dmg
```

## Project layout

```
Sources/CoolifyDeployBar/
├── CoolifyDeployBarApp.swift   # @main, MenuBarExtra + Settings
├── API/
├── Models/
├── Services/
├── Settings/
└── Views/
Packaging/
└── Info.plist                   # App bundle metadata for DMG packaging
scripts/
└── make-dmg.sh                  # swift build + .app + hdiutil
```

## License

MIT — see [LICENSE](LICENSE).
