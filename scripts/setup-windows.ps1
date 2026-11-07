# TownPass Windows dev env (Android emulator, no Android Studio) + MCP config.
# Idempotent: each step checks first and skips if done. Log: scripts/setup-windows.log
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path $PSScriptRoot -Parent
Start-Transcript -Path "$PSScriptRoot\setup-windows.log" -Append | Out-Null

$FlutterVersion = '3.47.6'
$FlutterDir = "$env:USERPROFILE\dev\flutter"
$Sdk = "$env:LOCALAPPDATA\Android\Sdk"
$Abi = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64-v8a' } else { 'x86_64' }
$SdkPackages = @(
  'platform-tools', 'emulator', "system-images/android-36/google_apis/$Abi",
  'platforms/android-36', 'platforms/android-35', 'platforms/android-34',
  'build-tools/36.0.0', 'ndk/29.0.13113456'
)

function Step($m) { Write-Host "`n=== $m" -ForegroundColor Cyan }
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }
function Add-UserPath($dir) {
  $parts = @(([Environment]::GetEnvironmentVariable('Path','User')) -split ';' | Where-Object { $_ })
  if ($parts -notcontains $dir) { [Environment]::SetEnvironmentVariable('Path', (($parts + $dir) -join ';'), 'User') }
}
function Test-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }

