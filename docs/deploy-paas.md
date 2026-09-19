# 把服务端部署到常开的机器（电脑关机也能用）

现状：**数据库在 Aiven、图片在缤纷云，但接口进程跑在你电脑上** ——
所以你电脑一关，手机/其它设备就同步不了（本机存档照常能用，联网后自动补齐）。

把接口进程搬到一台常开的机器上就彻底解决。

> 境外免费 PaaS 的实测结论（2026-09）：
> - **Hugging Face Spaces**：官方原话「Static Spaces 免费，但 Docker/Gradio Space 用免费
>   cpu-basic 需要 PRO（$9/月）」→ 走不通（而且国内访问本就不稳）。
> - **Render**：免费实例要个人 workspace 或绑定支付方式，team workspace 直接 402 → 要信用卡。
> - **Railway / Fly.io / Koyeb**：都要信用卡。
> - **Vercel**：注册在部分网络环境下打不开。
>
> 所以下面主推「国内轻量服务器」，并保留 Vercel 的配置（能用的时候直接跑）。

---

## 方案 A：国内轻量云服务器（推荐，¥60–100/年，支付宝付款）

优点：国内 IP，手机在外面直连、不用科学上网；固定地址；不会被休眠；一条命令装完。

1. 买一台（新用户常有首年特惠，1核1G 够用）：
   - 腾讯云轻量应用服务器 <https://cloud.tencent.com/product/lighthouse>
   - 阿里云轻量应用服务器 <https://www.aliyun.com/product/swas>
   - 系统选 **Ubuntu 22.04**，买完在控制台记下「公网 IP」和 root 密码；
2. 在控制台的**安全组 / 防火墙**里放行 **TCP 8080**（这一步必须做）；
3. 打开控制台的 **网页终端**（或用自己的 SSH），粘贴下面两行（把两个值换成你的）：

   ```bash
   curl -fsSL https://cdn.jsdelivr.net/gh/LAUSer121/luoyunzong-app@main/server/install-vps.sh -o install.sh
   sudo bash install.sh --token 你的API_TOKEN --password 你的数据库密码
   ```

   脚本会：装 Node 20 → 把代码放到 `/opt/luoyunzong` → 写 `.env` → 注册 systemd
   开机自启与崩溃自动重启 → 放行端口 → 打印 `http://公网IP:8080`。
   重复执行＝原地升级（拉最新代码 + 重装依赖 + 重启服务）。

4. 浏览器打开 `http://公网IP:8080/api/health`，看到 `{"ok":true,...}` 就成功；
5. 把地址写进 CI（见文末「部署完之后」），重新构建安装包。

> 两个值在 `server/.env` 里：`API_TOKEN` 与 `DB_PASSWORD`。
> 想要 HTTPS（可选）：给 IP 绑个域名后装 Caddy：`apt install caddy` →
> `/etc/caddy/Caddyfile` 写 `api.你的域名.com { reverse_proxy 127.0.0.1:8080 }` → `systemctl reload caddy`。
> 没有域名也行 —— App 已允许明文 HTTP，`http://IP:8080` 直接可用。

常用运维：

```bash
systemctl status luoyunzong-api      # 看状态
systemctl restart luoyunzong-api     # 重启
journalctl -u luoyunzong-api -f      # 看日志
```

---

## 方案 B：Vercel 免费版（不用卡、不休眠；代码已就绪）

仓库里已经准备好：根 `package.json`、`api/index.mjs`（serverless 入口）、`vercel.json`。
大文件走「预签名直传缤纷云」，不受 Vercel 4.5MB 请求体上限影响。

1. <https://vercel.com> 用 GitHub 登录 → **Add New → Project** → 选本仓库 → Import；
2. 在 **Environment Variables** 里加上：

   | 变量 | 值 |
   | --- | --- |
   | `DB_HOST` | `mysql-3818918f-jsjsjsnxjns-6e11.g.aivencloud.com` |
   | `DB_PORT` | `23483` |
   | `DB_USER` | `avnadmin` |
   | `DB_PASSWORD` | 见 `server/.env` |
   | `DB_NAME` | `defaultdb` |
   | `DB_SSL` | `true` |
   | `API_TOKEN` | 见 `server/.env` |
   | `MAX_UPLOAD_MB` | `512` |

3. Deploy → 访问 `https://<项目>.vercel.app/api/health` 验证；
4. 把地址写进 CI。

> 注意：**vercel.app 在国内经常连不上**（可能需要科学上网），这也是主推方案 A 的原因。
> Vercel 的磁盘是只读的，图片视频必须落缤纷云（现在是这个配置）。

---

## 方案 C：Render（需要信用卡）/ Railway（需要额度）

仓库里保留着 `render.yaml` / `railway.json`，账号能用的时候直接部署：

- Render：New → Blueprint → 选本仓库 → 填 `DB_PASSWORD`、`API_TOKEN` → Deploy；
- Railway：New Project → Deploy from GitHub → 加同样的环境变量 → Generate Domain。

---

## 部署完之后（必做）

把新地址写进 CI，让**新构建出来的安装包**默认连云：

```bash
# 国内服务器（方案 A）
gh variable set LUOYUNZONG_API_BASE --body "http://你的公网IP:8080"
# 或者 Vercel / Render（方案 B/C）
gh variable set LUOYUNZONG_API_BASE --body "https://xxx.vercel.app"

gh workflow run build.yml --ref main
```

> 想同时保留本机兜底，可以写两个地址（逗号分隔），App 启动按顺序探测：
> `http://你的公网IP:8080,http://127.0.0.1:8080`

---

## 本地那台电脑上的服务端怎么办

部署好之后，你电脑上的服务端就可以不用了：

```powershell
powershell -File server\start-server.ps1 -Uninstall   # 取消登录自启
```

---

## 两个注意点

1. **对象存储必须有**（PaaS 方案）：PaaS 磁盘是临时的，重启就没了。
   现在配置的就是缤纷云 ✓（子账户 `mymedia` 的读写权限已经打开，实测直传 200）。
2. **免费档休眠**（Render/Vercel 无此问题，Render 有）：Render 免费实例闲置约 15 分钟休眠，
   下次请求等十几秒唤醒；App 会显示「云端暂不可达，稍后自动重试」，不丢数据。

