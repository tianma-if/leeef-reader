$ErrorActionPreference = "Stop"

if ([System.Environment]::OSVersion.Platform -ne "Win32NT") {
  throw "This verification script must run on Windows."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Get-Command flutter -ErrorAction Stop | Out-Null
Get-Command go -ErrorAction Stop | Out-Null
Get-Command nuget -ErrorAction Stop | Out-Null

$edgeUpdateRoots = @(
  "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\*",
  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\*"
)
$webView2 = Get-ItemProperty $edgeUpdateRoots -ErrorAction SilentlyContinue |
  Where-Object { $_.name -like "*WebView2*" }
if (-not $webView2) {
  throw "Microsoft Edge WebView2 Runtime is not installed."
}
$webView2 | Select-Object name, pv | Format-Table

Push-Location sidecars/leeef-mcp
try {
  New-Item -ItemType Directory -Force build | Out-Null
  go test ./...
  go build -o build/leeef-mcp.exe ./cmd/leeef-mcp
} finally {
  Pop-Location
}

flutter config --enable-windows-desktop
flutter pub get
flutter analyze
flutter test
flutter test integration_test/foliate_reader_test.dart -d windows

Write-Host "Leeef Reader M0 Windows verification passed."
