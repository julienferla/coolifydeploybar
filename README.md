# CoolifyDeployBar

[![GitHub — repository](https://img.shields.io/badge/GitHub-repository-181717?style=flat&logo=github)](https://github.com/julienferla/coolifydeploybar)
[![GitHub Releases](https://img.shields.io/github/v/release/julienferla/coolifydeploybar?logo=github&label=Releases&color=blue)](https://github.com/julienferla/coolifydeploybar/releases)
[![Latest DMG](https://img.shields.io/badge/Download-latest%20DMG-181717?style=flat&logo=apple)](https://github.com/julienferla/coolifydeploybar/releases/latest)
[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-🍺_Buy_me_a_beer-EA4AAA?style=flat&logo=github-sponsors)](https://github.com/sponsors/julienferla)

> macOS menu bar companion for [Coolify](https://coolify.io): watch deployment queue and open your Coolify dashboard with a Bearer token.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License MIT](https://img.shields.io/badge/license-MIT-green)

## Features

- **Deployment queue** — polls Coolify HTTP API v1 for queued / in-progress deployments
- **Settings** — base URL (e.g. `https://coolify.example.com`) and API token (stored in UserDefaults)
- **Menu bar** — `MenuBarExtra` popover + system Settings scene for configuration

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ or Swift 5.9 toolchain (for local builds)
- A Coolify instance with a **personal access token** (Bearer) and API v1 enabled

## Getting started

```bash
git clone https://github.com/julienferla/coolifydeploybar.git
cd coolifydeploybar
swift build
swift run CoolifyDeployBar
```

### Où est l’app après un build ?

| Comment tu buildes | Emplacement |
| --- | --- |
| **Xcode** (⌘B / ⌘R) | Dans le **DerivedData** de Xcode : `~/Library/Developer/Xcode/DerivedData/CoolifyDeployBar-*/Build/Products/Debug/CoolifyDeployBar.app` (ou **Release** si tu as changé le schéma). Dans Xcode : menu **Product → Show Build Folder in Finder** pour ouvrir le dossier du produit. |
| **`swift build -c release`** | Pas de `.app` : exécutable seulement, chemin affiché par `swift build -c release --show-bin-path` → en général **`.build/arm64-apple-macosx/release/CoolifyDeployBar`**. |
| **`make dmg`** | Le script assemble un `.app` temporaire sous **`build/dmg_stage/`** et le DMG final dans **`dist/CoolifyDeployBar-<version>.dmg`**. |

### Xcode (recommandé — même flux qu’une app macOS classique)

Ouvre le projet généré **CoolifyDeployBar.xcodeproj** (cible Application macOS, `Packaging/Info.plist`, signature automatique possible avec ton équipe) :

```bash
make open
# ou : xed CoolifyDeployBar.xcodeproj
```

Puis **⌘R**. Dans **Signing & Capabilities**, choisis ton **Team** pour un binaire signé (évite les blocages Gatekeeper par rapport au seul exécutable SPM).

Le fichier **`project.yml`** sert de source de vérité pour [XcodeGen](https://github.com/yonaskolb/XcodeGen). Pour régénérer le `.xcodeproj` après modification des dossiers ou des réglages :

```bash
brew install xcodegen   # une fois
xcodegen generate
```

### Swift Package (sans Xcode)

```bash
xed Package.swift
```

Puis run avec **⌘R** sur le package (exécutable `CoolifyDeployBar`).

### Configuration

1. Open **Settings** (CoolifyDeployBar menu or system Settings).
2. Set **Coolify base URL** (no trailing slash), e.g. `https://coolify.example.com`.
3. Paste your **API token** (same value you would send as `Authorization: Bearer …`).

API reference: [Coolify API](https://coolify.io/docs/api-reference/authorization).

## Releases (DMG)

**Télécharger l’app :** [toutes les releases](https://github.com/julienferla/coolifydeploybar/releases) · [dernière release (DMG)](https://github.com/julienferla/coolifydeploybar/releases/latest)

Maintainers:

1. Bump **`CFBundleShortVersionString`** / **`CFBundleVersion`** in [`Packaging/Info.plist`](Packaging/Info.plist) when you cut a release (the DMG script also sets short version from the Git tag).
2. Create a **GitHub Release** (publish). Tag may be `v1.0.0` or `1.0.0`.
3. Workflow [`.github/workflows/release-dmg.yml`](.github/workflows/release-dmg.yml) builds on `macos-14` and uploads **`CoolifyDeployBar-<version>.dmg`** to that release.

### macOS : « CoolifyDeployBar est endommagé » après téléchargement GitHub

Ce message apparaît en général quand **Gatekeeper** refuse une app **non signée avec un certificat Apple de distribution** (le DMG des releases est construit par `swift build` sans signature). Ce n’est en principe **pas** un fichier téléchargé corrompu.

**À faire côté utilisateur (sans compte développeur) :**

1. Montre le DMG, fais glisser **CoolifyDeployBar.app** vers **Applications** (ou un dossier de ton choix).
2. Ouvre **Terminal** et exécute (remplace le chemin si besoin) :

   ```bash
   xattr -dr com.apple.quarantine /Applications/CoolifyDeployBar.app
   ```

3. Rouvre l’app depuis le Finder (double-clic). Si macOS bloque encore : clic droit sur l’app → **Ouvrir** → confirmer.

**Correctif durable pour les releases :** signer avec **Developer ID Application** et **notariser** (Apple `notarytool` + `stapler`) dans le workflow CI ; le script `make-dmg.sh` peut signer si la variable d’environnement `CODESIGN_IDENTITY` est définie (voir commentaire en tête du script).

Local DMG (Xcode / Swift notarized separately if you ship outside GitHub):

```bash
make dmg
# → dist/CoolifyDeployBar-<version>.dmg
```

## Project layout

```
CoolifyDeployBar.xcodeproj/    # App macOS (XcodeGen → project.yml)
project.yml                    # Définition XcodeGen (cible, Info.plist, déploiement)
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
