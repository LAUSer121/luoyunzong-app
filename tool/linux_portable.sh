#!/usr/bin/env bash
# 把 Flutter Linux 发布目录打成「单文件便携版」：luoyunzong-portable.run
#
# 结构：可执行 shell 脚本头 + gzip 压缩的 tar 负载（makeself 同款思路，无需额外依赖）。
# 运行：./luoyunzong-portable.run          → 解压到数据目录并启动
#        ./luoyunzong-portable.run --extract-only → 只解压，不启动（用于自检）
# 数据目录：默认 ~/.local/share/luoyunzong-app/data（可用 LUOYUNZONG_DIR / LUOYUNZONG_DATA_DIR 覆盖）
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-$REPO_ROOT/build/linux/x64/release/bundle}"
OUT_FILE="${OUT_FILE:-$REPO_ROOT/dist/luoyunzong-portable.run}"
APP_EXE="${APP_EXE:-luoyunzong}"
TITLE="${TITLE:-落云宗 · 宗门管理}"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "[portable] 未找到 Linux 发布目录：$BUNDLE_DIR（请先 flutter build linux --release）" >&2
  exit 1
fi
if [ ! -x "$BUNDLE_DIR/$APP_EXE" ]; then
  echo "[portable] 发布目录缺少可执行文件：$BUNDLE_DIR/$APP_EXE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[portable] 压缩发布目录…"
tar -czf "$TMP_DIR/payload.tar.gz" -C "$BUNDLE_DIR" .

HEADER="$TMP_DIR/header.sh"
cat > "$HEADER" <<HEADER_EOF
#!/usr/bin/env bash
# $TITLE —— 单文件便携版（自解压启动器）
set -euo pipefail
ARCHIVE_LINE=\$(awk '/^__ARCHIVE_BELOW__\$/ {print NR + 1; exit 0; }' "\$0")
TARGET_DIR="\${LUOYUNZONG_DIR:-\${XDG_DATA_HOME:-\$HOME/.local/share}/luoyunzong-app}"
mkdir -p "\$TARGET_DIR"
tail -n +"\$ARCHIVE_LINE" "\$0" | tar -xz -C "\$TARGET_DIR"
chmod +x "\$TARGET_DIR/$APP_EXE" 2>/dev/null || true
export LUOYUNZONG_DATA_DIR="\${LUOYUNZONG_DATA_DIR:-\$TARGET_DIR/data}"
mkdir -p "\$LUOYUNZONG_DATA_DIR"
if [ "\${1:-}" = "--extract-only" ]; then
  echo "[portable] 已解压到：\$TARGET_DIR（数据目录：\$LUOYUNZONG_DATA_DIR）"
  exit 0
fi
cd "\$TARGET_DIR"
exec "./$APP_EXE" "\$@"
exit 0
__ARCHIVE_BELOW__
HEADER_EOF

echo "[portable] 拼装单文件 .run…"
cat "$HEADER" "$TMP_DIR/payload.tar.gz" > "$OUT_FILE"
chmod +x "$OUT_FILE"

SIZE_MB=$(( $(stat -c%s "$OUT_FILE") / 1024 / 1024 ))
echo "[portable] 生成：$OUT_FILE（${SIZE_MB} MB）"

echo "[portable] 验证自解压内容…"
VERIFY_DIR="$TMP_DIR/verify"
LUOYUNZONG_DIR="$VERIFY_DIR" "$OUT_FILE" --extract-only >/dev/null
if [ ! -x "$VERIFY_DIR/$APP_EXE" ]; then
  echo "[portable] 自解压验证失败：缺少 $APP_EXE" >&2
  exit 1
fi
echo "[portable] 验证通过：解压得到 $APP_EXE"
echo "[portable] 完成。"
