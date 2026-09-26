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

for command in curl python3 sha256sum tar flock install mv readlink; do
	if ! command -v "$command" >/dev/null 2>&1; then
		say '缺少必要命令：%s' 'Missing required command: %s' "$command" >&2
		say 'Arch Linux 可运行以下命令安装依赖：sudo pacman -S --needed curl python tar coreutils util-linux' 'On Arch Linux, install prerequisites with: sudo pacman -S --needed curl python tar coreutils util-linux' >&2
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
app_root="${data_home}/xiaomi-power"
versions_root="${app_root}/versions"
current_link="${app_root}/current"
bin_dir="${HOME}/.local/bin"
command_path="${bin_dir}/xiaomi-power"
config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
config_path="${config_home}/xiaomi-power/config.json"
if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" && -w "$XDG_RUNTIME_DIR" && -O "$XDG_RUNTIME_DIR" ]]; then
	lock_dir="$XDG_RUNTIME_DIR"
else
	lock_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/mi-power-monitor"
	mkdir -p -m 0700 "$lock_dir"
	chmod 0700 "$lock_dir"
fi
lock_path="${lock_dir}/mi-power-monitor.install.lock"
temporary_dir="$(mktemp -d)"
candidate_dir=""
version_dir=""
previous_target=""
previous_command_link=""
current_switched=false
command_link_changed=false
created_version=false
preserve_version=false
trap 'rm -rf -- "$temporary_dir"' EXIT

