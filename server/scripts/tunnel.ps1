<#
.SYNOPSIS
  在本机启动「落云宗服务端 + Cloudflare 快速隧道」，拿到一个 HTTPS 公网地址。

.DESCRIPTION
  用途：还没买服务器时，先让手机 / 其他电脑连上你本机的服务端（手机端必须 HTTPS，
  所以用 Cloudflare 快速隧道，免域名、免账号、免备案）。

  注意：快速隧道的地址每次重启都会变；要长期稳定请买台小服务器（见 server/README.md）。
  拿到地址后，在本地打包时注入即可让应用默认走云端：
    flutter build apk --release --dart-define=LUOYUNZONG_API_BASE=<地址> --dart-define=LUOYUNZONG_API_TOKEN=<令牌>

.EXAMPLE
  pwsh -File server/scripts/tunnel.ps1
#>
[CmdletBinding()]
param(
  [int]$Port = 8080,
  [string]$ToolsDir = "$PSScriptRoot\..\..\.tooling"
)

$ErrorActionPreference = 'Stop'
$serverDir = Resolve-Path "$PSScriptRoot\.."

function Info([string]$m) { Write-Host "[tunnel] $m" }

# 1) 下载 cloudflared（若没有）
$exe = Join-Path $ToolsDir 'cloudflared.exe'
if (-not (Test-Path $exe)) {
  New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
  $url = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
  Info "下载 cloudflared…（$url）"
  & curl.exe -L --retry 3 -o $exe $url
  if (-not (Test-Path $exe)) { throw 'cloudflared 下载失败，请手动下载后放到 .tooling\cloudflared.exe' }
}

# 2) 启动服务端（若未在运行）
$listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $listening) {
  Info "启动服务端（node index.mjs，端口 $Port）…"
  Start-Process -FilePath 'node' -ArgumentList 'index.mjs' -WorkingDirectory $serverDir -WindowStyle Hidden
  Start-Sleep -Seconds 3
} else {
  Info "端口 $Port 已有服务在跑，跳过启动"
}

# 3) 健康检查
try {
  $health = Invoke-WebRequest "http://127.0.0.1:$Port/api/health" -UseBasicParsing -TimeoutSec 10
  Info "本地服务正常：$($health.Content)"
} catch {
  throw "本地服务未就绪：$($_.Exception.Message)"
}

# 4) 起隧道并抓取公网地址
Info '启动 Cloudflare 快速隧道…'
$log = Join-Path $env:TEMP 'cloudflared-lyz.log'
Remove-Item $log -ErrorAction SilentlyContinue
Start-Process -FilePath $exe -ArgumentList @('tunnel', '--no-autoupdate', '--url', "http://127.0.0.1:$Port") `
  -RedirectStandardError $log -RedirectStandardOutput $log -WindowStyle Hidden

$publicUrl = $null
for ($i = 0; $i -lt 40 -and -not $publicUrl; $i++) {
  Start-Sleep -Milliseconds 700
  if (Test-Path $log) {
    $m = Select-String -Path $log -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($m) { $publicUrl = $m.Matches[0].Value }
  }
}
if (-not $publicUrl) { throw "没能拿到隧道地址，请看日志：$log" }

Info "公网地址：$publicUrl"
Info '用手机/其他电脑打开 App，或本地打包时注入：'
Write-Host "  flutter build apk --release --dart-define=LUOYUNZONG_API_BASE=$publicUrl --dart-define=LUOYUNZONG_API_TOKEN=<API_TOKEN>" -ForegroundColor Cyan

# 5) 顺带验证公网地址可访问
try {
  $public = Invoke-WebRequest "$publicUrl/api/health" -UseBasicParsing -TimeoutSec 20
  Info "公网健康检查通过：$($public.StatusCode) $($public.Content)"
} catch {
  Info "公网健康检查暂未通过（隧道刚起来可能需要几秒）：$($_.Exception.Message)"
}
