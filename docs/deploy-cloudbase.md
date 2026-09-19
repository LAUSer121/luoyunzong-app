# 部署到腾讯云 CloudBase（云开发）—— 不用信用卡，国内直连

CloudBase 提供一个固定的 HTTPS 地址（`https://<环境ID>.service.tcloudbase.com`），
国内手机直接能连，**你电脑关机也不影响**。

---

## 一、你在控制台做三件事（约 5 分钟）

1. **开通云开发**：打开 <https://console.cloud.tencent.com/tcb> → 「新建环境」→
   计费方式选 **按量付费**（有免费额度，个人用基本花不到钱）→
   环境名随意，比如 `luoyunzong`，记住 **环境 ID**（形如 `luoyunzong-3g1a2b3c4d5e6`）。
2. **建 API 密钥**：<https://console.cloud.tencent.com/cam/capi> → 「新建密钥」，
   复制 **SecretId / SecretKey**（有了它我就能用命令行帮你部署，不用你点命令行）。
3. （可选）如果你希望我全程代做，把 **环境 ID + SecretId + SecretKey** 发我即可。

> 这两个密钥权限很大，我只会用它来：上传云函数、设置函数环境变量、
> 配置 HTTP 访问服务。用完你可以在控制台「禁用/删除」这把密钥。

---

## 二、我拿到密钥后会做的事

```bash
# 1) 组装函数目录（把 server/ 源码拷进函数包）
pwsh -File deploy/cloudbase/build.ps1

# 2) 登录（用 API 密钥，无需浏览器）
npx @cloudbase/cli login --apiKeyId <SecretId> --apiKey <SecretKey>

# 3) 写入 9 个环境变量（DB 连接 + 令牌 + 上限）
npx @cloudbase/cli fn config update luoyunzong-api -e <环境ID> \
  --envVariables '{"DB_HOST":"...","DB_PORT":"23483",...}'

# 4) 部署函数（云端自动 npm install）
npx @cloudbase/cli fn deploy luoyunzong-api -e <环境ID> --force
```

5）在控制台 **「HTTP 访问服务」** 里把路径 `/` 指向函数 `luoyunzong-api`
（一步点击；我也可以用 CLI 配好）；
6）访问 `https://<环境ID>.service.tcloudbase.com/api/health` 验证 `{"ok":true,...}`；
7）把这个地址写进 CI：`gh variable set LUOYUNZONG_API_BASE --body "https://..."`，
   然后 `gh workflow run build.yml --ref main` 重新出包。

---

## 三、为什么这套架构适合 serverless

- **大文件不经过云函数**：App 先向 `/api/assets/sign` 要一个**缤纷云预签名 URL**，
  然后**直传缤纷云**，完事再 `/api/assets/commit` 登记 —— 视频多大都行，
  不受云函数请求体上限（约 6MB）影响。
- **回读也直连缤纷云**：`/api/assets/links` 返回预签名 GET，App 直接从缤纷云下载。
- 存档本身只存 `asset:<id>` 引用，很小，云函数读写毫无压力。
- 云函数无状态，冷启动约 1~3 秒；App 侧有「稍后自动重试」，无感。

---

## 四、备选：不用命令行也能部署

控制台 → 云函数 → 新建函数（Nodejs 18.15）→ 把 `deploy/cloudbase/functions/luoyunzong-api/`
整个目录打包成 zip 上传（先跑一次 `build.ps1` 把 `server/` 拷进去）→
在「函数配置 → 环境变量」里填那 9 个变量 → 「HTTP 访问服务」加路径 `/`。

两种方式效果一样，用哪种都行。
