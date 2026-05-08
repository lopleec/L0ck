# L0ck

![platform](https://img.shields.io/badge/platform-macOS-0A84FF?style=flat-square)
![language](https://img.shields.io/badge/language-Swift-F05138?style=flat-square)
![framework](https://img.shields.io/badge/framework-SwiftUI-FA7343?style=flat-square)
![license](https://img.shields.io/badge/license-GPLv3-4A90E2?style=flat-square)
![preview](https://img.shields.io/badge/preview-Quick%20Look-8E8E93?style=flat-square)
![localization](https://img.shields.io/badge/localization-English%20%7C%20zh--Hans-34C759?style=flat-square)
![security](https://img.shields.io/badge/security-device--bound%20by%20default-111111?style=flat-square)

L0ck is a native macOS file-encryption app built with SwiftUI.

It encrypts files into `.l0ck` containers, keeps device-bound keys in the macOS login keychain, and adds system-level protection for encrypted files so they are harder to delete or move without administrator authorization.

## Highlights

- Native macOS SwiftUI interface with onboarding, settings, sidebar navigation, and localized UI
- Device-bound encryption for standard `.l0ck` files
- Optional app launch password with automatic re-lock when the app becomes inactive
- Quick Look based preview for supported file types, with auto-clear for temporary decrypted preview copies
- Key backup and restore for migrating to another Mac
- Protected vault storage in `~/Documents/L0ck` by default
- Manual deletion for any `.l0ck` file location from inside the app
- Optional portable `Universal .l0ck` export for cross-Mac sharing
- English and Simplified Chinese, with “Follow System” language behavior

## Security Model

L0ck currently uses two file modes:

### Standard `.l0ck` files

These are the recommended default.

- File content is encrypted with a random data-encryption key
- Access depends on the file password and keys stored on the current Mac
- Device keys are stored in the macOS login keychain
- Encrypted files can be protected with immutable flags so deletion and moving require elevated privileges

### `Universal .l0ck` export

This mode exists for portability and is intentionally marked as not recommended in the UI.

- Protected only by the export password
- Designed for moving encrypted files between Macs
- Uses a stricter password policy and a higher PBKDF2 cost than standard file encryption

## Preview Behavior

- Text, image, and PDF files can be previewed directly in-app
- Other supported file types can use embedded macOS Quick Look preview
- When system preview is needed, L0ck creates a hidden temporary decrypted copy
- Temporary preview copies can auto-clear after a configurable number of seconds
- All preview copies are cleaned up when L0ck quits

## Requirements

- macOS 14 or later
- Xcode 16+ recommended

## Getting Started

### Build and run

```bash
./script/build_and_run.sh
```

### Verify the app launches

```bash
./script/build_and_run.sh --verify
```

### Build with `xcodebuild`

```bash
xcodebuild \
  -project "L0ck.xcodeproj" \
  -scheme "L0ck" \
  -configuration Debug \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/L0ck-Codex" \
  build
```

## Project Structure

```text
L0ck/
├── L0ck/
│   ├── Crypto/       # encryption, KDF, file format, ECIES
│   ├── Models/       # file records and app session state
│   ├── Services/     # keychain, file I/O, admin auth
│   ├── Views/        # SwiftUI screens and components
│   └── zh-Hans.lproj # Simplified Chinese localization
├── script/
│   └── build_and_run.sh
└── L0ck.xcodeproj
```

## Current Features

- First-launch onboarding for key generation, app password setup, and backup guidance
- Import and encrypt files into the protected L0ck vault or next to the source file
- Export decrypted copies after password verification
- Reapply protection to existing encrypted files
- Delete invalid records or protected `.l0ck` files from inside the app
- Configure language, import defaults, preview auto-clear, and app lock behavior in Settings

## Important Notes

- This project has not been through a formal security audit
- `Universal .l0ck` exists for sharing and migration, not as the preferred default storage mode
- Some delete, export, and protection actions intentionally require administrator authorization
- Standard device-bound `.l0ck` files are tied to the local keychain state on the Mac that created them unless you use key backup/restore

## Localization

The app currently supports:

- English
- Simplified Chinese
- Follow System language selection

## Development Notes

- The provided build script keeps derived data outside iCloud-managed project folders to avoid local signing issues
- Local workspace artifacts such as `.build`, `xcuserdata`, logs, and temporary editor files should not be committed
