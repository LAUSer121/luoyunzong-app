# 落云宗 · 云同步服务端

把 App 的存档与资源（头像 / 立绘 / 背景图 / 动态视频）存到 **Aiven MySQL + 又拍云对象存储**。

- 存档：`archives.payload`（JSON；大资源在存档里只留 `asset:<id>` 引用）
- 资源：`assets` 表记录索引，字节按 `STORAGE_DRIVER` 决定落本地磁盘 / 又拍云 / S3
- 客户端：`ApiRepository`（App 设置里填服务地址 + 令牌即可，断网自动回落本地）

---

## 一、快速开始

### 最省事：直接在这台电脑上跑（Windows，零成本）

数据其实存在 Aiven MySQL 里，这台电脑只跑一个接口进程；电脑开着的时候，
本机 App 与**家里同一个 Wi-Fi 下的手机**都能连上同步。

```powershell
cd server
copy .env.example .env        # 填 Aiven 参数（只需一次）
npm install                   # 只需一次

# 前台运行（关掉窗口就停）
powershell -File server\start-server.ps1

# 开机自动后台运行 + 放行防火墙（手机要连必须放行，建议管理员运行）
powershell -File server\start-server.ps1 -Install

# 看状态：进程在不在、数据库通不通、本机可用的同步地址
powershell -File server\start-server.ps1 -Status
```

把 `-Status` 打印的局域网地址配进构建（多个地址用逗号分隔，App 会按顺序探测）：

```powershell
gh variable set LUOYUNZONG_API_BASE --body "http://127.0.0.1:8080,http://192.168.1.15:8080"
gh workflow run build.yml --ref main
```

一份安装包同时覆盖「电脑上双击即用」（走 `127.0.0.1`）和「手机在家连同一台电脑」
（走局域网地址）。手机在**外网**时连不上，App 自动回落本地存档继续可用，
回家后自动同步补齐，不会丢数据。

> 局域网地址由路由器 DHCP 分配，换网络/重启路由可能变；变了就再跑一次
> `-Status` 拿新地址，更新仓库变量后重新构建即可。
> Windows 防火墙放行需要管理员权限，脚本会自动尝试并给出提示。

### 传统方式（在 server/ 目录直接起）

```bash
cd server
cp .env.example .env      # 填 Aiven 与又拍云参数
npm install

npm run check             # 1) 检查 MySQL 连接（SSL / 版本 / 读写）
npm run schema            # 2) 建表（幂等）
npm run storage:check     # 3) 检查资源存储（local 直接过；upyun 需操作员密码）
npm start                 # 4) 启动服务：http://127.0.0.1:8080

npm run inspect           # 查看云端数据概览；加 --clean 清理测试数据
```

`.env` 关键项：

| 变量 | 说明 |
| --- | --- |
| `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASSWORD` / `DB_NAME` | Aiven 控制台「Connection information」里的值，`DB_SSL=true`（Aiven 强制 TLS） |
| `API_TOKEN` | 客户端要填同一个令牌；留空则不校验（仅本机调试） |
| `STORAGE_DRIVER` | `local`（服务器磁盘）/ `upyun`（又拍云）/ `s3`（R2、MinIO 等） |
| `UPYUN_BUCKET` / `UPYUN_OPERATOR` / `UPYUN_PASSWORD` / `UPYUN_DOMAIN` | 又拍云的**服务名**、**操作员**及其**密码**、绑定的访问域名 |
| `S3_*` | 用 Cloudflare R2 / MinIO 时的参数 |

> **又拍云的坑**：控制台「子账户 & Key」里的 AccessKey / SecretKey 是给**管理类接口**
> （刷新缓存、统计等）用的；**上传文件**要的是「操作员 + 操作员密码」（在
> 控制台 →「服务」→「配置」→ 操作员授权里设置/重置），并把这个操作员授权给对应服务。
> 没填 `UPYUN_PASSWORD` 时请先用 `STORAGE_DRIVER=local`。

## 二、接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/health` | 健康检查（App 设置页「测试连接」调它） |
| POST | `/api/auth/verify` | 校验管理员密码（优先 `admins` 表，回落存档里的密码） |
| GET | `/api/archive` | 读取整包存档 |
| PUT | `/api/archive` | 覆盖写入存档（revision +1） |
| DELETE | `/api/archive` | 清空存档 |
| POST | `/api/assets?id=&mime=` | 上传资源（body 为二进制，按 id 去重） |
| GET | `/api/assets/batch?ids=a,b,c` | 批量取回资源（base64） |
| GET | `/assets/<id>.<ext>` | `local` 驱动时的直链（对象存储则 302 到 URL） |

