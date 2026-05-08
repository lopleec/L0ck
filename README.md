# L0ck

![platform](https://img.shields.io/badge/platform-macOS-0A84FF?style=flat)
![language](https://img.shields.io/badge/language-Swift-F05138?style=flat)
![framework](https://img.shields.io/badge/framework-SwiftUI-FA7343?style=flat)
![license](https://img.shields.io/badge/license-GPLv3-4A90E2?style=flat)
![preview](https://img.shields.io/badge/preview-Quick%20Look-8E8E93?style=flat)
![localization](https://img.shields.io/badge/localization-English%20%7C%20zh--Hans-34C759?style=flat)
![security](https://img.shields.io/badge/security-device--bound%20by%20default-111111?style=flat)

L0ck is a security-focused native macOS file encryption app built with SwiftUI.

It turns files into `.l0ck` containers, binds standard encrypted files to the current Mac through Keychain-backed secrets, protects preview flows, and adds system-level friction around deleting or moving encrypted files without administrator authorization.

## Overview

L0ck is designed for local-first protection on macOS:

- Encrypt files into `.l0ck` containers instead of leaving plaintext files on disk
- Bind standard encrypted files to both a user password and the current Mac
- Keep device secrets in the macOS login keychain instead of the repository or app bundle
- Support in-app preview while aggressively cleaning temporary decrypted copies
- Make destructive file operations require elevated authorization when protection is enabled

This project currently focuses on the desktop app experience first: onboarding, encrypted file management, preview, export, backup, and safety controls around local storage.

## What L0ck Does

- Imports ordinary files and encrypts them into `.l0ck` containers
- Stores encrypted files either in the protected L0ck vault or next to the original file
- Lets you preview supported file types after entering the file password
- Exports decrypted copies only when explicitly requested
- Supports key backup and restore for moving to another Mac
- Supports an app-level launch password with optional auto-lock when the app loses focus
- Supports English, Simplified Chinese, and Follow System language behavior
- Supports deleting broken records and deleting `.l0ck` files from arbitrary locations inside the app
- Supports a portable `Universal .l0ck` format for cross-Mac sharing when device binding is not possible

## Main Features

### 1. Native macOS SwiftUI interface

- Standard sidebar and detail layout
- First-launch onboarding
- Settings window for language, app lock, import defaults, and preview cleanup
- Localized interface in English and Simplified Chinese

### 2. Device-bound encrypted files

Standard `.l0ck` files are the default and recommended format.

- File decryption depends on the file password
- It also depends on secrets stored in the current Mac's login keychain
- Moving the encrypted file alone is not enough to decrypt it on another Mac

### 3. Protected local storage

By default, L0ck stores encrypted files in:

```text
~/Documents/L0ck
```

This mode is intended to provide the strongest local protection in the current app:

- The encrypted file is written as read-only
- Immutable flags can be applied
- Delete and re-protect operations can require administrator authorization

### 4. Preview with cleanup controls

- Text, image, and PDF files can be previewed directly in-app
- Other file types can use embedded macOS Quick Look
- Temporary decrypted preview copies can auto-clear after a configurable delay
- All preview copies are removed when L0ck quits

### 5. App-level launch lock

- L0ck can require an app password every time it opens
- The app can also lock again when it becomes inactive
- App-lock credentials are stored in the macOS keychain as a verifier, not as plaintext

### 6. Key backup and restore

- Device-bound encryption keys can be exported into an encrypted backup file
- That backup can be restored on another Mac when you intentionally migrate
- This is how standard `.l0ck` access can move between devices

### 7. Portable export mode

`Universal .l0ck` exists for portability, not as the preferred default.

- It removes the current Mac from the trust chain
- It protects the file with a strong password only
- It is intentionally marked as not recommended in the UI

## Requirements

- macOS 14 or later
- Xcode 16 or later recommended for development

## Build and Run

### Quick start

```bash
./script/build_and_run.sh
```

### Verify launch

```bash
./script/build_and_run.sh --verify
```

### Build manually with `xcodebuild`

```bash
xcodebuild \
  -project "L0ck.xcodeproj" \
  -scheme "L0ck" \
  -configuration Debug \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/L0ck-Codex" \
  build
```

## How to Use

### First launch

When L0ck launches for the first time, it walks through onboarding:

1. Introduction to how the app works
2. Device key creation in the macOS login keychain
3. Optional app password setup
4. Key backup guidance

### Encrypt a file

1. Click `Import`
2. Choose the source file
3. Set the file password
4. Choose where the encrypted file should live:
   - `App Folder`
   - `Same Folder`
5. Optionally delete the original file after encryption

### Open or preview a file

1. Select a `.l0ck` record in the sidebar
2. Click `Preview`
3. Enter the file password
4. View the content in-app or through embedded Quick Look

### Export a decrypted copy

1. Open a file record
2. Click `Export`
3. Enter the file password
4. Choose where the decrypted copy should be saved

### Export a portable `Universal .l0ck`

1. Open a file record
2. Click `Universal .l0ck…`
3. Enter the current file password
4. Set a new strong export password
5. Save the portable encrypted file

### Delete protected encrypted files

- Files managed by L0ck can be deleted from the detail view or sidebar
- Arbitrary `.l0ck` files can also be deleted through `More -> Delete .l0ck File…`
- Protected delete operations can require administrator authorization

## Settings

L0ck currently includes settings for:

- Language
  - English
  - Simplified Chinese
  - Follow System
- App lock
  - Turn app password on or off
  - Change app password
  - Lock when the app becomes inactive
- Import defaults
  - Default storage mode
  - Delete original file after encryption
- Preview behavior
  - Auto-clear preview timeout in seconds
  - `0` means manual clear only
- Advanced
  - Show onboarding again

## Storage Modes

### App Folder

Recommended for strongest protection in the current design.

- Stores encrypted files in `~/Documents/L0ck`
- Best fit for root-gated delete and move protection
- Easier to manage as a dedicated vault

### Same Folder

Useful when you want encrypted files next to their source context.

- Stores the `.l0ck` file beside the source file
- Protects the encrypted file itself
- The surrounding folder remains user-managed

## Implementation Overview

This section explains the main design choices behind L0ck.

### Device-bound standard encryption

Standard `.l0ck` files are intentionally tied to:

- the file password
- a master secret stored in the current Mac's keychain
- a Curve25519 private key stored in the current Mac's keychain

That means the encrypted file alone is not enough for decryption. A copied file is still missing the local secrets unless the user restores a valid key backup onto another Mac.

### App-level protection model

L0ck tries to make unsafe actions explicit rather than invisible:

- preview requires the file password
- export requires the file password
- destructive operations can require administrator authorization
- temporary decrypted preview files are hidden, locked, and cleaned up

### Preview model

Preview is split into two paths:

- direct in-memory preview for text, image, and PDF
- temporary-file preview for types that rely on Quick Look

When Quick Look is needed, the app writes a temporary decrypted copy to the macOS temporary directory, locks it down with file permissions and flags, and removes it when the preview is cleared or the app exits.

## Cryptography

### Standard `.l0ck` encryption pipeline

L0ck's standard format uses a multi-layer design:

1. `AES-256-GCM`
   - encrypts the plaintext payload with a random DEK
   - the plaintext payload contains both the original filename and file bytes
2. `PBKDF2-HMAC-SHA512`
   - derives a password-based key from the user password and per-file salt
3. `HKDF-SHA256`
   - derives a key from the local master secret
   - combines the password-derived key and keychain-derived key into a combined KEK
4. `ChaCha20-Poly1305`
   - wraps the random DEK using the combined KEK
5. `ECIES over Curve25519`
   - protects the wrapped DEK using the app's Curve25519 key pair
   - implemented with Curve25519 key agreement, HKDF-SHA256, and AES-256-GCM

### Standard password and KDF parameters

- File encryption password minimum length: `8`
- Default PBKDF2 iteration count for new device-bound files: `350,000`
- Iteration count is stored per file so older files remain decryptable

### Portable `Universal .l0ck` encryption

Portable export intentionally trades device binding for portability:

- encrypted with `AES-256-GCM`
- key derived from password with `PBKDF2-HMAC-SHA512`
- stronger KDF cost than the standard device-bound format

Current parameters:

- Minimum password length: `12`
- Must include uppercase, lowercase, digit, and symbol
- PBKDF2 iteration count: `1,000,000`

## File Format

L0ck currently uses two serialized `.l0ck` payload versions:

- `0x02` for device-bound multi-factor payloads
- `0x03` for portable password-only payloads

Each file starts with the `L0CK` magic header and then stores the version-specific encrypted payload.

## Project Structure

```text
L0ck/
├── L0ck/
│   ├── Crypto/                 # encryption engine, ECIES, file format, KDF
│   ├── Models/                 # file records, file types, app session state
│   ├── Services/               # keychain, admin auth, file I/O
│   ├── Views/                  # onboarding, main UI, detail view, settings
│   ├── Assets.xcassets/        # app icon and color assets
│   └── zh-Hans.lproj/          # Simplified Chinese localization
├── script/
│   └── build_and_run.sh        # local build and run helper
├── L0ck.xcodeproj/
├── LICENSE
└── README.md
```

## Security Notes

- This project has not been through a formal third-party security audit
- `Universal .l0ck` is less strict than the default device-bound mode
- Quick Look preview can require a temporary decrypted file on disk
- Local protection is strongest when using `App Folder`
- Key backups should be treated as highly sensitive material

## Current Limitations

- The project is macOS-only
- Standard `.l0ck` files are intentionally tied to keychain state unless migrated with backup and restore
- Some operations depend on administrator authorization and system behavior on macOS
- Quick Look preview behavior depends on what the current macOS installation can preview

## Development Notes

- The build script keeps derived data outside iCloud-managed project folders to avoid local signing issues
- Workspace artifacts such as `.build`, `xcuserdata`, logs, and temporary editor files should not be committed
- The repository intentionally does not store generated local encryption keys or preview artifacts

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
