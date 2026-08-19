#!/usr/bin/env bash
# Switch Nextcloud between workspace dev deploy and App Store install.
#
# Layout:
#   WORKSPACE  this git checkout (edit + build here)
#   LIVE       $NC_ROOT/custom_apps/hwpdocuments  (always a real directory)
#
#   dev:   rsync runtime files WORKSPACE → LIVE, then occ app:enable
#   store: occ app:install / app:update (App Store managed copy at LIVE)
#   sync:  redeploy WORKSPACE → LIVE (dev workflow after build)
#
# Env: OCC, NEXTCLOUD_ROOT, WORKSPACE (default: ~/Workspace/hwpdocuments)
set -euo pipefail

APP_ID="hwpdocuments"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Same allow-list as scripts/build-release.sh (runtime only).
RUNTIME_PATHS=(appinfo css img js lib studio LICENSE README.md)

usage() {
	sed -n '2,17p' "$0"
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
	if command -v docker >/dev/null 2>&1 \
		&& docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nextcloud-app'; then
		echo "docker exec -u www-data nextcloud-app php occ"
		return
	fi
	if [[ -n "${NC_ROOT:-}" && -x "${NC_ROOT}/occ" ]]; then
		echo "php ${NC_ROOT}/occ"
		return
	fi
	if [[ -n "${NEXTCLOUD_ROOT:-}" && -x "${NEXTCLOUD_ROOT}/occ" ]]; then
		echo "php ${NEXTCLOUD_ROOT}/occ"
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
	# Host path when the app lives under custom_apps (or a symlink into it).
	local real parent
	real="$(realpath "$ROOT")"
	if [[ "$(basename "$real")" == "$APP_ID" ]]; then
		parent="$(dirname "$real")"
		if [[ "$(basename "$parent")" == "custom_apps" && -x "$(dirname "$parent")/occ" ]]; then
			realpath "$(dirname "$parent")"
			return
		fi
	fi
	# Common local installs (workspace checkout is outside Nextcloud tree).
	local candidate
	for candidate in /ssd1/nextcloud /var/www/html "$HOME/nextcloud"; do
		if [[ -x "$candidate/occ" && -d "$candidate/custom_apps" ]]; then
			realpath "$candidate"
			return
		fi
	done
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

ensure_workspace_layout() {
	local canonical="$HOME/Workspace/$APP_ID"
	local legacy target ws_real leg_real

	for legacy in "$NC_ROOT/.${APP_ID}-dev" "$NC_ROOT/.hwp-dev"; do
		[[ -e "$legacy" ]] || continue
		if [[ -L "$canonical" ]]; then
			target="$(readlink -f "$canonical")"
			if [[ "$target" == "$(realpath "$legacy")" ]]; then
				echo "[switch] migrate workspace: $legacy → $canonical"
				rm "$canonical"
				mv "$legacy" "$canonical"
			fi
		elif [[ ! -e "$canonical" && -d "$legacy/.git" ]]; then
			echo "[switch] migrate legacy dev dir: $legacy → $canonical"
			mkdir -p "$(dirname "$canonical")"
			mv "$legacy" "$canonical"
		fi
	done

	if [[ -d "$canonical/.git" ]]; then
		ws_real="$(realpath "$canonical")"
		for legacy in "$NC_ROOT/.${APP_ID}-dev" "$NC_ROOT/.hwp-dev"; do
			[[ -e "$legacy" ]] || continue
			leg_real="$(realpath "$legacy")"
			if [[ "$ws_real" != "$leg_real" ]]; then
				echo "[switch] remove legacy dev dir: $legacy"
				rm -rf "$legacy"
			fi
		done
	fi

	if [[ -L "$LIVE" ]]; then
		target="$(readlink -f "$LIVE")"
		echo "[switch] remove custom_apps symlink: $LIVE -> $target"
		rm -f "$LIVE"
	fi
}

current_mode() {
	if [[ ! -d "$LIVE/appinfo" || ! -f "$LIVE/appinfo/info.xml" ]]; then
		echo "unknown"
		return
	fi
	if [[ -f "$LIVE/.install-source" ]] && grep -qx 'workspace' "$LIVE/.install-source"; then
		echo "dev"
		return
	fi
	if [[ -f "$LIVE/appinfo/signature.json" ]]; then
		echo "store"
		return
	fi
	# Legacy symlink or manual copy without marker — treat as dev if not store-signed.
	if is_dev_checkout "$LIVE"; then
		echo "dev"
	else
		echo "unknown"
	fi
}

remove_live() {
	local m
	m="$(current_mode)"
	run_occ app:disable "$APP_ID" || true
	if [[ -d "$LIVE" || -L "$LIVE" ]]; then
		assert_not_workspace "$LIVE"
		if [[ "$m" == "store" ]]; then
			echo "[switch] remove App Store copy at $LIVE"
			run_occ app:remove --keep-data "$APP_ID" || true
		else
			echo "[switch] remove live copy at $LIVE"
		fi
		if [[ -L "$LIVE" ]]; then
			rm -f "$LIVE"
		elif [[ -d "$LIVE" ]]; then
			rm -rf "$LIVE"
		fi
		[[ -n "$CONTAINER" ]] && docker_rm_path "$LIVE" 2>/dev/null || true
	fi
}

deploy_workspace_to_live() {
	echo "[switch] deploy $WORKSPACE → $LIVE"
	assert_not_workspace "$LIVE"
	mkdir -p "$LIVE"
	for path in "${RUNTIME_PATHS[@]}"; do
		if [[ -d "$WORKSPACE/$path" ]]; then
			rsync -a --delete "$WORKSPACE/$path/" "$LIVE/$path/"
		elif [[ -f "$WORKSPACE/$path" ]]; then
			rsync -a "$WORKSPACE/$path" "$LIVE/$path"
		else
			echo "[switch] missing required path: $WORKSPACE/$path" >&2
			exit 1
		fi
	done
	echo workspace > "$LIVE/.install-source"
	find "$LIVE" -name '*.map' -type f -delete 2>/dev/null || true
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

print_status() {
	local m ver=""
	m="$(current_mode)"
	if [[ -f "$LIVE/appinfo/info.xml" ]]; then
		ver="$(sed -n 's/.*<version>\([^<]*\)<\/version>.*/\1/p' "$LIVE/appinfo/info.xml" | head -1)"
	fi
	echo "mode:      $m"
	echo "workspace: $WORKSPACE"
	echo "live:      $LIVE${ver:+  (version $ver)}"
	run_occ app:list 2>/dev/null | grep -i "$APP_ID" || echo "$APP_ID: (not in occ app:list)"
}

NC_ROOT="$(detect_nc_root)"
OCC_CMD="$(resolve_occ)"
[[ -n "$NC_ROOT" ]] || { echo "Could not detect NEXTCLOUD_ROOT" >&2; exit 1; }
[[ -n "$OCC_CMD" ]] || { echo "Could not find occ" >&2; exit 1; }

CONTAINER=""
if [[ "$OCC_CMD" == docker\ exec* ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nextcloud-app'; then
	CONTAINER="nextcloud-app"
fi

WORKSPACE="${WORKSPACE:-$HOME/Workspace/$APP_ID}"
LIVE="$NC_ROOT/custom_apps/$APP_ID"

ensure_workspace_layout
if [[ -d "$WORKSPACE" || -L "$WORKSPACE" ]]; then
	WORKSPACE="$(realpath "$WORKSPACE")"
fi

if ! is_dev_checkout "$WORKSPACE"; then
	echo "[switch] missing git checkout at $WORKSPACE" >&2
	exit 1
fi

case "$mode" in
	status) print_status ;;
	sync)
		deploy_workspace_to_live
		run_occ upgrade || true
		print_status
		;;
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
		if [[ "$(current_mode)" == "store" ]]; then
			remove_live
		fi
		deploy_workspace_to_live
		run_occ app:enable "$APP_ID" || true
		run_occ upgrade || true
		print_status
		;;
	*) echo "Unknown mode: $mode" >&2; usage 1 ;;
esac
