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

function Test-CommandAvailable {
  param([string] $Command)
  return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Write-InstallStatus {
  param(
    [string] $Name,
    [bool] $Installed,
    [string] $Fix
  )

  if ($Installed) {
    Write-Host "[OK]      $Name" -ForegroundColor Green
  } else {
    Write-Host "[MISSING] $Name - $Fix" -ForegroundColor Yellow
  }
}

function Test-DevSpaceAvailable {
  if (-not (Test-CommandAvailable "npx.cmd")) {
    return $false
  }

  $output = npx.cmd --yes @waishnav/devspace --help 2>&1 | Select-Object -First 1
  return $LASTEXITCODE -eq 0 -and $null -ne $output
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

Write-Step "Installation status"
Write-InstallStatus -Name "Node.js" -Installed (Test-CommandAvailable "node.exe") -Fix "install Node.js LTS"
Write-InstallStatus -Name "npm.cmd" -Installed (Test-CommandAvailable "npm.cmd") -Fix "reopen PowerShell or reinstall Node.js LTS"
Write-InstallStatus -Name "npx.cmd" -Installed (Test-CommandAvailable "npx.cmd") -Fix "reopen PowerShell or reinstall Node.js LTS"
Write-InstallStatus -Name "@waishnav/devspace" -Installed (Test-DevSpaceAvailable) -Fix "run npm.cmd install -g @waishnav/devspace"
Write-InstallStatus -Name "ngrok" -Installed ((Test-CommandAvailable "ngrok.exe") -or (Test-Path $ngrokLocalPath)) -Fix "install ngrok or keep bin\ngrok.exe"
Write-InstallStatus -Name "cloudflared" -Installed ((Test-CommandAvailable "cloudflared.exe") -or (Test-Path $cloudflaredFallbackPath)) -Fix "install cloudflared"

Write-Host ""
Write-Host "Done. Click Check install in DevSpace Control to confirm everything is available." -ForegroundColor Green
Write-Host "Close and reopen DevSpace Control before starting DevSpace if Node.js was newly installed." -ForegroundColor Green
Read-Host "Press Enter to close"
