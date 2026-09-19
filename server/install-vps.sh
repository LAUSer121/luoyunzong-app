#!/usr/bin/env bash
# 落云宗 · 云同步服务端 一键安装（Ubuntu/Debian/CentOS 均可）
#
# 用法（在服务器的终端里执行，root 身份）：
#   curl -fsSL <脚本地址> | bash -s -- --token <API_TOKEN> --password <DB密码>
# 或者把本文件传上去再跑：
#   bash install-vps.sh --token xxx --password yyy
#
# 做的事：装 Node 20 → 放代码到 /opt/luoyunzong → 写 .env → systemd 开机自启 →
#         开防火墙端口 → 打印访问地址。重复执行会原地升级（代码/依赖会更新）。
set -euo pipefail

REPO="${REPO:-https://github.com/LAUSer121/luoyunzong-app.git}"
APP_DIR="${APP_DIR:-/opt/luoyunzong}"
PORT="${PORT:-8080}"
API_TOKEN=""
DB_PASSWORD=""
DB_HOST="${DB_HOST:-mysql-3818918f-jsjsjsnxjns-6e11.g.aivencloud.com}"
DB_PORT="${DB_PORT:-23483}"
DB_USER="${DB_USER:-avnadmin}"
DB_NAME="${DB_NAME:-defaultdb}"
ORG_ID="${ORG_ID:-default}"
MAX_UPLOAD_MB="${MAX_UPLOAD_MB:-512}"

while [ $# -gt 0 ]; do
  case "$1" in
    --token) API_TOKEN="$2"; shift 2 ;;
    --password) DB_PASSWORD="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --dir) APP_DIR="$2"; shift 2 ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
done

if [ "$(id -u)" != "0" ]; then
  echo "请用 root 运行（sudo bash install-vps.sh ...）"; exit 1
fi
if [ -z "$API_TOKEN" ] || [ -z "$DB_PASSWORD" ]; then
  echo "必须提供 --token 和 --password（App 里用的访问令牌 / 数据库密码）"; exit 1
fi

echo "[1/6] 安装 Node 20 与 git ..."
if ! command -v node >/dev/null 2>&1 || [ "$(node -v | cut -c2-3)" -lt 18 ]; then
  if command -v apt-get >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1 || true
    apt-get install -y nodejs git >/dev/null 2>&1 || apt-get update >/dev/null 2>&1 && apt-get install -y nodejs git
  elif command -v dnf >/dev/null 2>&1; then
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - >/dev/null 2>&1 || true
    dnf install -y nodejs git
  else
    echo "认不出系统，请自行安装 Node 20 后重跑"; exit 1
  fi
fi
echo "  node $(node -v)"

echo "[2/6] 拉取代码到 $APP_DIR ..."
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" fetch --depth 1 origin main >/dev/null 2>&1
  git -C "$APP_DIR" reset --hard origin/main >/dev/null 2>&1
else
  mkdir -p "$APP_DIR"
  git clone --depth 1 "$REPO" "$APP_DIR"
fi

echo "[3/6] 安装依赖 ..."
cd "$APP_DIR/server"
npm install --omit=dev --no-fund --no-audit >/dev/null 2>&1

echo "[4/6] 写配置 $APP_DIR/server/.env ..."
cat > "$APP_DIR/server/.env" <<EOF
PORT=$PORT
ORG_ID=$ORG_ID
API_TOKEN=$API_TOKEN
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
DB_SSL=true
DB_POOL=4
MAX_UPLOAD_MB=$MAX_UPLOAD_MB
EOF
chmod 600 "$APP_DIR/server/.env"

echo "[5/6] 注册 systemd 服务（开机自启 + 崩溃自动重启）..."
cat > /etc/systemd/system/luoyunzong-api.service <<EOF
[Unit]
Description=Luoyunzong Cloud Sync API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR/server
ExecStart=$(command -v node) index.mjs
Restart=always
RestartSec=3
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable luoyunzong-api >/dev/null 2>&1
systemctl restart luoyunzong-api

echo "[6/6] 放行防火墙 / 安全组端口 $PORT ..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q active; then
  ufw allow "$PORT"/tcp >/dev/null 2>&1 || true
fi
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="$PORT"/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi
# 云厂商的「安全组」要在网页控制台里放行，脚本管不到
IP="$(curl -fsSL --max-time 8 https://ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')"
sleep 2
echo
echo "==================== 安装完成 ===================="
systemctl is-active luoyunzong-api >/dev/null 2>&1 && echo "服务状态：运行中 ✅" || echo "服务状态：未运行 ❌（看 systemctl status luoyunzong-api）"
echo "健康检查：curl http://127.0.0.1:$PORT/api/health"
echo "给 App 用的地址：http://$IP:$PORT"
echo
echo "⚠️ 还要去云厂商控制台把「安全组/防火墙」的 TCP $PORT 放行，外网才连得上。"
echo "常用命令：systemctl restart luoyunzong-api / journalctl -u luoyunzong-api -f"
echo "================================================="
