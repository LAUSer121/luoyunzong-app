#!/usr/bin/env bash
# 把 Flutter macOS 应用打成「单文件便携版」：luoyunzong-macos.dmg
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="${RELEASE_DIR:-$REPO_ROOT/build/macos/Build/Products/Release}"
OUT_FILE="${OUT_FILE:-$REPO_ROOT/dist/luoyunzong-macos.dmg}"
VOL_NAME="${VOL_NAME:-落云宗}"

APP_PATH="$(find "$RELEASE_DIR" -maxdepth 1 -name '*.app' | head -n 1)"
if [ -z "${APP_PATH:-}" ]; then
  echo "[portable] 未找到 .app（请先 flutter build macos --release）" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"
rm -f "$OUT_FILE"

echo "[portable] 生成 DMG：$OUT_FILE"
hdiutil create -volname "$VOL_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$OUT_FILE" >/dev/null

SIZE_MB=$(( $(stat -f%z "$OUT_FILE") / 1024 / 1024 ))
echo "[portable] 生成完成（${SIZE_MB} MB）"

echo "[portable] 验证挂载…"
MOUNT_POINT="$(mktemp -d)"
hdiutil attach "$OUT_FILE" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
ls "$MOUNT_POINT" | head -5
hdiutil detach "$MOUNT_POINT" -quiet
rmdir "$MOUNT_POINT" 2>/dev/null || true
echo "[portable] 验证通过。"
