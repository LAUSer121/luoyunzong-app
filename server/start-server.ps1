# 落云宗云端服务端 · 一键启动（Windows）
#
# 作用：在「服务器配置所在目录」启动 Node 服务端（dotenv 按当前目录读 server/.env）。
# 用法：
#   powershell -File server\start-server.ps1              # 前台运行（关掉窗口就停）
#   powershell -File server\start-server.ps1 -Install     # 注册登录自启（开机后自动后台运行）
#   powershell -File server\start-server.ps1 -Uninstall   # 取消登录自启
#   powershell -File server\start-server.ps1 -Status      # 看是否在跑 + 本机可用地址
#
# 说明：手机在家连的是本机局域网地址（如 http://192.168.1.15:8080），
#       云端数据存在 Aiven MySQL，本机只跑接口进程，不存数据。

[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Status,
  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$serverDir = $PSScriptRoot
$taskName = 'LuoyunzongCloudServer'
$firewallRule = "Luoyunzong Cloud Server (TCP $Port)"

function Get-ServerProcess {
  Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -like '*index.mjs*' -and
      $_.CommandLine -notlike '*runner.js*' -and
      $_.CommandLine -notlike '*subprocess-local*'
    }
}

function Get-LanAddresses {
  Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -ExpandProperty IPAddress
}

# 直连方式做健康检查：不走系统 HTTP 代理（很多人开着 Clash 之类的代理，
# 走代理访问 127.0.0.1 反而会超时）。
function Test-LocalHealth([int]$p, [int]$timeoutMs = 4000) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $connect = $client.BeginConnect('127.0.0.1', $p, $null, $null)
    if (-not $connect.AsyncWaitHandle.WaitOne($timeoutMs)) { return $null }
    $client.EndConnect($connect)
    $stream = $client.GetStream()
    $stream.ReadTimeout = $timeoutMs
    $req = [System.Text.Encoding]::ASCII.GetBytes("GET /api/health HTTP/1.0`r`nHost: 127.0.0.1`r`nConnection: close`r`n`r`n")
    $stream.Write($req, 0, $req.Length)
    $reader = New-Object System.IO.StreamReader($stream)
    $text = $reader.ReadToEnd()
    $idx = $text.IndexOf('{')
    if ($idx -ge 0) { return $text.Substring($idx) }
    return $text
  } catch {
    return $null
  } finally {
    $client.Close()
  }
}

if ($Status) {
  $procs = Get-ServerProcess
  if ($procs) {
    "服务端进程在跑：PID $($procs.ProcessId -join ', ')"
  } else {
    '服务端进程未运行'
  }
  $health = Test-LocalHealth -p $Port
  if ($health) {
    "健康检查：$health"
  } else {
    "健康检查失败：127.0.0.1:$Port 无响应（服务端没起来或端口被占）"
  }
  '本机可用的同步地址（把它配到 CI 变量 LUOYUNZONG_API_BASE 或用手机浏览器验证）：'
  foreach ($ip in Get-LanAddresses) { "  http://${ip}:$Port" }
  return
}

if ($Uninstall) {
  schtasks /Delete /TN $taskName /F 2>$null | Out-Null
  '已取消开机自启。'
  return
}

if ($Install) {
  $script = Join-Path $serverDir 'start-server.ps1'
  # 用当前这个 PowerShell 宿主来跑，避免机器上没装 pwsh 时任务失败
  $hostExe = (Get-Process -Id $PID).Path
  $action = "`"$hostExe`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
  schtasks /Create /TN $taskName /SC ONLOGON /RL LIMITED /TR $action /F | Out-Null
  "已注册登录自启：$taskName"
  "（它会在你登录 Windows 后自动把服务端跑起来；用 -Uninstall 可取消）"

  # 让手机能通过局域网连进来（需要管理员权限；失败也不影响本机使用）
  try {
    if (-not (Get-NetFirewallRule -DisplayName $firewallRule -ErrorAction SilentlyContinue)) {
      New-NetFirewallRule -DisplayName $firewallRule -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $Port -Profile Private | Out-Null
      "已放行防火墙入站端口 $Port（仅专用网络）"
    }
  } catch {
    "提示：防火墙放行失败（$($_.Exception.Message)）。想让手机连上，请用管理员身份再跑一次本脚本。"
  }

  Start-Process $hostExe -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $script
  Start-Sleep -Seconds 3
  & $PSCommandPath -Status
  return
}

if (-not (Test-Path (Join-Path $serverDir '.env'))) {
  throw "缺少 $serverDir\.env —— 请先按 server\.env.example 填好数据库配置。"
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw '未检测到 node，请先安装 Node.js 20+。'
}

Set-Location $serverDir
"落云宗服务端启动中：http://127.0.0.1:$Port"
'（按 Ctrl+C 停止）'
foreach ($ip in Get-LanAddresses) { "  局域网访问：http://${ip}:$Port" }
node index.mjs
