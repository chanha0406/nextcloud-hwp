#!/usr/bin/env bash
# Switch Nextcloud between workspace dev checkout and App Store install.
#
# Layout:
#   WORKSPACE  ~/Workspace/hwpdocuments  — git + scripts (edit here)
#   LIVE       $NC_ROOT/custom_apps/hwpdocuments
#
#   dev:   LIVE -> WORKSPACE (symlink; requires Docker mount of WORKSPACE)
#   store: LIVE is a real App Store directory (symlink removed)
#
# Env: OCC, NEXTCLOUD_ROOT, WORKSPACE_LINK
set -euo pipefail

APP_ID="hwpdocuments"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
	sed -n '2,16p' "$0"
	exit "${1:-0}"
}

mode="${1:-status}"
ALLOW_UNSTABLE=0
shift || true
for arg in "$@"; do
	case "$arg" in
		--allow-unstable) ALLOW_UNSTABLE=1 ;;
		-h|--help) usage 0 ;;
		*) echo "Unknown option: $arg" >&2; usage 1 ;;
	esac
done

resolve_occ() {
	if [[ -n "${OCC:-}" ]]; then
		echo "$OCC"
		return
	fi
	if [[ -n "${NEXTCLOUD_ROOT:-}" && -x "${NEXTCLOUD_ROOT}/occ" ]]; then
		echo "php ${NEXTCLOUD_ROOT}/occ"
		return
	fi
	if command -v docker >/dev/null 2>&1 \
		&& docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nextcloud-app'; then
		echo "docker exec -u www-data nextcloud-app php occ"
		return
	fi
	echo ""
}

detect_nc_root() {
	if [[ -n "${NEXTCLOUD_ROOT:-}" ]]; then
		realpath "$NEXTCLOUD_ROOT"
		return
	fi
	if command -v docker >/dev/null 2>&1 \
		&& docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nextcloud-app'; then
		local src
		src="$(docker inspect nextcloud-app --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Source}}{{end}}{{end}}')"
		[[ -n "$src" ]] && realpath "$src" && return
	fi
	local real
	real="$(realpath "$ROOT")"
	if [[ "$(basename "$real")" == "$APP_ID" ]]; then
		realpath "$(dirname "$(dirname "$real")")"
		return
	fi
	echo ""
}

run_occ() {
	# shellcheck disable=SC2086
	$OCC_CMD "$@"
}

host_to_container() {
	echo "/var/www/html/${1#"$NC_ROOT"/}"
}

docker_rm_path() {
	docker exec -u root "$CONTAINER" rm -rf "$(host_to_container "$1")"
}

is_dev_checkout() {
	[[ -d "$1/.git" || -f "$1/.git" ]]
}

live_target() {
	if [[ -L "$LIVE" ]]; then
		realpath "$LIVE"
	elif [[ -d "$LIVE" ]]; then
		realpath "$LIVE"
	else
		echo ""
	fi
}

current_mode() {
	if [[ -L "$LIVE" ]]; then
		echo "dev"
	elif [[ -d "$LIVE" && -f "$LIVE/appinfo/info.xml" ]]; then
		if is_dev_checkout "$LIVE"; then
			echo "dev"
		else
			echo "store"
		fi
	else
		echo "unknown"
	fi
}

assert_not_workspace() {
	local path="$1"
	local ws_real live_real
	ws_real="$(realpath "$WORKSPACE")"
	live_real="$(realpath "$path" 2>/dev/null || echo "")"
	if [[ "$live_real" == "$ws_real" ]]; then
		echo "[switch] REFUSING to delete workspace: $ws_real" >&2
		exit 1
	fi
}

verify_workspace_in_docker() {
	[[ -n "$CONTAINER" ]] || return 0
	if docker exec -u www-data "$CONTAINER" test -d "$WORKSPACE"; then
		return 0
	fi
	echo "[switch] ERROR: $WORKSPACE is not visible inside $CONTAINER" >&2
	echo "  Add to docker-compose (app + cron):" >&2
	echo "    - $WORKSPACE:$WORKSPACE:Z" >&2
	echo "  Then: docker compose up -d app cron" >&2
	exit 1
}

remove_live() {
	local m
	m="$(current_mode)"
	run_occ app:disable "$APP_ID" || true
	if [[ "$m" == "dev" && -L "$LIVE" ]]; then
		echo "[switch] remove symlink $LIVE"
		rm -f "$LIVE"
	elif [[ "$m" == "store" && -d "$LIVE" && ! -L "$LIVE" ]]; then
		assert_not_workspace "$LIVE"
		echo "[switch] remove App Store copy at $LIVE"
		run_occ app:remove --keep-data "$APP_ID" || true
		if [[ -d "$LIVE" ]]; then
			assert_not_workspace "$LIVE"
			rm -rf "$LIVE"
			[[ -n "$CONTAINER" ]] && docker_rm_path "$LIVE" 2>/dev/null || true
		fi
	elif [[ -d "$LIVE" || -L "$LIVE" ]]; then
		assert_not_workspace "$LIVE"
		rm -rf "$LIVE"
	fi
}

