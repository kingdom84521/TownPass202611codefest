# Start a standalone Appium server on 127.0.0.1:4723 (detached) if one isn't already up.
# Needed for WEBVIEW DOM access: create appium-mcp sessions with remoteServerUrl=http://127.0.0.1:4723.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\start-appium.ps1
$ErrorActionPreference = 'Stop'
$url = 'http://127.0.0.1:4723/status'
function Test-Up { try { (Invoke-RestMethod $url -TimeoutSec 3).value.ready } catch { $false } }
if (Test-Up) { Write-Host "Appium already running at $url"; exit 0 }

$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = (Get-Item 'C:\Program Files\Eclipse Adoptium\jdk-17*' | Select-Object -First 1).FullName }
$appium = "$(npm root -g)\appium\index.js"
if (-not (Test-Path $appium)) { throw 'appium not installed; run scripts\setup-windows.ps1 first.' }
$log = "$env:TEMP\appium_server.log"
Start-Process node -ArgumentList "`"$appium`"", '--address', '127.0.0.1', '--port', '4723', '--log', "`"$log`"" -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds(60)
while (-not (Test-Up)) {
  if ((Get-Date) -gt $deadline) { throw "Appium did not become ready; see $log" }
  Start-Sleep 2
}
Write-Host "Appium ready at $url (log: $log)"
