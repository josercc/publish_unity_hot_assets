# Build Windows release and package as ZIP (+ optional Inno Setup installer).
# Run from repo root in PowerShell:
#   .\scripts\package_windows.ps1
#   .\scripts\package_windows.ps1 -Arch x64

param(
  [ValidateSet("x64", "arm64")]
  [string]$Arch = "x64",
  [string]$BuildName = "",
  [string]$BuildNumber = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$AppName = "UnityHotAssets"
$BinaryName = "publish_unity_hot_assets.exe"
$DistDir = Join-Path $Root "dist"

if (-not $BuildName -or -not $BuildNumber) {
  $raw = (Select-String -Path (Join-Path $Root "pubspec.yaml") -Pattern "^version:\s*(.+)$").Matches[0].Groups[1].Value.Trim()
  if (-not $BuildName) { $BuildName = ($raw -split "\+")[0] }
  if (-not $BuildNumber) {
    if ($raw -match "\+") { $BuildNumber = ($raw -split "\+", 2)[1] } else { $BuildNumber = "1" }
  }
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

function Invoke-Flutter {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
  if ((Get-Command fvm -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $Root ".fvmrc"))) {
    & fvm flutter @FlutterArgs
  } else {
    & flutter @FlutterArgs
  }
  if ($LASTEXITCODE -ne 0) {
    throw "flutter failed with exit code $LASTEXITCODE"
  }
}

Write-Host "==> Building Windows release ($Arch, $BuildName+$BuildNumber)"
$targetPlatform = if ($Arch -eq "arm64") { "windows-arm64" } else { "windows-x64" }

$built = $false
try {
  Invoke-Flutter build windows --release --build-name=$BuildName --build-number=$BuildNumber --target-platform=$targetPlatform
  $built = $true
} catch {
  Write-Host "==> --target-platform not accepted; building host architecture"
}
if (-not $built) {
  Invoke-Flutter build windows --release --build-name=$BuildName --build-number=$BuildNumber
}

$candidates = @(
  (Join-Path $Root "build\windows\$Arch\runner\Release"),
  (Join-Path $Root "build\windows\runner\Release")
)
$ReleaseDir = $null
foreach ($dir in $candidates) {
  if (Test-Path (Join-Path $dir $BinaryName)) {
    $ReleaseDir = $dir
    break
  }
}
if (-not $ReleaseDir) {
  throw "Missing Windows release binary under build/windows"
}

$ZipName = "$AppName-$BuildName-windows-$Arch.zip"
$ZipPath = Join-Path $DistDir $ZipName
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }

Write-Host "==> Creating ZIP: $ZipName"
Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $ZipPath -Force

$isccPath = $null
$isccCmd = Get-Command iscc -ErrorAction SilentlyContinue
if ($isccCmd) {
  $isccPath = $isccCmd.Source
} elseif (Test-Path "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe") {
  $isccPath = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
}

if ($isccPath) {
  Write-Host "==> Creating Inno Setup installer"
  $Iss = Join-Path $Root "packaging\windows\installer.iss"
  & $isccPath $Iss `
    "/DMyAppVersion=$BuildName" `
    "/DMyArch=$Arch" `
    "/DSourceDir=$ReleaseDir" `
    "/DOutputDir=$DistDir"
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE"
  }
} else {
  Write-Host "==> Inno Setup (iscc) not found; ZIP only"
}

Write-Host "==> Windows packages ready under $DistDir"
Get-ChildItem $DistDir -Filter "$AppName-$BuildName-windows-*" | Format-Table Name, Length
