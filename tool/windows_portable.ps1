<#
.SYNOPSIS
  把 Flutter Windows 发布目录打成「单文件便携版 EXE」（不产出压缩包）。

.DESCRIPTION
  1) 用 .NET 编译一个自包含的单文件启动器（用户无需安装 .NET）；
  2) 把发布目录压成 zip 载荷；
  3) 把 [标记 + zip] 附加到启动器尾部，得到一个可双击运行的 exe。

  运行时：解压到 <exe 同级>/luoyunzong-app（该目录不可写时退回 %LOCALAPPDATA%），
  数据目录为 <解压目录>/data，因此整个目录可随身携带；仅首次运行解压。

.EXAMPLE
  pwsh -File tool/windows_portable.ps1
#>
[CmdletBinding()]
param(
  [string]$ReleaseDir = 'build/windows/x64/runner/Release',
  [string]$OutFile = 'dist/luoyunzong-portable.exe',
  [string]$AppExe = 'luoyunzong.exe',
  [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Info([string]$m) { Write-Host "[portable] $m" }
function Fail([string]$m) { Write-Error "[portable] $m"; exit 1 }

if (-not (Test-Path $ReleaseDir)) { Fail "未找到发布目录：$ReleaseDir（请先 flutter build windows --release）" }
if (-not (Test-Path (Join-Path $ReleaseDir $AppExe))) { Fail "发布目录缺少 $AppExe" }

$dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
if (-not $dotnet) { Fail '未找到 dotnet SDK，无法编译便携启动器（安装 .NET SDK 8 后重试）' }
Info "dotnet: $dotnet"

$distDir = Split-Path -Parent $OutFile
if ($distDir -and -not (Test-Path $distDir)) { New-Item -ItemType Directory -Force -Path $distDir | Out-Null }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("lyz-portable-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
  # 1) 编译自包含单文件启动器
  $stubDir = Join-Path $work 'stub'
  Info '编译便携启动器（.NET 自包含单文件）…'
  & $dotnet publish (Join-Path $PSScriptRoot 'launcher/Launcher.csproj') `
    -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true `
    -o $stubDir --nologo -v minimal
  if ($LASTEXITCODE -ne 0) { Fail '启动器编译失败' }

  $stub = Join-Path $stubDir 'luoyunzong-portable-stub.exe'
  if (-not (Test-Path $stub)) { Fail "未找到编译产物：$stub" }

  # 2) 打包载荷
  $payload = Join-Path $work 'payload.zip'
  Info '压缩发布目录…'
  Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $payload -Force

  # 3) 拼装：[stub] + [标记] + [zip]
  Info '拼装单文件便携版…'
  $outPath = [System.IO.Path]::GetFullPath($OutFile)
  if (Test-Path $outPath) { Remove-Item $outPath -Force }
  $markerBytes = [System.Text.Encoding]::ASCII.GetBytes('<<<LUOYUNZONG_PAYLOAD_V1>>>')
  $outStream = [System.IO.File]::Create($outPath)
  try {
    $stubBytes = [System.IO.File]::ReadAllBytes($stub)
    $outStream.Write($stubBytes, 0, $stubBytes.Length)
    $outStream.Write($markerBytes, 0, $markerBytes.Length)
    $payloadStream = [System.IO.File]::OpenRead($payload)
    try { $payloadStream.CopyTo($outStream) } finally { $payloadStream.Dispose() }
  } finally {
    $outStream.Dispose()
  }

  if (-not (Test-Path $outPath)) { Fail '拼装失败' }
  Info ("生成：{0}（{1:N1} MB）" -f $outPath, ((Get-Item $outPath).Length / 1MB))

  # 4) 自检：解压到临时目录并检查可执行文件
  if (-not $SkipVerify) {
    $verify = Join-Path $work 'verify'
    Info '验证自解压内容…'
    $env:LUOYUNZONG_DIR = $verify
    & $outPath --extract-only
    if ($LASTEXITCODE -ne 0) { Fail '自解压验证失败（启动器返回非零）' }
    if (-not (Test-Path (Join-Path $verify $AppExe))) { Fail "自解压验证失败：缺少 $AppExe" }
    $count = (Get-ChildItem $verify -Recurse -File).Count
    Info "验证通过：解压出 $count 个文件，入口 $AppExe"
  }
} finally {
  Remove-Item Env:LUOYUNZONG_DIR -ErrorAction SilentlyContinue
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Info '完成。'
