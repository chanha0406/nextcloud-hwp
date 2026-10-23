#!/usr/bin/env bash
# Build a Nextcloud App Store release tarball (and optionally code-sign it).
#
# Usage:
#   ./scripts/build-release.sh              # build + package (sign if certs exist)
#   ./scripts/build-release.sh --no-sign    # package only
#   ./scripts/build-release.sh --skip-build # reuse existing js/ build
#
# Env:
#   CERT_DIR       default: ~/.nextcloud/certificates
#   OCC            path to occ, or a wrapper command (e.g. docker exec … php occ)
#   NEXTCLOUD_ROOT if set and OCC unset, uses $NEXTCLOUD_ROOT/occ
set -euo pipefail

APP_ID="hwpdocuments"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERT_DIR="${CERT_DIR:-$HOME/.nextcloud/certificates}"
KEY="$CERT_DIR/${APP_ID}.key"
CRT="$CERT_DIR/${APP_ID}.crt"
OUT_DIR="$ROOT/build/artifacts/appstore"
STAGE_ROOT="$ROOT/build/stage"
STAGE="$STAGE_ROOT/${APP_ID}"
SIGN=1
DO_BUILD=1

for arg in "$@"; do
	case "$arg" in
		--no-sign) SIGN=0 ;;
		--skip-build) DO_BUILD=0 ;;
		-h|--help)
			sed -n '2,14p' "$0"
			exit 0
			;;
		*)
			echo "Unknown option: $arg" >&2
			exit 1
			;;
	esac
done

version="$(sed -n 's/.*<version>\([^<]*\)<\/version>.*/\1/p' "$ROOT/appinfo/info.xml" | head -1)"
if [[ -z "$version" ]]; then
	echo "Could not read <version> from appinfo/info.xml" >&2
	exit 1
fi

tarball="$OUT_DIR/${APP_ID}-${version}.tar.gz"
signature_file="$OUT_DIR/${APP_ID}-${version}.tar.gz.sig"

resolve_occ() {
	if [[ -n "${OCC:-}" ]]; then
		echo "$OCC"
		return
	fi
	if [[ -n "${NEXTCLOUD_ROOT:-}" && -x "${NEXTCLOUD_ROOT}/occ" ]]; then
		echo "php ${NEXTCLOUD_ROOT}/occ"
		return
	fi
	# Common local Docker setup from README
	if command -v docker >/dev/null 2>&1 \
		&& docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nextcloud-app'; then
		echo "docker exec -u www-data nextcloud-app php occ"
		return
	fi
	echo ""
}

docker_occ_container() {
	local -a tokens
	# shellcheck disable=SC2206
	tokens=($1)
	local i=0
	local seen_exec=0
	while (( i < ${#tokens[@]} )); do
		local t="${tokens[$i]}"
		if (( seen_exec == 0 )); then
			if [[ "$t" == "exec" ]]; then
				seen_exec=1
			fi
			i=$((i + 1))
			continue
		fi
		case "$t" in
			-u|--user|-w|--workdir|-e|--env)
				i=$((i + 2))
				continue
				;;
			-*)
				i=$((i + 1))
				continue
				;;
			*)
				echo "$t"
				return 0
				;;
		esac
	done
	return 1
}

