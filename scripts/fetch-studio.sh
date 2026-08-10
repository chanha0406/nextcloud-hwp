#!/usr/bin/env bash
# Re-download rhwp-studio static assets into ./studio
# Rewrites /rhwp/ → /custom_apps/hwp_viewer/studio/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/rhwp-studio-mirror-$$"
BASE_URL="https://edwardkim.github.io/rhwp"
APP_BASE="/custom_apps/hwp_viewer/studio"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "[fetch-studio] mirroring $BASE_URL …"
mkdir -p "$TMP"
wget -q --show-progress -r -np -nH --cut-dirs=1 \
  -e robots=off --timeout=30 --tries=3 \
  -R '*.map' \
  -P "$TMP" \
  "$BASE_URL/" \
  "$BASE_URL/theme-init.js" \
  "$BASE_URL/registerSW.js" \
  "$BASE_URL/manifest.webmanifest"

mkdir -p "$TMP/assets" "$TMP/fonts"

python3 - "$TMP" "$BASE_URL" "$APP_BASE" <<'PY'
import re, sys, pathlib, urllib.request

tmp, base_url, app_base = sys.argv[1:4]
assets = pathlib.Path(tmp) / "assets"
js_path = next(assets.glob("index-*.js"))
js = js_path.read_text(encoding="utf-8", errors="ignore")

m = re.search(r"rhwp_bg-[A-Za-z0-9_-]+\.wasm", js)
if not m:
    raise SystemExit("Could not detect wasm asset name")
wasm = m.group(0)
print(f"[fetch-studio] wasm {wasm}")
urllib.request.urlretrieve(f"{base_url}/assets/{wasm}", assets / wasm)

fonts = sorted(set(re.findall(r"fonts/[A-Za-z0-9._-]+\.woff2", js)))
dst = pathlib.Path(tmp)
for f in fonts:
    out = dst / f
    out.parent.mkdir(parents=True, exist_ok=True)
    print(f"[fetch-studio] {f}")
    urllib.request.urlretrieve(f"{base_url}/{f}", out)

for p in dst.rglob("*"):
    if not p.is_file():
        continue
    if p.suffix.lower() not in {".html", ".js", ".css", ".webmanifest", ".json", ".svg"}:
        continue
    data = p.read_text(encoding="utf-8", errors="ignore")
    if "/rhwp/" not in data:
        continue
    new = data.replace("/rhwp/", app_base + "/")
    if p.name == "index.html":
        sw = f'<script id="vite-plugin-pwa:register-sw" src="{app_base}/registerSW.js"></script>'
        mf = f'<link rel="manifest" href="{app_base}/manifest.webmanifest">'
        new = new.replace(sw, "").replace(mf, "")
    p.write_text(new, encoding="utf-8")
    print(f"[fetch-studio] rewrote {p.relative_to(dst)}")
PY

rm -rf "$ROOT/studio"
# move contents; keep TMP for trap by swapping
mv "$TMP" "$ROOT/studio"
mkdir -p "$TMP"
echo "[fetch-studio] done → $ROOT/studio"
