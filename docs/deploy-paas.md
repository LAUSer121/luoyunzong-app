# 把服务端部署到免费 PaaS（电脑关机也能用）

现状：**数据库在 Aiven、图片在缤纷云，但接口进程跑在你电脑上** ——
所以你电脑一关，手机/其它设备就同步不了（本机存档照常能用，联网后自动补齐）。

把接口进程搬到一台常开的机器上就彻底解决。下面两条路都免费。

---

## 路线 A：Render（推荐，免费档）

### A1. 点几下（Blueprint）

1. 打开 <https://dashboard.render.com> → 用 GitHub 登录（仓库是公开的，不用额外授权）；
2. **New → Blueprint** → 选 `LAUSer121/luoyunzong-app` → Render 会自动读到根目录的 `render.yaml`；
3. 面板只会让你填两个密钥（其余值我在 `render.yaml` 里已经写好了）：

   | 变量 | 值 |
   | --- | --- |
   | `DB_PASSWORD` | `server/.env` 里的 `DB_PASSWORD` |
   | `API_TOKEN` | `server/.env` 里的 `API_TOKEN` |

4. 点 **Apply / Deploy**，等 2~4 分钟，拿到形如
   `https://luoyunzong-api.onrender.com` 的地址；
5. 浏览器打开 `https://luoyunzong-api.onrender.com/api/health`，看到
   `{"ok":true,...}` 就成功了。

### A2. 用 API Key 一键创建（我可以代做）

在 Render → **Account Settings → API Keys → Create API Key**，把 Key 发我，
我直接调 Render API 把服务建好（含两个密钥、区域、健康检查），
并把 CI 里的 `LUOYUNZONG_API_BASE` 改成新地址、重新构建一次。

命令大致是：

```bash
curl -X POST https://api.render.com/v1/services \
  -H "Authorization: Bearer $RENDER_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "web_service",
    "name": "luoyunzong-api",
    "ownerId": "<你的 ownerId>",
    "repo": "https://github.com/LAUSer121/luoyunzong-app",
    "branch": "main",
    "autoDeploy": "yes",
    "serviceDetails": {
      "env": "docker",
      "plan": "free",
      "region": "singapore",
      "healthCheckPath": "/api/health",
      "envVars": [
        {"key": "DB_HOST", "value": "mysql-3818918f-jsjsjsnxjns-6e11.g.aivencloud.com"},
        {"key": "DB_PORT", "value": "23483"},
        {"key": "DB_USER", "value": "avnadmin"},
        {"key": "DB_NAME", "value": "defaultdb"},
        {"key": "DB_SSL", "value": "true"},
        {"key": "DB_PASSWORD", "value": "..."},
        {"key": "API_TOKEN", "value": "..."}
      ]
    }
  }'
```

---

## 路线 B：Railway（免费试用额度，构建更快）

1. <https://railway.app> → New Project → **Deploy from GitHub repo** → 选本仓库；
2. Railway 会读根目录 `railway.json`（用 `server/Dockerfile` 构建）；
3. 在 **Variables** 里加：`DB_HOST` `DB_PORT` `DB_USER` `DB_PASSWORD` `DB_NAME` `DB_SSL=true` `API_TOKEN`；
4. Settings → Networking → **Generate Domain**，拿到 `https://xxx.up.railway.app`。

---

## 部署完之后（必做）

把新地址写进 CI，让**新构建出来的安装包**默认连云：

```bash
gh variable set LUOYUNZONG_API_BASE --body "https://luoyunzong-api.onrender.com"
gh workflow run build.yml --ref main
```

> 如果手机也要在外网用，地址必须是 **https** 的 PaaS 域名（自带证书），
> 不能再是 `http://192.168.x.x:8080` 那种局域网地址。

---

## 两个注意点

1. **免费档会休眠**：Render 免费实例闲置约 15 分钟后休眠，下一次请求要等十几秒唤醒。
   App 里表现为「云端暂不可达，稍后会自动重试」，**不会丢数据**；
   你也可以用任意定时任务每 10 分钟访问一次 `/api/health` 把它保活。
2. **对象存储必须有**：PaaS 的磁盘是临时的，重启就没了。
   把「设置 → 云端资源存储」配成**缤纷云**（现在已经是了），
   数据库里只留索引，图片视频都在缤纷云 ✓。
   记得先把缤纷云子账户 `mymedia` 对 `my-media` 桶的读写权限打开，否则上传会 403。

---

## 本地那台电脑上的服务端怎么办

部署好 PaaS 之后，你电脑上的服务端就可以不用了：

```powershell
powershell -File server\start-server.ps1 -Uninstall   # 取消登录自启
```

想留作备用也行 —— 把 `LUOYUNZONG_API_BASE` 写成两个地址（逗号分隔），
App 启动会按顺序探测，哪个通用哪个：

```bash
gh variable set LUOYUNZONG_API_BASE --body "https://luoyunzong-api.onrender.com,http://127.0.0.1:8080"
```
