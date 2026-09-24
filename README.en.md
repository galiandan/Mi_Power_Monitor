[简体中文](README.md) | English

# Xiaomi Plug 3 Power Monitor

A small LAN reader for live power usage from Xiaomi/Mijia smart plug 3 (`cuco.plug.v3`). The Go command is designed to stay running with low overhead for polling clients such as a future KDE Plasma widget. It does not need Home Assistant or Xiaomi Cloud for readings.

## Quick install (Arch Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/galiandan/Mi_Power_Monitor/main/install.sh | bash
```

The script downloads the matching Go build, verifies its SHA-256 checksum, guides QR login on first setup, and installs `~/.local/bin/xiaomi-power`. Existing device config is reused. Python is only needed during first-time token setup; the Go reader does not depend on Python at runtime.

You can inspect the [installer script](install.sh) first. If required system tools are missing, it prints the Arch Linux package command.

## Build from source

Requires Go 1.25 or newer. The app uses [`github.com/mberatsanli/miio`](https://github.com/mberatsanli/miio), a Go implementation of Xiaomi's local miIO transport with generic MIoT property reads. That library handles UDP framing, encryption, handshake, retries, and `(siid, piid)` addressing; this project calls its property API rather than reimplementing the wire protocol.

```bash
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o xiaomi-power ./cmd/xiaomi-power
```

This produces a stripped, statically linked binary with no Python runtime dependency.

You can also download Linux x86-64 or ARM64 builds from [Releases](https://github.com/galiandan/Mi_Power_Monitor/releases).

## Optional Python device details

The installer handles QR login and token setup on first run. To query firmware or device ID later, install the optional Python helper dependencies:

```bash
python -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python xiaomi_power.py --info
```

`--info` also prints the device IP, so check the output for private details before sharing it.

To create the config manually:

```bash
install -d -m 700 ~/.config/xiaomi-power
install -m 600 config.example.json ~/.config/xiaomi-power/config.json
$EDITOR ~/.config/xiaomi-power/config.json
chmod 600 ~/.config/xiaomi-power/config.json
```

Replace the documentation-only IP, token, and optional device ID placeholders. Never commit the real `config.json`; `.gitignore` excludes it. The Go reader also resets the config directory/file modes to `700`/`600` before using the token.

## Run

Build once, then read one value:

```bash
./xiaomi-power
```

Output:

```text
Device: cuco.plug.v3
Power: 83.4 W
```

Keep one process alive and poll once per second:

```bash
./xiaomi-power --watch
```

Machine-readable output is newline-delimited JSON. `--count` is useful for bounded checks; `--interval` changes the polling period:

```bash
./xiaomi-power --json
./xiaomi-power --watch --json --interval 1s --count 30
```

Each JSON line contains `model`, `power`, `unit`, and `available`. The watch process keeps the LAN client open and reuses it between reads. Press Ctrl+C to stop it.

## MIoT property

The [`cuco.plug.v3` MIoT specification](https://home.miot-spec.com/spec/cuco.plug.v3) defines service 11 (`power-consumption`), property 11.2 (`electric-power`, watts). The Go reader calls `GetProperties` for SIID 11 / PIID 2. Property 11.1 is accumulated energy in 0.01 kWh steps.

The token is a local credential granting device access. LAN reads use UDP port 54321. If they fail, check the IP, token, network reachability, and local access settings on the plug.

## Validation

The original Python reader was verified against hardware with 30 one-second reads and changing load. The Go reader has now completed 30 consecutive one-second LAN reads on the same plug with no failures. During that run it used about 11.7 MiB peak RSS on Arch Linux x86-64; actual usage depends on the Go runtime and system.

## License

Licensed under the GNU General Public License, version 3 only. See [LICENSE](LICENSE). The Go MIoT transport is a separate MIT-licensed dependency.
