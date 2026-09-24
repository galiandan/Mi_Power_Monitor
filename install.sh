#!/usr/bin/env bash
set -Eeuo pipefail

repo="galiandan/Mi_Power_Monitor"
api_url="https://api.github.com/repos/${repo}/releases/latest"

for command in curl python3 sha256sum tar; do
	if ! command -v "$command" >/dev/null 2>&1; then
		printf 'Missing required command: %s\n' "$command" >&2
		printf 'On Arch Linux, install prerequisites with: sudo pacman -S --needed curl python tar coreutils\n' >&2
		exit 1
	fi
done

if [[ "$(uname -s)" != Linux ]]; then
	printf 'This installer currently supports Linux only.\n' >&2
	exit 1
fi

case "$(uname -m)" in
	x86_64|amd64) go_arch="amd64" ;;
	aarch64|arm64) go_arch="arm64" ;;
	*) printf 'Unsupported CPU architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

release_info="$(python3 - "$api_url" "$go_arch" <<'PY'
import json
import sys
import urllib.request

request = urllib.request.Request(sys.argv[1], headers={"User-Agent": "xiaomi-power-installer"})
with urllib.request.urlopen(request, timeout=20) as response:
    release = json.load(response)

version = release["tag_name"].removeprefix("v")
asset_name = f"xiaomi-power_{version}_linux_{sys.argv[2]}.tar.gz"
asset = next((item for item in release["assets"] if item["name"] == asset_name), None)
checksums = next((item for item in release["assets"] if item["name"] == "SHA256SUMS"), None)
if asset is None or checksums is None:
    raise SystemExit("The latest GitHub release does not contain the required Linux assets")
print(release["tag_name"])
print(asset_name)
print(asset["browser_download_url"])
print(checksums["browser_download_url"])
PY
)"
mapfile -t release_data <<< "$release_info"
release_tag="${release_data[0]}"
archive_name="${release_data[1]}"
archive_url="${release_data[2]}"
checksums_url="${release_data[3]}"
if [[ ! "$release_tag" =~ ^v?[0-9A-Za-z][0-9A-Za-z._+-]*$ ]]; then
	printf 'Invalid release tag returned by GitHub.\n' >&2
	exit 1
fi

data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
install_dir="${data_home}/xiaomi-power/${release_tag}"
bin_dir="${HOME}/.local/bin"
command_path="${bin_dir}/xiaomi-power"
config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
config_path="${config_home}/xiaomi-power/config.json"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

printf 'Downloading Xiaomi Power Monitor %s (%s)...\n' "$release_tag" "$go_arch"
curl -fsSL "$archive_url" -o "${temporary_dir}/${archive_name}"
curl -fsSL "$checksums_url" -o "${temporary_dir}/SHA256SUMS"
expected_checksum="$(awk -v filename="$archive_name" '$2 == filename { print $1; exit }' "${temporary_dir}/SHA256SUMS")"
if [[ ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
	printf 'No valid SHA-256 checksum found for %s.\n' "$archive_name" >&2
	exit 1
fi
printf '%s  %s\n' "$expected_checksum" "$archive_name" | (cd "$temporary_dir" && sha256sum --check -)

mkdir -p "$install_dir"
tar -xzf "${temporary_dir}/${archive_name}" -C "$install_dir"

prepare_python_setup() {
	if ! command -v git >/dev/null 2>&1; then
		printf 'QR token setup needs git. On Arch Linux, install it with: sudo pacman -S --needed git\n' >&2
		exit 1
	fi
	if [[ ! -x "${install_dir}/.venv/bin/python" ]]; then
		python3 -m venv "${install_dir}/.venv"
	fi
	"${install_dir}/.venv/bin/python" -m pip install --quiet -r "${install_dir}/requirements.txt"
	if [[ -t 0 ]]; then
		python3 "${install_dir}/xiaomi_power.py" --setup-cloud-qr
	elif [[ -r /dev/tty ]]; then
		python3 "${install_dir}/xiaomi_power.py" --setup-cloud-qr </dev/tty
	else
		printf 'QR setup needs an interactive terminal. Re-run install.sh from a terminal.\n' >&2
		exit 1
	fi
}

if [[ ! -s "$config_path" ]]; then
	printf 'Starting one-time QR login to save the plug IP and token.\n'
	prepare_python_setup
elif [[ -t 0 ]]; then
	read -r -p 'A Xiaomi Power config already exists. Run QR login again? [y/N] ' answer
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		prepare_python_setup
	fi
else
	printf 'Using existing config: %s\n' "$config_path"
fi

mkdir -p "$bin_dir"
if [[ -e "$command_path" && ! -L "$command_path" ]]; then
	printf 'Cannot replace existing non-symlink: %s\n' "$command_path" >&2
	exit 1
fi
ln -sfn "${install_dir}/xiaomi-power" "$command_path"

printf '\nInstalled %s\n' "$command_path"
if [[ ":${PATH}:" != *":${bin_dir}:"* ]]; then
	printf 'Add this directory to PATH if needed: %s\n' "$bin_dir"
fi
printf 'Read power: xiaomi-power\n'
printf 'Keep polling: xiaomi-power --watch\n'
