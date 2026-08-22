$ErrorActionPreference = "Stop"

function Assert-NativeSuccess([string] $step) {
  if ($LASTEXITCODE -ne 0) {
    throw "$step failed with exit code $LASTEXITCODE."
  }
}

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
  Assert-NativeSuccess "go test"
  go build -o build/leeef-mcp.exe ./cmd/leeef-mcp
  Assert-NativeSuccess "go build"
} finally {
  Pop-Location
}

flutter config --enable-windows-desktop
Assert-NativeSuccess "flutter config"
flutter pub get
Assert-NativeSuccess "flutter pub get"
flutter analyze
Assert-NativeSuccess "flutter analyze"
flutter test
Assert-NativeSuccess "flutter test"
flutter test integration_test/foliate_reader_test.dart -d windows
Assert-NativeSuccess "Windows integration test"
flutter test integration_test/m1_vertical_slice_test.dart -d windows
Assert-NativeSuccess "Windows M1 vertical slice test"

Write-Host "Leeef Reader Windows verification passed."
