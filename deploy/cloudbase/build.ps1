# 组装 CloudBase 云函数目录：把 server/ 的源码拷进函数目录再上传。
#
# 用法（在仓库根目录）：
#   pwsh -File deploy/cloudbase/build.ps1
# 产物：deploy/cloudbase/functions/luoyunzong-api/server/*（可直接 tcb fn deploy）
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fnDir = Join-Path $PSScriptRoot 'functions/luoyunzong-api'
$serverSrc = Join-Path $root 'server'
$serverDst = Join-Path $fnDir 'server'

Write-Host "[cloudbase] 仓库根目录: $root"
if (-not (Test-Path $serverSrc)) { throw "找不到 server 目录：$serverSrc" }

if (Test-Path $serverDst) { Remove-Item $serverDst -Recurse -Force }
New-Item -ItemType Directory -Path $serverDst | Out-Null

# 只拷代码与依赖声明，不拷 .env / uploads / node_modules
Get-ChildItem $serverSrc -File | Where-Object {
  $_.Name -like '*.mjs' -or $_.Name -eq 'package.json' -or $_.Name -eq 'schema.sql'
} | ForEach-Object {
  Copy-Item $_.FullName -Destination $serverDst
  Write-Host "  + server/$($_.Name)"
}
if (Test-Path (Join-Path $serverSrc 'scripts')) {
  Copy-Item (Join-Path $serverSrc 'scripts') -Destination $serverDst -Recurse
}

# 函数目录里不要出现 .env（密钥走云函数环境变量）
$envFile = Join-Path $serverDst '.env'
if (Test-Path $envFile) { Remove-Item $envFile -Force }

Write-Host "[cloudbase] 组装完成：$fnDir"
Write-Host "[cloudbase] 下一步：tcb fn deploy luoyunzong-api -e <环境ID> --force"
