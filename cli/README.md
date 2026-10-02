# pouse-cli

> The official cross-platform command-line distribution tool for the **Pouse** desktop client.

`pouse-cli` provides seamless installation, updates, verification, and uninstallation of the Pouse desktop client from your terminal.

---

## Requirements

- **Node.js**: `>=22.0.0` (Native ES Modules and modern standard Web APIs)
- **Zero runtime dependencies**: Pure native Node.js implementation (`dependencies: {}`)
- **Supported OS (Desktop Client)**:
  - **Windows 10 / 11 (x64)**: Fully supported in V1.
  - **Linux / macOS**: Adapter interfaces are structured; desktop clients planned for future releases.
  - **Android**: Available via the official Pouse download page.
  - **iOS**: Future Apple distribution; not a CLI installation target.

---

## Installation

You can run `pouse` directly using `npx` or install it globally:

```bash
# Run directly without installation
npx pouse-cli install

# Or install globally via npm
npm install -g pouse-cli
```

---

## Commands

### `pouse install`
Downloads the official Windows installer from GitHub Releases, validates its companion SHA-256 checksum, and launches the setup.

```bash
# Standard interactive installation (installs latest release)
pouse install

# Install a specific release version
pouse install --release v1.0.0

# Silent / unattended installation (no GUI prompts, ideal for scripts)
pouse install --silent

# Force re-installation even if already installed
pouse install --force
```

### `pouse update`
Checks the installed version against GitHub Releases and updates if a newer version is available.

```bash
# Update to the latest release
pouse update

# Silent update
pouse update --silent

# Force re-installation of the latest release
pouse update --force
```

### `pouse uninstall`
Detects the installation location and Inno Setup uninstaller from the Windows registry, and cleanly removes Pouse.

```bash
# Interactive uninstallation
pouse uninstall

# Silent uninstallation
pouse uninstall --silent
```

### `pouse --version` (`-v`)
Displays the CLI package version, Node.js runtime version, and installed Pouse desktop client version.

```bash
pouse --version
```

### `pouse --help` (`-h`)
Displays complete command reference and usage options.

```bash
pouse --help
```

---

## Command Options

| Option | Shorthand | Description |
|---|---|---|
| `--silent` | `-s` | Runs in unattended mode with no interactive prompts or dialogs. |
| `--verbose` | | Enables verbose diagnostic output and network logs. |
| `--release <version>` | `-r` | Specifies a target GitHub release version (e.g., `v1.0.0` or `1.0.0`). |
| `--force` | `-f` | Bypasses installed version checks and terminates running processes if needed. |
| `--unsafe-no-checksum` | | **[UNSAFE]** Overrides mandatory SHA-256 verification when companion checksum files are absent. (Testing/development use only). |

---

## Security Model

1. **Source of Truth**: Binaries and release metadata are sourced exclusively from the official GitHub repository (`Anikett-2310/Pouse`).
2. **Mandatory Checksum Verification**: Every binary download must be accompanied by an authoritative `.exe.sha256` companion hash on the release. If missing or mismatched, installation aborts immediately and the downloaded file is purged.
3. **Sandboxed Downloads**: Files are downloaded into isolated, randomized temporary directories (`%TEMP%\pouse-cli-*`) and cleaned up immediately after execution.
4. **Clean Process Shutdown**: The CLI prompts users to close Pouse via the system tray before updates or uninstallation to ensure Bluetooth discoverability and state are cleanly restored.

---

## Development & Testing

```bash
cd cli

# Run automated test suite
npm test
```