鉴权：`Authorization: Bearer <API_TOKEN>`（`/api/health` 与 `/assets/*` 不需要）。

## 三、部署到服务器

```bash
# 方式一：裸机（最省事）
sudo apt install -y nodejs npm
npm ci --omit=dev && npm run schema
pm2 start index.mjs --name luoyunzong-api && pm2 save

# 方式二：Docker
docker compose up -d --build

# HTTPS 反代（Caddy 自动申请证书；Android 9+ 不允许明文 HTTP，必须上 TLS）
echo 'api.你的域名.com { reverse_proxy 127.0.0.1:8080 }' | sudo tee /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

备份（Aiven 免费版自带每日备份，导出一份更稳妥）：

```bash
mysqldump --single-transaction -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
  | gzip > /backup/lyz-$(date +%F).sql.gz
```

## 四、容量参考（Aiven 免费版：1 CPU / 1 GB RAM / **1 GB 存储**）

| 内容 | 大小 | 放哪合适 |
| --- | --- | --- |
| 头像 256px | 20–60 KB | DB（内联在存档里，小于 48KB 不拆分） |
| 立绘 720px | 150–400 KB | DB `assets.bytes` 或又拍云 |
| 背景 1920px | 300–900 KB | 同上 |
| 视频 | 单条 ≤20 MB | **必须对象存储**（又拍云 / R2 / COS） |

> 免费版 1 GB：图片存几百张没问题；**只要开始放视频，就把 `STORAGE_DRIVER` 切到 `upyun`**，
> 否则很快撑满。DB 里 `assets.bytes` 只在 `local` 驱动时才写入，切对象存储后自动只存 URL。

## 五、客户端对接

App →「设置 → 数据源」：

1. 服务端地址：`https://api.你的域名.com`
2. 访问令牌：与 `.env` 的 `API_TOKEN` 一致
3. 打开「使用云端同步」→ 保存并测试连接

也可以在构建时直接烧进默认值（打包出来的 exe / apk 打开即是云端模式）：

```bash
flutter build windows --release \
  --dart-define=LUOYUNZONG_API_BASE=https://api.你的域名.com \
  --dart-define=LUOYUNZONG_API_TOKEN=你的令牌
```

CI 里对应加两个变量（`LUOYUNZONG_API_BASE`、`LUOYUNZONG_API_TOKEN`）传给 `--dart-define` 即可；
`LUOYUNZONG_API_BASE` 支持逗号分隔的多个候选地址（App 启动时按顺序探测连通性）。

---

## 六、不想买服务器？用免费 PaaS（5 分钟上线，Aiven 直连）

仓库根目录已经放好两个部署描述文件，选一个即可：

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| **Render**（推荐，免费层） | `render.yaml` | Blueprint 一键部署；免费实例闲置会休眠，首次访问慢几秒 |
| Railway | `railway.json` | 新账号有试用额度，构建更快 |
| Fly.io / 自己的 VPS | `server/Dockerfile` | `docker compose up -d --build` |

步骤（Render 为例）：

1. 打开 <https://dashboard.render.com> → New → **Blueprint** → 选本仓库；
2. 按提示填环境变量（`DB_HOST` / `DB_PASSWORD` / `API_TOKEN` 等，值见 `server/.env`）；
3. 部署完成后拿到形如 `https://luoyunzong-api.onrender.com` 的 HTTPS 地址；
4. 把这个地址写进 GitHub 仓库变量，之后**每次构建出来的单文件都默认连云**：

```bash
gh variable set LUOYUNZONG_API_BASE --body "https://luoyunzong-api.onrender.com"
gh secret   set LUOYUNZONG_API_TOKEN --body "你的 API_TOKEN"
gh workflow run build.yml --ref main     # 重新构建
```

> App 里不会显示这个地址，也不会显示任何数据库信息；设置页只显示「云端同步」状态。
> 地址不可达时会**自动回落本地存档**，不会卡住或丢数据。

### 临时测试（不部署也能用）

`server/scripts/tunnel.ps1` 会在本机起服务端 + Cloudflare 快速隧道，打印一个临时 HTTPS 地址。
免费隧道**每次重启地址都会变**，只适合临时联调；长期使用请用上面的 PaaS 或小服务器。
