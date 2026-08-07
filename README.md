# aigo CLI (binary distribution)

Prebuilt **`aigo`** binaries for the [AI GO](https://ai-go.app) platform.

This repository is a **public install channel only**. It ships:

- `install.sh` — one-line installer
- GitHub Release assets — stripped platform binaries
- [`LICENSE`](./LICENSE) — **Binary Distribution License**

**Source code is not published here** and remains in a private repository. Downloading or installing the binary does **not** grant a source-code license.

## Install

macOS (Apple Silicon) / Linux (x86_64):

```bash
curl -fsSL https://raw.githubusercontent.com/AI-GO-APP/aigo-cli-releases/main/install.sh | bash
```

Pin a version:

```bash
curl -fsSL https://raw.githubusercontent.com/AI-GO-APP/aigo-cli-releases/main/install.sh | bash -s 0.3.0
```

Then:

```bash
aigo --version
aigo --help
```

If `~/.local/bin` is not on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Supported platforms

| Platform | Asset pattern |
|----------|----------------|
| Windows (x86_64) | `aigo-<version>-x86_64-pc-windows-msvc.zip` |
| Linux (x86_64) | `aigo-<version>-x86_64-unknown-linux-gnu.tar.gz` |
| Apple Silicon | `aigo-<version>-aarch64-apple-darwin.tar.gz` |

Windows: run `install.sh` under [Git Bash](https://gitforwindows.org/). WSL gets the Linux binary.

### Manual download

See [Releases](https://github.com/AI-GO-APP/aigo-cli-releases/releases): download the archive for your platform, extract `aigo` / `aigo.exe`, place it on your `PATH`.

## License

Use of the prebuilt binary is governed by the [Binary Distribution License](./LICENSE).

- You may install and run the binary for use with AI GO.
- You may **not** reverse-engineer or redistribute the binary (except internal deployment copies as allowed in the license).
- **No source code** is licensed or provided via this repository.

## Support

Product / API docs: your AI GO dashboard and platform documentation.  
Issues about the **installer or release assets** can be opened on this repo if issues are enabled; product bugs may be routed through your AI GO support channel.
