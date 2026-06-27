$ErrorActionPreference = "Continue"

$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ngrokLocalPath = Join-Path $rootDir "bin\ngrok.exe"
$cloudflaredFallbackPath = "C:\Program Files (x86)\cloudflared\cloudflared.exe"

function Write-Step {
  param([string] $Message)
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Install-WingetPackage {
  param(
    [string] $Id,
    [string] $Name
  )

  $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
  if (-not $winget) {
    Write-Warning "winget.exe was not found. Install $Name manually."
    return
  }

  Write-Step "Installing $Name"
  & $winget.Source install --id $Id --exact --accept-package-agreements --accept-source-agreements
}

Write-Host "DevSpace Control requirements installer" -ForegroundColor Green
Write-Host "This installs Node.js, @waishnav/devspace, ngrok, and cloudflared when missing."

if (-not (Get-Command "node.exe" -ErrorAction SilentlyContinue)) {
  Install-WingetPackage -Id "OpenJS.NodeJS.LTS" -Name "Node.js LTS"
} else {
  Write-Step "Node.js already installed"
  node.exe --version
}

if (-not (Get-Command "npm.cmd" -ErrorAction SilentlyContinue)) {
  Write-Warning "npm.cmd was not found. Reopen this window after Node.js installs, then run this script again."
} else {
  Write-Step "Installing @waishnav/devspace"
  npm.cmd install -g @waishnav/devspace
}

if (-not (Get-Command "ngrok.exe" -ErrorAction SilentlyContinue) -and -not (Test-Path $ngrokLocalPath)) {
  Install-WingetPackage -Id "Ngrok.Ngrok" -Name "ngrok"
} else {
  Write-Step "ngrok already installed"
  if (Test-Path $ngrokLocalPath) {
    & $ngrokLocalPath version
  } else {
    ngrok.exe version
  }
}

if (-not (Get-Command "cloudflared.exe" -ErrorAction SilentlyContinue) -and -not (Test-Path $cloudflaredFallbackPath)) {
  Install-WingetPackage -Id "Cloudflare.cloudflared" -Name "cloudflared"
} else {
  Write-Step "cloudflared already installed"
  if (Test-Path $cloudflaredFallbackPath) {
    & $cloudflaredFallbackPath --version
  } else {
    cloudflared.exe --version
  }
}

Write-Step "Verifying DevSpace"
if (Get-Command "npx.cmd" -ErrorAction SilentlyContinue) {
  npx.cmd --yes @waishnav/devspace doctor
} else {
  Write-Warning "npx.cmd was not found. Reopen PowerShell or reinstall Node.js."
}

Write-Host ""
Write-Host "Done. Close and reopen DevSpace Control before starting DevSpace." -ForegroundColor Green
Read-Host "Press Enter to close"