invalidate_appstore_cache() {
	echo "[switch] drop local App Store catalog cache"
	run_occ config:app:delete settings appstore-fetcher-lastFailure >/dev/null 2>&1 || true
	if [[ -n "$CONTAINER" ]]; then
		docker exec -u www-data "$CONTAINER" sh -c 'rm -f /data/appdata_*/appstore/apps.json' || true
	fi
}

wait_for_store_signature() {
	local len
	for ((i = 1; i <= 12; i++)); do
		len="$(curl -fsSL 'https://apps.nextcloud.com/api/v1/apps.json' | python3 -c "
import json,sys
for a in json.load(sys.stdin):
    if a.get('id')=='$APP_ID':
        print(len(a['releases'][0]['signature']))
        break
")"
		if [[ "$len" -le 700 ]]; then
			echo "[switch] App Store signature length OK ($len)"
			return 0
		fi
		echo "[switch] WARN: signature still $len bytes; retry $i/12" >&2
		sleep 5
		invalidate_appstore_cache
	done
	return 1
}

install_from_store() {
	local install_opts=()
	[[ "$ALLOW_UNSTABLE" -eq 1 ]] && install_opts+=(--allow-unstable)
	invalidate_appstore_cache
	wait_for_store_signature
	echo "[switch] install $APP_ID from App Store"
	run_occ app:install "${install_opts[@]}" "$APP_ID"
}

link_live_to_workspace() {
	verify_workspace_in_docker
	assert_not_workspace "$LIVE"
	rm -f "$LIVE"
	ln -sfn "$WORKSPACE" "$LIVE"
	echo "[switch] $LIVE -> $WORKSPACE"
}

print_status() {
	local m ver="" target
	m="$(current_mode)"
	target="$(live_target)"
	if [[ -f "$LIVE/appinfo/info.xml" ]]; then
		ver="$(sed -n 's/.*<version>\([^<]*\)<\/version>.*/\1/p' "$LIVE/appinfo/info.xml" | head -1)"
	fi
	echo "mode:      $m"
	echo "workspace: $WORKSPACE"
	echo "live:      $LIVE${ver:+  (version $ver)}"
	[[ -n "$target" ]] && echo "live ->    $target"
	run_occ app:list 2>/dev/null | grep -i "$APP_ID" || echo "$APP_ID: (not in occ app:list)"
}

OCC_CMD="$(resolve_occ)"
NC_ROOT="$(detect_nc_root)"
[[ -n "$NC_ROOT" ]] || { echo "Could not detect NEXTCLOUD_ROOT" >&2; exit 1; }
[[ -n "$OCC_CMD" ]] || { echo "Could not find occ" >&2; exit 1; }

CONTAINER=""
if [[ "$OCC_CMD" == docker\ exec* ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nextcloud-app'; then
	CONTAINER="nextcloud-app"
fi

WORKSPACE="$(realpath "${WORKSPACE_LINK:-$HOME/Workspace/$APP_ID}")"
LIVE="$NC_ROOT/custom_apps/$APP_ID"

if ! is_dev_checkout "$WORKSPACE"; then
	echo "[switch] missing git checkout at $WORKSPACE" >&2
	echo "  git clone https://github.com/chanha0406/nextcloud-hwp.git $WORKSPACE" >&2
	exit 1
fi

case "$mode" in
	status) print_status ;;
	store)
		if [[ "$(current_mode)" == "store" ]]; then
			echo "[switch] already on App Store copy — updating"
			invalidate_appstore_cache
			install_opts=()
			[[ "$ALLOW_UNSTABLE" -eq 1 ]] && install_opts+=(--allow-unstable)
			run_occ app:update "${install_opts[@]}" "$APP_ID"
		else
			remove_live
			install_from_store
		fi
		print_status
		;;
	dev)
		if [[ "$(current_mode)" == "dev" ]] && [[ "$(live_target)" == "$(realpath "$WORKSPACE")" ]]; then
			echo "[switch] already linked to workspace"
		else
			remove_live
			link_live_to_workspace
		fi
		run_occ app:enable "$APP_ID"
		print_status
		;;
	*) echo "Unknown mode: $mode" >&2; usage 1 ;;
esac
