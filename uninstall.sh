#!/usr/bin/env bash
set -uo pipefail

purge_config=false
case "${1:-}" in
	"") ;;
	--purge-config) purge_config=true ;;
	--help|-h)
		printf 'Usage: uninstall.sh [--purge-config]\n'
		printf 'By default, removes managed binaries but keeps your device token config.\n'
		exit 0
		;;
	*) printf 'Unknown option: %s\nUsage: uninstall.sh [--purge-config]\n' "$1" >&2; exit 2 ;;
esac

data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
app_root="${data_home}/xiaomi-power"
versions_root="${app_root}/versions"
current_link="${app_root}/current"
command_path="${HOME}/.local/bin/xiaomi-power"
config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
config_dir="${config_home}/xiaomi-power"
config_path="${config_dir}/config.json"
if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" && -w "$XDG_RUNTIME_DIR" && -O "$XDG_RUNTIME_DIR" ]]; then
	lock_dir="$XDG_RUNTIME_DIR"
else
	lock_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/mi-power-monitor"
	mkdir -p -m 0700 "$lock_dir"
	chmod 0700 "$lock_dir"
fi
lock_path="${lock_dir}/mi-power-monitor.install.lock"
failed=0

if command -v flock >/dev/null 2>&1; then
	if [[ -L "$lock_path" ]]; then
		printf 'Install lock path must not be a symbolic link: %s\n' "$lock_path" >&2
		exit 1
	fi
	old_umask="$(umask)"
	umask 077
	exec 9>>"$lock_path"
	umask "$old_umask"
	chmod 0600 "$lock_path"
	if ! flock -n 9; then
		printf 'An install or upgrade is running; retry uninstall after it finishes.\n' >&2
		exit 1
	fi
fi

if [[ -L "$command_path" ]]; then
	raw_target="$(readlink -- "$command_path" 2>/dev/null || true)"
	target="$(readlink -f -- "$command_path" 2>/dev/null || true)"
	if [[ "$raw_target" == "${app_root}/current/"* || "$target" == "${app_root}/"* ]]; then
		if rm -- "$command_path"; then
			printf 'Removed managed command link: %s\n' "$command_path"
		else
			printf 'Could not remove command link: %s\n' "$command_path" >&2
			failed=1
		fi
	else
		printf 'Kept command link not managed by this installer: %s\n' "$command_path"
	fi
elif [[ -e "$command_path" ]]; then
	printf 'Kept non-symlink command file: %s\n' "$command_path"
fi

if [[ -L "$current_link" ]]; then
	raw_current="$(readlink -- "$current_link" 2>/dev/null || true)"
	if [[ "$raw_current" == "${versions_root}/"* ]]; then
		rm -f -- "$current_link" || failed=1
	fi
elif [[ -e "$current_link" ]]; then
	printf 'Kept unrecognized current-version path: %s\n' "$current_link"
fi

if [[ -d "$versions_root" ]]; then
	for version_dir in "${versions_root}"/*; do
		[[ -d "$version_dir" && ! -L "$version_dir" ]] || continue
		[[ -f "${version_dir}/.mi-power-monitor-managed" ]] || continue
		if rm -rf -- "$version_dir"; then
			printf 'Removed managed version: %s\n' "$version_dir"
		else
			printf 'Could not remove managed version: %s\n' "$version_dir" >&2
			failed=1
		fi
	done
	rmdir -- "$versions_root" 2>/dev/null || true
fi

# Clean the layout created by older releases by filename, then leave any
# unrecognized user files and directories in place.
shopt -s nullglob
for legacy_dir in "${app_root}"/*; do
	[[ -d "$legacy_dir" && ! -L "$legacy_dir" && "$legacy_dir" != "$versions_root" ]] || continue
	if [[ -f "${legacy_dir}/xiaomi-power" && -f "${legacy_dir}/xiaomi_power.py" && -f "${legacy_dir}/requirements.txt" ]]; then
		rm -f -- "${legacy_dir}/xiaomi-power" "${legacy_dir}/xiaomi_power.py" \
			"${legacy_dir}/requirements.txt" "${legacy_dir}/config.example.json" \
			"${legacy_dir}/README.md" "${legacy_dir}/LICENSE" 2>/dev/null || failed=1
		rm -rf -- "${legacy_dir}/.venv" 2>/dev/null || failed=1
		rmdir -- "$legacy_dir" 2>/dev/null || true
	fi
done
if [[ "$purge_config" == true ]]; then
	if [[ -e "$config_path" || -L "$config_path" ]]; then
		if rm -f -- "$config_path"; then
			printf 'Removed device config and token: %s\n' "$config_path"
		else
			printf 'Could not remove device config: %s\n' "$config_path" >&2
			failed=1
		fi
	fi
	rmdir -- "$config_dir" 2>/dev/null || true
else
	printf 'Kept device config and token: %s\n' "$config_path"
	printf 'To remove it too, rerun with --purge-config.\n'
fi

rmdir -- "$app_root" 2>/dev/null || true

if (( failed != 0 )); then
	printf 'Uninstall left one or more managed items behind; retry or inspect the paths above.\n' >&2
	exit 1
fi
