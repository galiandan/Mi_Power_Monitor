# Xiaomi Plug 3 Power Monitor

A small command-line reader for the live power usage of Xiaomi/Mijia smart plug 3 devices (`cuco.plug.v3`). It talks to the plug directly over the local network using [`python-miio`](https://github.com/rytilahti/python-miio); Home Assistant and Xiaomi Cloud are not used for meter readings.

## Requirements

- Arch Linux (or another Linux distribution) with Python 3.10 or newer
- `git` (needed only for QR-based credential setup)
- The computer and plug must be reachable on the same local network
- A valid 32-character device token

The program uses `python-miio`'s generic MIoT interface. `requirements.txt` pins the upstream commit that provides the `MiotDevice` API used here, plus dependencies for the optional QR login helper.

## Install

```bash
python -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
```

The script automatically re-runs itself inside `.venv` when invoked with the system Python, so its normal invocation remains:

```bash
python xiaomi_power.py
```

## Configure credentials

### QR login (recommended)

Run:

```bash
python xiaomi_power.py --setup-cloud-qr
```

Choose `q` at the login prompt. Open the local URL printed by the helper on this computer, scan the QR code with Mi Home on Android, then approve the login. Leave the server selection empty to search all available regions. The helper locates a `cuco.plug.v3` device and saves its connection details under `~/.config/xiaomi-power/config.json` (or `$XDG_CONFIG_HOME/xiaomi-power/config.json`).

QR setup downloads a pinned revision of the open-source [Xiaomi Cloud Tokens Extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) into a temporary directory. Its device-list and credential output is filtered from this program's terminal output, the temporary files are removed afterward, and the resulting config directory/file are set to permissions `700`/`600`. Xiaomi QR login is used only to obtain the local device token; subsequent meter reads are LAN requests.

### Manual config or local backup

Copy the example config into the private config directory, then edit it with the real plug IP and token:

```bash
install -d -m 700 ~/.config/xiaomi-power
install -m 600 config.example.json ~/.config/xiaomi-power/config.json
$EDITOR ~/.config/xiaomi-power/config.json
chmod 600 ~/.config/xiaomi-power/config.json
```

`192.0.2.10` and the token/device ID in the example are placeholders and must be replaced. Keep the real `config.json` private; it is deliberately excluded from version control. At minimum, configure `model`, `ip`, and `token`.

If QR login is unavailable, import a local Mi Home database export or Android `.ab` backup:

```bash
python xiaomi_power.py --import-token-source /path/to/miio2.db
# or
python xiaomi_power.py --import-token-source /path/to/mi-home-backup.ab
```

For an encrypted Android backup, the program prompts for its password without echoing it. See the [`python-miio` token extraction guide](https://python-miio.readthedocs.io/en/latest/legacy_token_extraction.html). The legacy password-based `--setup-cloud` option is also available, but Xiaomi may require verification that its login flow cannot complete.

## Usage

```bash
python xiaomi_power.py
python xiaomi_power.py --json
python xiaomi_power.py --info
python xiaomi_power.py --energy --json
```

Human-readable output:

```text
Device: cuco.plug.v3
Power: 83.4 W
```

JSON output contains `model`, `power`, `unit`, and `available`. `--energy` also requests accumulated energy when the device returns it. `--info` requests firmware and device ID over LAN; avoid sharing that output publicly because it can identify your device/network.

## Data source

The [`cuco.plug.v3` MIoT specification](https://home.miot-spec.com/spec/cuco.plug.v3) defines service 11 (`power-consumption`) and property 11.2 (`electric-power`, read-only, watts). This program reads that property with `MiotDevice.get_property_by(11, 2)`. It can also request property 11.1 (accumulated energy, 0.01 kWh increments) using `--energy`. Voltage and current are not exposed in this model's corresponding service.

All readings are requested directly from the configured plug over LAN. If a read fails, check the IP, token, LAN access, and whether UDP port 54321 is reachable between the computer and plug. The older `chuangmiplug` command set does not expose these generic MIoT properties.

## Validation

The implementation was exercised with a `cuco.plug.v3` device: 30 consecutive reads at one-second intervals completed without failures, and observed wattage changed when the connected computer load changed. Energy reporting is optional and depends on the device returning that property.

## License

Licensed under the GNU General Public License, version 3 only. See [LICENSE](LICENSE).