say '正在下载小米功耗监控器 %s（%s）……' 'Downloading Xiaomi Power Monitor %s (%s)...' "$release_tag" "$go_arch"
curl -fsSL "$archive_url" -o "${temporary_dir}/${archive_name}"
curl -fsSL "$checksums_url" -o "${temporary_dir}/SHA256SUMS"
expected_checksum="$(awk -v filename="$archive_name" '$2 == filename { print $1; exit }' "${temporary_dir}/SHA256SUMS")"
if [[ ! "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
	say '未找到 %s 对应的有效 SHA-256 校验值。' 'No valid SHA-256 checksum found for %s.' "$archive_name" >&2
	exit 1
fi
printf '%s  %s\n' "$expected_checksum" "$archive_name" | (cd "$temporary_dir" && sha256sum --check -)

mkdir -p "$versions_root" "$bin_dir"
if [[ -L "$lock_path" ]]; then
	say '安装锁路径不能是符号链接：%s' 'The install lock path must not be a symbolic link: %s' "$lock_path" >&2
	exit 1
fi
old_umask="$(umask)"
umask 077
exec 9>>"$lock_path"
umask "$old_umask"
chmod 0600 "$lock_path"
if ! flock -n 9; then
	say '另一个安装或升级任务正在运行。' 'Another install or upgrade is already running.' >&2
	exit 1
fi

if [[ -e "$command_path" && ! -L "$command_path" ]]; then
	say '目标位置已有非符号链接文件，无法覆盖：%s' 'Cannot replace existing non-symlink: %s' "$command_path" >&2
	exit 1
fi
if [[ -L "$command_path" ]]; then
	previous_command_link="$(readlink -- "$command_path" 2>/dev/null || true)"
	existing_target="$(readlink -f -- "$command_path" 2>/dev/null || true)"
	case "$existing_target" in
		"${app_root}"/*|"${data_home}/mi-power-monitor/"*) ;;
		*) say '目标链接不属于小米功耗监控器，拒绝覆盖：%s' 'Refusing to replace an unmanaged command link: %s' "$command_path" >&2; exit 1 ;;
	esac
fi
if [[ -L "$current_link" ]]; then
	previous_target="$(readlink -f -- "$current_link" 2>/dev/null || true)"
	case "$previous_target" in
		"${versions_root}"/*) ;;
		*) say '当前版本链接指向受管版本目录以外，停止升级：%s' 'The current version link is outside the managed versions directory: %s' "$current_link" >&2; exit 1 ;;
	esac
	if [[ ! -f "${previous_target}/.mi-power-monitor-managed" ]]; then
		say '当前版本没有本安装器的管理标记，拒绝自动升级：%s' 'The active version is not marked as managed; refusing automatic upgrade: %s' "$previous_target" >&2
		exit 1
	fi
elif [[ -e "$current_link" ]]; then
	say '当前版本路径不是符号链接，拒绝覆盖：%s' 'The current version path is not a symlink: %s' "$current_link" >&2
	exit 1
fi

cleanup() {
	local status=$?
	if [[ -n "$candidate_dir" && -d "$candidate_dir" ]]; then
		rm -rf -- "$candidate_dir"
	fi
	if (( status != 0 )) && [[ "$command_link_changed" == true ]]; then
		local restore_command_link="${command_path}.rollback.$$"
		if [[ -n "$previous_command_link" ]]; then
			if ln -s "$previous_command_link" "$restore_command_link"; then
				mv -Tf "$restore_command_link" "$command_path" || rm -f -- "$restore_command_link"
			fi
		else
			rm -f -- "$command_path"
		fi
	fi
	if (( status != 0 )) && [[ -n "$version_dir" && -d "$version_dir" && "$created_version" == true && "$preserve_version" == false ]]; then
		if [[ "$current_switched" == true && -n "$previous_target" && -d "$previous_target" ]]; then
			local restore_link="${app_root}/.current-rollback.$$"
			if ln -s "${previous_target}" "$restore_link" && mv -Tf "$restore_link" "$current_link"; then
				say '安装失败，已恢复到上一版本：%s' 'Install failed; restored the previous version: %s' "$previous_target" >&2
			else
				rm -f -- "$restore_link"
				preserve_version=true
				say '自动恢复失败，请检查当前链接：%s' 'Automatic rollback failed; inspect the active link: %s' "$current_link" >&2
			fi
		elif [[ "$current_switched" == true ]]; then
			rm -f -- "$current_link"
		fi
		if [[ "$preserve_version" == false ]]; then
			rm -rf -- "$version_dir"
		fi
	fi
	rm -rf -- "$temporary_dir"
	exit "$status"
}
trap cleanup EXIT

candidate_dir="$(mktemp -d "${versions_root}/.staging.XXXXXX")"
if ! python3 - "${temporary_dir}/${archive_name}" <<'PY'
import sys
import tarfile

archive_path = sys.argv[1]
expanded = 0
members = 0
try:
    with tarfile.open(archive_path, mode="r|gz") as archive:
        for member in archive:
            members += 1
            expanded += max(member.size, 0)
            parts = member.name.split("/")
            if (
                members > 10_000
                or expanded > 512 * 1024**2
                or not member.name
                or member.name.startswith("/")
                or "\\" in member.name
                or ".." in parts
                or member.size < 0
                or not (member.isdir() or member.isreg())
            ):
                raise SystemExit(1)
except Exception:
    raise SystemExit(1) from None
PY
then
	say '发行包包含不安全或超限的归档项目，已停止安装。' 'The release archive contains an unsafe or oversized member.' >&2
	exit 1
fi
tar --no-same-owner --no-same-permissions -xzf "${temporary_dir}/${archive_name}" -C "$candidate_dir"
for required_file in xiaomi-power xiaomi_power.py requirements.txt; do
	if [[ ! -f "${candidate_dir}/${required_file}" ]]; then
		say '发行包缺少必要文件：%s' 'Release archive is missing a required file: %s' "$required_file" >&2
		exit 1
	fi
done
"${candidate_dir}/xiaomi-power" -h >/dev/null

version_name="${release_tag}-${expected_checksum:0:12}"
version_dir="${versions_root}/${version_name}"
if [[ -e "$version_dir" ]]; then
	if [[ ! -f "${version_dir}/.mi-power-monitor-managed" || "$(<"${version_dir}/.mi-power-monitor-managed")" != "$expected_checksum" ]]; then
		version_name="${version_name}-$$"
		version_dir="${versions_root}/${version_name}"
	fi
fi
if [[ -d "$version_dir" && -f "${version_dir}/.mi-power-monitor-managed" && "$(<"${version_dir}/.mi-power-monitor-managed")" == "$expected_checksum" ]]; then
	rm -rf -- "$candidate_dir"
	candidate_dir=""
else
	if [[ -e "$version_dir" ]]; then
		say '目标版本目录已存在且不属于本安装器：%s' 'The target version directory already exists and is unmanaged: %s' "$version_dir" >&2
		exit 1
	fi
	mv -- "$candidate_dir" "$version_dir"
	candidate_dir=""
	created_version=true
	printf '%s\n' "$expected_checksum" > "${version_dir}/.mi-power-monitor-managed"
fi

prepare_python_setup() {
	if ! command -v git >/dev/null 2>&1; then
		say '二维码配置需要 git。Arch Linux 可运行：sudo pacman -S --needed git' 'QR token setup needs git. On Arch Linux, install it with: sudo pacman -S --needed git' >&2
		return 1
	fi
    if ! command -v timeout >/dev/null 2>&1; then
        say '缺少 timeout（coreutils），无法限制依赖安装时间。' 'Missing timeout (coreutils), required to bound dependency setup.' >&2
        return 1
    fi
    if [[ ! -x "${version_dir}/.venv/bin/python" ]]; then
        say '正在创建扫码所需的 Python 环境（最多 2 分钟）……' 'Creating the QR Python environment (up to 2 minutes)...'
        if ! timeout --kill-after=5s 120s python3 -m venv "${version_dir}/.venv"; then
            say 'Python 环境创建失败或超时，请检查 python3-venv/ensurepip 是否可用。' 'Python environment creation failed or timed out; check python3-venv/ensurepip.' >&2
            return 1
        fi
    fi
    say '正在下载扫码依赖（最多 5 分钟）；下方会显示进度，尚未进入扫码登录。' 'Downloading QR dependencies (up to 5 minutes); progress follows. QR login has not started yet.'
    # QR extraction needs only these PyPI packages, not the Git-based python-miio
    # dependency used by the optional legacy Python LAN/backup tools.
    if ! timeout --kill-after=5s 300s "${version_dir}/.venv/bin/python" -m pip install \
        --disable-pip-version-check --no-input --no-cache-dir --progress-bar off \
        --timeout 15 --retries 2 \
        'requests>=2.32,<3' 'pycryptodome>=3.20,<4' 'charset-normalizer>=3,<4' \
        'colorama>=0.4.6,<1' 'Pillow>=10,<13'; then
        say '扫码依赖安装失败或超过 5 分钟。请检查 PyPI 网络/代理后重试；尚未进入小米登录。' 'QR dependency installation failed or exceeded 5 minutes. Check PyPI connectivity/proxy and retry; Xiaomi login has not started.' >&2
        return 1
    fi
    say '扫码依赖已就绪，正在启动登录程序……' 'QR dependencies are ready; starting the login helper...'

	if [[ -t 0 ]]; then
		"${version_dir}/.venv/bin/python" "${version_dir}/xiaomi_power.py" --setup-cloud-qr
	elif [[ -r /dev/tty ]]; then
		"${version_dir}/.venv/bin/python" "${version_dir}/xiaomi_power.py" --setup-cloud-qr </dev/tty
	else
		say '二维码配置需要交互式终端，请在终端中重新运行 install.sh。' 'QR setup needs an interactive terminal. Re-run install.sh from a terminal.' >&2
		return 1
	fi
}

config_valid=false
if config_error="$(python3 "${version_dir}/xiaomi_power.py" --validate-config 2>&1 >/dev/null)"; then
	config_valid=true
else
	say '现有配置缺失或格式无效，将启动二维码配置。旧配置会在新配置成功保存前保留。' 'The existing config is missing or invalid. QR setup will run; the old config stays until a new one is saved.'
	[[ -z "$config_error" ]] || printf '  %s\n' "$config_error" >&2
	prepare_python_setup
	python3 "${version_dir}/xiaomi_power.py" --validate-config >/dev/null
	config_valid=true
fi

if [[ "$config_valid" == true && -t 0 ]]; then
	if supports_chinese; then
		read -r -p '检测到有效配置，要重新进行二维码登录吗？[y/N] ' answer
	else
		read -r -p 'A valid config exists. Run QR login again? [y/N] ' answer
	fi
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		prepare_python_setup
		python3 "${version_dir}/xiaomi_power.py" --validate-config >/dev/null
	fi
else
	say '设备配置有效，继续使用现有配置。' 'The device config is valid; keeping the existing config.'
fi

atomic_link() {
	local target="$1" link_path="$2" temp_link="${2}.tmp.$$"
	rm -f -- "$temp_link"
	ln -s -- "$target" "$temp_link"
	mv -Tf -- "$temp_link" "$link_path"
}
atomic_link "${app_root}/current/xiaomi-power" "$command_path"
command_link_changed=true
atomic_link "$version_dir" "$current_link"
current_switched=true
preserve_version=true

keep_previous=""
if [[ -n "$previous_target" && -d "$previous_target" ]]; then
	keep_previous="$previous_target"
fi
for old_version in "${versions_root}"/*; do
	[[ -d "$old_version" && ! -L "$old_version" ]] || continue
	[[ -f "${old_version}/.mi-power-monitor-managed" ]] || continue
	[[ "$old_version" == "$version_dir" || "$old_version" == "$keep_previous" ]] && continue
	if ! rm -rf -- "$old_version"; then
		say '旧版本清理失败，已保留目录：%s' 'Could not remove the old managed version; keeping: %s' "$old_version" >&2
	fi
done

say '\n已安装：%s' '\nInstalled %s' "$command_path"
if [[ ":${PATH}:" != *":${bin_dir}:"* ]]; then
	say '如果命令无法运行，请将此目录加入 PATH：%s' 'Add this directory to PATH if needed: %s' "$bin_dir"
fi
say '读取一次功耗：xiaomi-power' 'Read power once: xiaomi-power'
say '持续读取功耗：xiaomi-power --watch' 'Keep polling: xiaomi-power --watch'
