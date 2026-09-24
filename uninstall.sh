#!/usr/bin/env bash
set -Eeuo pipefail

purge_config=false
case "${1:-}" in
	"") ;;
	--purge-config) purge_config=true ;;
	--help|-h)
		printf 'Usage: uninstall.sh [--purge-config]\n'
		printf 'By default, removes the Go command and installed files but keeps your device token config.\n'
		exit 0
		;;
	*) printf 'Unknown option: %s\nUsage: uninstall.sh [--purge-config]\n' "$1" >&2; exit 2 ;;
esac

data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
app_root="${data_home}/xiaomi-power"
command_path="${HOME}/.local/bin/xiaomi-power"
config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
config_dir="${config_home}/xiaomi-power"
config_path="${config_dir}/config.json"

if [[ -L "$command_path" ]]; then
	target="$(readlink -f -- "$command_path" 2>/dev/null || true)"
	case "$target" in
		"${app_root}"/*)
			rm -- "$command_path"
			printf 'Removed command link: %s\n' "$command_path"
			;;
		*) printf 'Kept command link not managed by this installer: %s\n' "$command_path" ;;
	esac
elif [[ -e "$command_path" ]]; then
	printf 'Kept non-symlink command file: %s\n' "$command_path"
fi

if [[ -d "$app_root" ]]; then
	rm -rf -- "$app_root"
	printf 'Removed installed app files: %s\n' "$app_root"
fi

if [[ "$purge_config" == true ]]; then
	if [[ -e "$config_path" ]]; then
		rm -f -- "$config_path"
		printf 'Removed device config and token: %s\n' "$config_path"
	fi
	rmdir -- "$config_dir" 2>/dev/null || true
else
	printf 'Kept device config and token: %s\n' "$config_path"
	printf 'To remove it too, rerun with --purge-config.\n'
fi