host_to_container_path() {
	local container="$1"
	local host_path="$2"
	local real src dst
	real="$(realpath "$host_path")"
	while IFS=$'\t' read -r src dst; do
		[[ -z "$src" ]] && continue
		local src_real
		src_real="$(realpath "$src" 2>/dev/null || echo "$src")"
		if [[ "$real" == "$src_real" || "$real" == "$src_real"/* ]]; then
			echo "${dst}${real#"$src_real"}"
			return 0
		fi
	done < <(docker inspect "$container" --format '{{range .Mounts}}{{.Source}}{{"\t"}}{{.Destination}}{{println}}{{end}}')
	return 1
}

cleanup_docker_sign() {
	local container="${SIGN_CONTAINER:-}"
	[[ -n "$container" ]] || return 0
	docker exec "$container" rm -rf "/tmp/${APP_ID}-certs" "/tmp/${APP_ID}-stage" >/dev/null 2>&1 || true
}

prepare_docker_sign_paths() {
	local occ_cmd="$1"
	local container
	container="$(docker_occ_container "$occ_cmd")"
	if [[ -z "$container" ]]; then
		echo "[release] ERROR: could not parse docker container from OCC" >&2
		return 1
	fi
	SIGN_CONTAINER="$container"

	local remote_dir="/tmp/${APP_ID}-certs"
	docker exec "$container" mkdir -p "$remote_dir"
	docker cp "$KEY" "$container:$remote_dir/${APP_ID}.key"
	docker cp "$CRT" "$container:$remote_dir/${APP_ID}.crt"
	docker exec "$container" chown www-data:www-data "$remote_dir/${APP_ID}.key" "$remote_dir/${APP_ID}.crt"
	docker exec "$container" chmod 600 "$remote_dir/${APP_ID}.key"

	SIGN_KEY="$remote_dir/${APP_ID}.key"
	SIGN_CRT="$remote_dir/${APP_ID}.crt"
	SIGN_STAGE_COPIED=0

	local stage_in_container
	if stage_in_container="$(host_to_container_path "$container" "$STAGE")"; then
		SIGN_PATH="$stage_in_container"
		return 0
	fi

	local remote_stage="/tmp/${APP_ID}-stage"
	docker exec "$container" rm -rf "$remote_stage"
	docker cp "$STAGE" "$container:$remote_stage"
	docker exec "$container" chown -R www-data:www-data "$remote_stage"
	SIGN_PATH="$remote_stage"
	SIGN_STAGE_COPIED=1
}

if [[ "$DO_BUILD" -eq 1 ]]; then
	echo "[release] npm ci && npm run build"
	cd "$ROOT"
	if [[ -f package-lock.json ]]; then
		npm ci
	else
		npm install
	fi
	npm run build
fi

if [[ ! -f "$ROOT/js/hwpdocuments-main.mjs" ]]; then
	echo "Missing js/hwpdocuments-main.mjs — run build first." >&2
	exit 1
fi
if [[ ! -d "$ROOT/studio" || ! -f "$ROOT/studio/index.html" ]]; then
	echo "Missing studio/ — run ./scripts/fetch-studio.sh first." >&2
	exit 1
fi

echo "[release] staging $STAGE"
rm -rf "$STAGE_ROOT"
mkdir -p "$STAGE" "$OUT_DIR"

# Explicit allow-list: runtime only (no src/, node_modules/, tooling).
for path in appinfo css img js l10n lib studio LICENSE README.md; do
	if [[ ! -e "$ROOT/$path" ]]; then
		echo "Missing required path: $path" >&2
		exit 1
	fi
	cp -a "$ROOT/$path" "$STAGE/"
done
find "$STAGE" -name '*.map' -type f -delete

if [[ "$SIGN" -eq 1 ]]; then
	if [[ -f "$KEY" && -f "$CRT" ]]; then
		occ_cmd="$(resolve_occ)"
		if [[ -z "$occ_cmd" ]]; then
			echo "[release] WARN: certs found but no occ (set OCC or NEXTCLOUD_ROOT)." >&2
			echo "[release]        Packaging unsigned integrity; App Store still needs signature.json." >&2
		else
			SIGN_KEY="$KEY"
			SIGN_CRT="$CRT"
			SIGN_PATH="$STAGE"
			SIGN_CONTAINER=""
			SIGN_STAGE_COPIED=0
			if [[ "$occ_cmd" == docker\ exec* ]]; then
				echo "[release] copying certs into docker for occ (host CERT_DIR=$CERT_DIR)"
				prepare_docker_sign_paths "$occ_cmd"
			fi
			echo "[release] integrity:sign-app via: $occ_cmd"
			# shellcheck disable=SC2086
			if ! $occ_cmd integrity:sign-app \
				--privateKey="$SIGN_KEY" \
				--certificate="$SIGN_CRT" \
				--path="$SIGN_PATH"; then
				cleanup_docker_sign
				exit 1
			fi
			if [[ "$SIGN_STAGE_COPIED" -eq 1 ]]; then
				docker cp "$SIGN_CONTAINER:$SIGN_PATH/appinfo/signature.json" "$STAGE/appinfo/signature.json"
			fi
			cleanup_docker_sign
			if [[ ! -f "$STAGE/appinfo/signature.json" ]]; then
				echo "[release] ERROR: signature.json was not created" >&2
				exit 1
			fi
		fi
	else
		echo "[release] WARN: no certs at $KEY / $CRT — skipping integrity sign." >&2
		echo "[release]        Run ./scripts/gen-cert.sh then submit CSR; after .crt arrives, re-run." >&2
	fi
else
	echo "[release] --no-sign: skipping integrity sign"
fi

echo "[release] creating $tarball"
tar -czf "$tarball" -C "$STAGE_ROOT" "$APP_ID"

# App Store upload signature (openssl over the archive), separate from integrity:sign-app
if [[ "$SIGN" -eq 1 && -f "$KEY" ]]; then
	echo "[release] openssl archive signature → $signature_file"
	openssl dgst -sha512 -sign "$KEY" "$tarball" | openssl base64 -A > "$signature_file"
	echo
	echo "App Store upload fields:"
	echo "  download:  (host $tarball or attach to a GitHub Release)"
	echo "  signature: $(cat "$signature_file")"
fi

sha256="$(sha256sum "$tarball" | awk '{print $1}')"
size="$(du -h "$tarball" | awk '{print $1}')"
echo
echo "[release] done"
echo "  file:   $tarball"
echo "  size:   $size"
echo "  sha256: $sha256"
if [[ -f "$STAGE/appinfo/signature.json" ]]; then
	echo "  integrity: signed (appinfo/signature.json in archive)"
else
	echo "  integrity: NOT signed"
fi