# --- 0. Admin-only bits (HypervisorPlatform, winget) ---------------------------
Step '0. Virtualization + system packages'
$hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
$vt = (Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled
# With Hyper-V running, VirtualizationFirmwareEnabled reports False even when VT is on.
if (-not $vt -and -not $hv) { throw 'VT-x/SVM is disabled in BIOS. Enable it and rerun.' }
Refresh-Path
$needWinget = @()
if (-not (Test-Path 'C:\Program Files\Eclipse Adoptium\jdk-17*')) { $needWinget += 'EclipseAdoptium.Temurin.17.JDK' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { $needWinget += 'OpenJS.NodeJS.LTS' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $needWinget += 'Git.Git' }
if ($needWinget -or -not (Test-Admin)) {
  if (Test-Admin) {
    $f = Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform
    if ($f.State -ne 'Enabled') { Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart | Out-Null; Write-Warning 'HypervisorPlatform enabled; reboot may be required.' }
    foreach ($id in $needWinget) { winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements --scope machine }
  } elseif ($needWinget) {
    Write-Host "Elevating for: $($needWinget -join ', ')"
    Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Refresh-Path
  }
}
$Jdk = (Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' | Select-Object -First 1).FullName
if (-not $Jdk) { throw 'JDK 17 not found after install.' }

# --- 1. Flutter ----------------------------------------------------------------
Step "1. Flutter $FlutterVersion"
if (-not (Test-Path "$FlutterDir\bin\flutter.bat")) {
  New-Item -ItemType Directory -Force (Split-Path $FlutterDir) | Out-Null
  git clone --depth 1 -b $FlutterVersion https://github.com/flutter/flutter.git $FlutterDir
}
Add-UserPath "$FlutterDir\bin"

# --- 2. Android SDK ------------------------------------------------------------
Step '2. Android SDK'
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $Sdk, 'User')
[Environment]::SetEnvironmentVariable('JAVA_HOME', $Jdk, 'User')
$env:ANDROID_HOME = $Sdk; $env:JAVA_HOME = $Jdk
foreach ($d in "$Sdk\cmdline-tools\latest\bin", "$Sdk\platform-tools", "$Sdk\emulator") { Add-UserPath $d }
Refresh-Path
if (-not (Test-Path "$Sdk\cmdline-tools\latest\bin\android.exe")) {
  [xml]$x = (Invoke-WebRequest https://dl.google.com/android/repository/repository2-3.xml -UseBasicParsing).Content
  $pkg = $x.SelectNodes("//*[local-name()='remotePackage'][@path='cmdline-tools;latest']") | Select-Object -First 1
  $url = 'https://dl.google.com/android/repository/' + ($pkg.archives.archive | Where-Object { $_.'host-os' -eq 'windows' } | Select-Object -First 1).complete.url
  $zip = "$env:TEMP\cmdline-tools.zip"; $tmp = "$env:TEMP\cmdline-tools-x"
  Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue; Expand-Archive $zip $tmp -Force
  New-Item -ItemType Directory -Force "$Sdk\cmdline-tools" | Out-Null
  Remove-Item -Recurse -Force "$Sdk\cmdline-tools\latest" -ErrorAction SilentlyContinue
  Move-Item "$tmp\cmdline-tools" "$Sdk\cmdline-tools\latest"
}
# New cmdline-tools: sdkmanager.bat forwards to `android sdk` and drops ';' from package
# names (so AGP's auto-download of NDK fails too). Use android.exe with '/' paths instead.
$android = "$Sdk\cmdline-tools\latest\bin\android.exe"
foreach ($p in $SdkPackages) {
  if (-not (Test-Path (Join-Path $Sdk ($p -replace '/', '\')))) { & $android sdk install $p }
}
flutter config --android-sdk $Sdk | Out-Null
flutter config --jdk-dir $Jdk | Out-Null

# --- 3. AVD --------------------------------------------------------------------
Step '3. AVD tp'
if (-not (& "$Sdk\emulator\emulator.exe" -list-avds | Select-String '^tp$')) {
  'no' | & "$Sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd -n tp -k "system-images;android-36;google_apis;$Abi" -d pixel_7
}

# --- 4. Project ----------------------------------------------------------------
Step '4. Project deps + codegen'
Push-Location $Root
flutter pub get
if (-not (Test-Path 'lib\gen\assets.gen.dart')) { dart run build_runner build --delete-conflicting-outputs }
Pop-Location

# --- 6/7. chromedriver + MCP config (needs a booted emulator for WebView version) --
Step '6-7. chromedriver + MCP config'
$adb = "$Sdk\platform-tools\adb.exe"
$cdDir = "$Root\.appium\chromedriver"; New-Item -ItemType Directory -Force $cdDir | Out-Null
$cd = "$cdDir\chromedriver.exe"
if ((& $adb devices) -match 'emulator-5554\s+device') {
  $wv = ((& $adb shell dumpsys package com.google.android.webview | Select-String 'versionName=' | Select-Object -First 1).ToString() -split '=')[1].Trim()
  $major = ($wv -split '\.')[0]
  $have = if (Test-Path $cd) { (& $cd --version) -replace '^ChromeDriver (\d+).*', '$1' } else { '' }
  if ($have -ne $major) {
    $j = Invoke-RestMethod https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json
    $cand = $j.versions | Where-Object { $_.version -like "$major.*" -and $_.downloads.chromedriver }
    $pick = ($cand | Where-Object version -eq $wv | Select-Object -First 1); if (-not $pick) { $pick = $cand | Select-Object -Last 1 }
    $zip = "$env:TEMP\chromedriver.zip"; $x = "$env:TEMP\chromedriver-x"
    Invoke-WebRequest ($pick.downloads.chromedriver | Where-Object platform -eq 'win64').url -OutFile $zip -UseBasicParsing
    Remove-Item -Recurse -Force $x -ErrorAction SilentlyContinue; Expand-Archive $zip $x -Force
    Copy-Item "$x\chromedriver-win64\chromedriver.exe" $cd -Force
  }
} else { Write-Warning 'Emulator not running; skipped chromedriver (start `emulator -avd tp` and rerun).' }

$caps = [ordered]@{ android = [ordered]@{
  platformName = 'Android'; 'appium:automationName' = 'UiAutomator2'; 'appium:udid' = 'emulator-5554'
  'appium:appPackage' = 'com.example.townpass'; 'appium:appActivity' = '.MainActivity'
  'appium:noReset' = $true; 'appium:dontStopAppOnReset' = $true; 'appium:autoLaunch' = $false
  'appium:newCommandTimeout' = 3600; 'appium:chromedriverExecutable' = $cd } }
[IO.File]::WriteAllText("$Root\.appium\capabilities.json", ($caps | ConvertTo-Json -Depth 5))
# Global install + direct node launch: `npx -y appium-mcp@latest` hits the registry on every start and exceeds Claude Code's 30s MCP connect timeout.
$amJs = "$(npm root -g)\appium-mcp\dist\index.js"
if (-not (Test-Path $amJs)) { npm i -g appium-mcp@latest | Out-Null }
# Standalone Appium server: appium-mcp's embedded mode calls UiAutomator2 directly and never proxies to
# chromedriver, so WEBVIEW DOM only works via remoteServerUrl=http://127.0.0.1:4723 (scripts/start-appium.ps1).
Refresh-Path
if (-not (Get-Command appium -ErrorAction SilentlyContinue)) { npm i -g appium@^3 | Out-Null; Refresh-Path }
# appium logs progress to stderr; under EAP=Stop PS 5.1 treats that as a terminating error, so go through cmd.
if (-not ((cmd /c 'appium driver list --installed 2>&1' | Out-String) -match 'uiautomator2@')) { cmd /c 'appium driver install uiautomator2 2>&1' | Out-Null }
$mcp = [ordered]@{ mcpServers = [ordered]@{
  dart = [ordered]@{ type = 'stdio'; command = 'cmd'; args = @('/c', 'dart', 'mcp-server', '--enable', 'flutter_app_lifecycle') }  # launch_app/list_devices are off by default
  'appium-mcp' = [ordered]@{ type = 'stdio'; command = 'node'; args = @($amJs)
    env = [ordered]@{ ANDROID_HOME = $Sdk; JAVA_HOME = $Jdk; CAPABILITIES_CONFIG = "$Root\.appium\capabilities.json"; NO_UI = '1' } } } }  # NO_UI drops the HTML dashboard from every reply
[IO.File]::WriteAllText("$Root\.mcp.json", ($mcp | ConvertTo-Json -Depth 6))
$ex = "$Root\.git\info\exclude"; $c = @(Get-Content $ex -ErrorAction SilentlyContinue)
foreach ($l in '.mcp.json', '.appium/', 'scripts/setup-windows.log') { if ($c -notcontains $l) { Add-Content $ex $l } }

Step 'Done'
flutter doctor
Stop-Transcript | Out-Null
