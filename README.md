# L0ck

![platform](https://img.shields.io/badge/platform-macOS-0A84FF?style=flat)
![language](https://img.shields.io/badge/language-Swift-F05138?style=flat)
![framework](https://img.shields.io/badge/framework-SwiftUI-FA7343?style=flat)
![license](https://img.shields.io/badge/license-GPLv3-4A90E2?style=flat)

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

On first launch, L0ck guides you through:

1. device key creation
2. optional app password setup
3. key backup guidance

### Encrypt and manage files

1. Click `Import`
2. Choose a source file
3. Set the file password
4. Choose `App Folder` or `Same Folder`
5. Open the record from the sidebar to preview, export, re-protect, or delete it later

### Preview and export

- `Preview` opens the file after password verification
- `Export` writes a decrypted copy to a location you choose
- `Universal .l0ck…` creates a portable password-only encrypted file for cross-Mac sharing
- For highly sensitive files, avoid unnecessary preview or plaintext export

### Cleanup and deletion

- Invalid records can be removed from the sidebar
- Protected `.l0ck` files can be deleted from the app
- Arbitrary `.l0ck` files can also be deleted through `More -> Delete .l0ck File…`

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

## Security Assessment

### What an attacker needs

For standard device-bound `.l0ck` files, an offline attacker normally needs all of the following:

- the `.l0ck` file itself
- the correct file password, or enough guesses to find it
- the device-bound master secret from the original Mac's keychain
- the device-bound Curve25519 private key from the original Mac's keychain

That means a copied `.l0ck` file by itself is not enough.

For `Universal .l0ck`, the attacker only needs:

- the encrypted file
- the correct export password, or enough guesses to find it

That is why `Universal .l0ck` is more portable, but also a weaker model than the default device-bound format.

### Rough password-guessing cost

These numbers are only rough order-of-magnitude estimates, not guarantees.

- Public hashcat benchmark data for PBKDF2-SHA512 on an RTX 4090 shows about `2,825,700` guesses per second at `1,023` iterations
- If you scale that roughly to L0ck's `350,000` PBKDF2 iterations, you get about `8,000 to 8,500` guesses per second
- If you scale it to `1,000,000` iterations, you get about `2,800 to 2,900` guesses per second

What that means in practice:

- An `8`-character random lowercase password (`26^8`) is not enough. Full search is on the order of months at these speeds.
- An `8`-character random base62 password (`A-Z`, `a-z`, `0-9`) is much stronger. Full search is on the order of centuries.
- A `10`-character random base62 password is on the order of millions of years for full search on a single top-end consumer GPU.

Important caveat:

- human-chosen passwords are usually far weaker than random passwords
- dictionary attacks, password reuse, and pattern-based guessing can collapse those times dramatically
- for standard device-bound `.l0ck`, these password-guessing numbers matter only after the attacker also gets the local keychain secrets or equivalent access to the original Mac

### What is most likely to fail first

The most realistic risks are usually not "breaking AES" or "breaking Curve25519".

They are more likely to be:

- weak file passwords
- weak `Universal .l0ck` export passwords
- compromise of the same Mac while the user session is unlocked
- malware running as the same user
- plaintext exposure through manual export
- sensitive content being exposed during preview through temporary decrypted copies
- unsafe storage of key backup files

### Preview risk

Preview is convenient, but it is not the safest path for extremely sensitive material.

- Text, image, and PDF preview can stay in-app
- Some file types require Quick Look and therefore a temporary decrypted file on disk
- L0ck tries to hide, lock, and delete that temporary copy quickly
- However, the app cannot guarantee what other software, Quick Look plugins, system services, or external viewers may cache once plaintext has existed on the machine

For highly sensitive files, the safest practice is:

- avoid preview unless necessary
- avoid `Universal .l0ck` unless portability is required
- avoid exporting plaintext copies unless absolutely necessary
- prefer `App Folder`

### App lock and protection boundaries

The app password is useful, but it is not the same thing as file encryption.

- It protects the app entry flow
- It does not replace the file password
- It does not make a compromised unlocked macOS session safe

Likewise, delete protection and admin-gated operations are defense-in-depth features, not substitutes for strong passwords and secure device hygiene.

### Honest warning

This app is not perfect.

- It has not been through a formal third-party security audit
- We try to improve each version, but we cannot promise 100% security
- Bugs, design mistakes, macOS behavior changes, third-party preview behavior, or unsafe user practices can still create exposure

L0ck should be described as security-focused software, not as formally verified or guaranteed unbreakable software.

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
