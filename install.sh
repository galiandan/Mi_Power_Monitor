#!/usr/bin/env bash
set -Eeuo pipefail

supports_chinese() {
	local charmap
	charmap="$(locale charmap 2>/dev/null || true)"
	[[ "$charmap" == UTF-8 || "$charmap" == UTF8 ]]
}

say() {
	local chinese="$1" english="$2"
	shift 2
	if supports_chinese; then
		printf "$chinese\n" "$@"
	else
		printf "$english\n" "$@"
	fi
}

repo="galiandan/Mi_Power_Monitor"
api_url="https://api.github.com/repos/${repo}/releases/latest"

for command in curl python3 sha256sum tar; do
	if ! command -v "$command" >/dev/null 2>&1; then
		say '缺少必要命令：%s' 'Missing required command: %s' "$command" >&2
		say 'Arch Linux 可运行以下命令安装依赖：sudo pacman -S --needed curl python tar coreutils' 'On Arch Linux, install prerequisites with: sudo pacman -S --needed curl python tar coreutils' >&2
		exit 1
	fi
done

if [[ "$(uname -s)" != Linux ]]; then
	say '此安装程序目前仅支持 Linux。' 'This installer currently supports Linux only.' >&2
	exit 1
fi

case "$(uname -m)" in
	x86_64|amd64) go_arch="amd64" ;;
	aarch64|arm64) go_arch="arm64" ;;
	*) say '暂不支持此 CPU 架构：%s' 'Unsupported CPU architecture: %s' "$(uname -m)" >&2; exit 1 ;;
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
	say 'GitHub 返回的版本标签无效。' 'Invalid release tag returned by GitHub.' >&2
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

say '正在下载小米功耗监控器 %s（%s）……' 'Downloading Xiaomi Power Monitor %s (%s)...' "$release_tag" "$go_arch"
curl -fsSL "$archive_url" -o "${temporary_dir}/${archive_name}"
curl -fsSL "$checksums_url" -o "${temporary_dir}/SHA256SUMS"
expected_checksum="$(awk -v filename="$archive_name" '$2 == filename { print $1; exit }' "${temporary_dir}/SHA256SUMS")"
if [[ ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
	say '未找到 %s 对应的有效 SHA-256 校验值。' 'No valid SHA-256 checksum found for %s.' "$archive_name" >&2
	exit 1
fi
printf '%s  %s\n' "$expected_checksum" "$archive_name" | (cd "$temporary_dir" && sha256sum --check -)

mkdir -p "$install_dir"
tar -xzf "${temporary_dir}/${archive_name}" -C "$install_dir"

prepare_python_setup() {
	if ! command -v git >/dev/null 2>&1; then
		say '二维码配置需要 git。Arch Linux 可运行：sudo pacman -S --needed git' 'QR token setup needs git. On Arch Linux, install it with: sudo pacman -S --needed git' >&2
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
		say '二维码配置需要交互式终端，请在终端中重新运行 install.sh。' 'QR setup needs an interactive terminal. Re-run install.sh from a terminal.' >&2
		exit 1
	fi
}

if [[ ! -s "$config_path" ]]; then
	say '首次配置：推荐使用米家二维码扫码登录，将插座 IP 和 token 安全保存在本机。' 'First-time setup: QR sign-in is recommended to save the plug IP and token securely on this computer.'
	prepare_python_setup
elif [[ -t 0 ]]; then
	if supports_chinese; then
		read -r -p '检测到已有配置，要重新进行二维码登录吗？[y/N] ' answer
	else
		read -r -p 'A Xiaomi Power config already exists. Run QR login again? [y/N] ' answer
	fi
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		prepare_python_setup
	fi
else
	say '沿用已有配置：%s' 'Using existing config: %s' "$config_path"
fi

mkdir -p "$bin_dir"
if [[ -e "$command_path" && ! -L "$command_path" ]]; then
	say '目标位置已有非符号链接文件，无法覆盖：%s' 'Cannot replace existing non-symlink: %s' "$command_path" >&2
	exit 1
fi
ln -sfn "${install_dir}/xiaomi-power" "$command_path"

say '\n已安装：%s' '\nInstalled %s' "$command_path"
if [[ ":${PATH}:" != *":${bin_dir}:"* ]]; then
	say '如果命令无法运行，请将此目录加入 PATH：%s' 'Add this directory to PATH if needed: %s' "$bin_dir"
fi
say '读取一次功耗：xiaomi-power' 'Read power once: xiaomi-power'
say '持续读取功耗：xiaomi-power --watch' 'Keep polling: xiaomi-power --watch'
