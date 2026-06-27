Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$script:RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:PidFile = Join-Path $script:RootDir "devspace.pid"
$script:TunnelPidFile = Join-Path $script:RootDir "cloudflared.pid"
$script:NgrokPidFile = Join-Path $script:RootDir "ngrok.pid"
$script:LogFile = Join-Path $script:RootDir "devspace.log"
$script:TunnelLogFile = Join-Path $script:RootDir "cloudflared.log"
$script:NgrokLogFile = Join-Path $script:RootDir "ngrok.log"
$script:NgrokErrorLogFile = Join-Path $script:RootDir "ngrok.err.log"
$script:DefaultAllowedRoot = (Resolve-Path (Join-Path $script:RootDir "..")).Path
$script:DefaultStablePublicBaseUrl = "http://127.0.0.1:7676"
$script:ConfigDir = Join-Path $env:USERPROFILE ".devspace"
$script:ConfigPath = Join-Path $script:ConfigDir "config.json"
$script:AuthPath = Join-Path $script:ConfigDir "auth.json"
$script:CloudflaredFallbackPath = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
$script:NgrokLocalPath = Join-Path $script:RootDir "bin\ngrok.exe"
$script:RequirementsInstallerPath = Join-Path $script:RootDir "Install-DevSpace-Requirements.ps1"

function New-OwnerToken {
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Read-JsonFile($Path, $Fallback) {
  if (-not (Test-Path $Path)) {
    return $Fallback
  }

  try {
    return Get-Content -Raw -Path $Path | ConvertFrom-Json
  } catch {
    return $Fallback
  }
}

function Save-DevSpaceConfig {
  param(
    [string] $AllowedRoot,
    [int] $Port,
    [string] $PublicBaseUrl
  )

  New-Item -ItemType Directory -Force -Path $script:ConfigDir | Out-Null

  $config = [ordered]@{
    host = "127.0.0.1"
    port = $Port
    allowedRoots = @($AllowedRoot)
    publicBaseUrl = $PublicBaseUrl.TrimEnd("/")
  }
  [IO.File]::WriteAllText($script:ConfigPath, (($config | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))

  $auth = Read-JsonFile $script:AuthPath ([pscustomobject]@{})
  if (-not $auth.ownerToken -or $auth.ownerToken.Length -lt 16) {
    $auth = [ordered]@{
      ownerToken = New-OwnerToken
    }
    [IO.File]::WriteAllText($script:AuthPath, (($auth | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
  }
}

function Get-DevSpaceProcess {
  if (-not (Test-Path $script:PidFile)) {
    return $null
  }

  $pidText = (Get-Content -Raw -Path $script:PidFile).Trim()
  if (-not $pidText) {
    return $null
  }

  try {
    return Get-Process -Id ([int]$pidText) -ErrorAction Stop
  } catch {
    Remove-Item -Force -Path $script:PidFile -ErrorAction SilentlyContinue
    return $null
  }
}

function Get-CloudflaredCommand {
  $command = Get-Command "cloudflared.exe" -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  if (Test-Path $script:CloudflaredFallbackPath) {
    return $script:CloudflaredFallbackPath
  }

  return $null
}

function Get-NgrokCommand {
  if (Test-Path $script:NgrokLocalPath) {
    return $script:NgrokLocalPath
  }

  $command = Get-Command "ngrok.exe" -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  return $null
}

function Get-ProcessFromPidFile {
  param([string] $Path)

  if (-not (Test-Path $Path)) {
    return $null
  }

  $pidText = (Get-Content -Raw -Path $Path).Trim()
  if (-not $pidText) {
    return $null
  }

  try {
    return Get-Process -Id ([int]$pidText) -ErrorAction Stop
  } catch {
    Remove-Item -Force -Path $Path -ErrorAction SilentlyContinue
    return $null
  }
}

function Get-TunnelProcess {
  $process = Get-ProcessFromPidFile -Path $script:TunnelPidFile
  if ($process) {
    return $process
  }

  $process = Get-ProcessFromPidFile -Path $script:NgrokPidFile
  if ($process) {
    return $process
  }

  try {
    $candidates = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
      Where-Object {
        ($_.Name -eq "cloudflared.exe" -and $_.CommandLine -like "*tunnel --url http://127.0.0.1:*") -or
        ($_.Name -eq "ngrok.exe" -and $_.CommandLine -like "*http*7676*")
      } |
      Select-Object -First 1
    if ($candidates) {
      return Get-Process -Id $candidates.ProcessId -ErrorAction SilentlyContinue
    }
  } catch {
    return $null
  }

  return $null
}

function Get-PortOwnerProcesses {
  param([int] $Port)

  try {
    $ownerIds = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty OwningProcess -Unique
    return @($ownerIds | ForEach-Object {
      Get-Process -Id $_ -ErrorAction SilentlyContinue
    })
  } catch {
    return @()
  }
}

function Test-DevSpaceRunning {
  if ($null -ne (Get-DevSpaceProcess)) {
    return $true
  }

  return @(Get-PortOwnerProcesses -Port ([int]$portBox.Value)).Count -gt 0
}

function Test-TunnelRunning {
  return $null -ne (Get-TunnelProcess)
}

function Get-OwnerPassword {
  $auth = Read-JsonFile $script:AuthPath ([pscustomobject]@{})
  return $auth.ownerToken
}

function Append-Status($Text) {
  $timestamp = Get-Date -Format "HH:mm:ss"
  $statusBox.AppendText("[$timestamp] $Text`r`n")
}

function Get-SetupStepsText {
  return @"
Install requirements:

1. Click Install reqs, or run these commands on the remote PC:
   winget install --id OpenJS.NodeJS.LTS
   npm.cmd install -g @waishnav/devspace
   winget install --id Ngrok.Ngrok
   winget install --id Cloudflare.cloudflared

2. If PowerShell blocks npm or npx, use npm.cmd and npx.cmd:
   npm.cmd install -g @waishnav/devspace
   npx.cmd --yes @waishnav/devspace doctor

DevSpace Control setup:

1. Set Allowed project root to the folder ChatGPT may access.
2. Keep Local port as 7676 unless that port is already used.
3. Put the ChatGPT public fallback/origin URL in Public base URL.
   Use the base URL only, without /mcp.
   Example: https://your-domain.ngrok-free.dev
4. Click Save setup.
5. Click Start tunnel.
6. Click Start.
7. Click Copy MCP URL.

ChatGPT setup:

1. Use ChatGPT web on the account/workspace that supports custom apps.
2. Set Server URL to the copied MCP URL:
   https://your-domain.ngrok-free.dev/mcp
3. Use OAuth when the setup screen supports it.
4. Use the Owner password from this window when asked to approve access.

Notes:

- For a stable ChatGPT URL, use ngrok with an https://...ngrok-free.dev domain.
- For a temporary Cloudflare URL, leave Public base URL local or empty before Start tunnel.
- If the tunnel URL changes, restart DevSpace so the new host is allowed.
"@
}

function Show-SetupSteps {
  $setupForm = New-Object Windows.Forms.Form
  $setupForm.Text = "DevSpace Setup Steps"
  $setupForm.Width = 780
  $setupForm.Height = 620
  $setupForm.StartPosition = "CenterParent"

  $box = New-Object Windows.Forms.TextBox
  $box.Multiline = $true
  $box.ReadOnly = $true
  $box.ScrollBars = "Both"
  $box.Dock = "Fill"
  $box.Font = New-Object Drawing.Font("Consolas", 10)
  $box.Text = Get-SetupStepsText
  $setupForm.Controls.Add($box)
  $setupForm.ShowDialog($form) | Out-Null
}

function Install-Requirements {
  if (-not (Test-Path $script:RequirementsInstallerPath)) {
    [Windows.Forms.MessageBox]::Show("Install-DevSpace-Requirements.ps1 was not found.", "DevSpace Launcher")
    return
  }

  Append-Status "Opening requirements installer..."
  Start-Process powershell.exe -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$script:RequirementsInstallerPath`""
  )
}

function Refresh-Ui {
  $running = Test-DevSpaceRunning
  $tunnelRunning = Test-TunnelRunning
  $startButton.Enabled = -not $running
  $stopButton.Enabled = $running
  $startTunnelButton.Enabled = -not $tunnelRunning
  $stopTunnelButton.Enabled = $tunnelRunning
  $statusLabel.Text = if ($running) { "Running" } else { "Stopped" }
  $statusLabel.ForeColor = if ($running) { [Drawing.Color]::ForestGreen } else { [Drawing.Color]::Firebrick }
  $tunnelStatusLabel.Text = if ($tunnelRunning) { "Tunnel running" } else { "Tunnel stopped" }
  $tunnelStatusLabel.ForeColor = if ($tunnelRunning) { [Drawing.Color]::ForestGreen } else { [Drawing.Color]::Firebrick }

  $publicBase = $publicUrlBox.Text.Trim().TrimEnd("/")
  if ($publicBase) {
    $mcpUrlBox.Text = "$publicBase/mcp"
  }

  $owner = Get-OwnerPassword
  $passwordBox.Text = if ($owner) { $owner } else { "" }
}

function Find-TunnelUrl {
  if (-not (Test-Path $script:TunnelLogFile)) {
    return $null
  }

  $text = Get-Content -Raw -Path $script:TunnelLogFile
  $marker = "--- cloudflared tunnel start "
  $lastMarker = $text.LastIndexOf($marker)
  if ($lastMarker -ge 0) {
    $text = $text.Substring($lastMarker)
  }

  $matches = [regex]::Matches($text, "https://[a-zA-Z0-9-]+\.trycloudflare\.com")
  if ($matches.Count -gt 0) {
    return $matches[$matches.Count - 1].Value
  }

  return $null
}

function Start-DevSpace {
  Save-DevSpaceConfig -AllowedRoot $allowedRootBox.Text.Trim() -Port ([int]$portBox.Value) -PublicBaseUrl $publicUrlBox.Text.Trim()

  if (Test-DevSpaceRunning) {
    Append-Status "DevSpace is already running."
    Refresh-Ui
    return
  }

  $npx = (Get-Command "npx.cmd" -ErrorAction SilentlyContinue)
  if (-not $npx) {
    [Windows.Forms.MessageBox]::Show("npx.cmd was not found. Install Node.js/npm first.", "DevSpace Launcher")
    return
  }

  Add-Content -Path $script:LogFile -Value "`r`n--- DevSpace start $(Get-Date -Format s) ---"

  $process = New-Object Diagnostics.Process
  $process.StartInfo.FileName = $npx.Source
  $process.StartInfo.Arguments = "--yes @waishnav/devspace serve"
  $process.StartInfo.WorkingDirectory = $script:DefaultAllowedRoot
  $process.StartInfo.UseShellExecute = $false
  $process.StartInfo.CreateNoWindow = $true
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError = $true
  $process.StartInfo.EnvironmentVariables["DEVSPACE_LOG_FORMAT"] = "pretty"
  $process.StartInfo.EnvironmentVariables["DEVSPACE_LOG_LEVEL"] = "info"
  $process.StartInfo.EnvironmentVariables["DEVSPACE_TRUST_PROXY"] = "1"
  $process.Start() | Out-Null

  Set-Content -Path $script:PidFile -Value $process.Id
  Append-Status "Started DevSpace. PID: $($process.Id)"
  Append-Status "MCP URL: $($mcpUrlBox.Text)"
  Append-Status "Logs: $script:LogFile"

  Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -MessageData $script:LogFile -Action {
    if ($EventArgs.Data) {
      Add-Content -Path $Event.MessageData -Value $EventArgs.Data
    }
  } | Out-Null
  Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -MessageData $script:LogFile -Action {
    if ($EventArgs.Data) {
      Add-Content -Path $Event.MessageData -Value $EventArgs.Data
    }
  } | Out-Null
  $process.BeginOutputReadLine()
  $process.BeginErrorReadLine()

  Start-Sleep -Milliseconds 500
  Refresh-Ui
}

function Restart-DevSpace {
  Stop-DevSpace
  Start-Sleep -Seconds 1
  Start-DevSpace
}

function Stop-DevSpace {
  $process = Get-DevSpaceProcess
  $portOwners = @(Get-PortOwnerProcesses -Port ([int]$portBox.Value))

  if (-not $process -and $portOwners.Count -eq 0) {
    Append-Status "DevSpace is not running."
    Refresh-Ui
    return
  }

  if ($process) {
    try {
      Stop-Process -Id $process.Id -Force
      Append-Status "Stopped DevSpace wrapper. PID: $($process.Id)"
    } catch {
      Append-Status "Wrapper stop failed: $($_.Exception.Message)"
    }
  }

  foreach ($owner in $portOwners) {
    try {
      Stop-Process -Id $owner.Id -Force
      Append-Status "Stopped listener on port $($portBox.Value). PID: $($owner.Id)"
    } catch {
      Append-Status "Port listener stop failed: $($_.Exception.Message)"
    }
  }

  Remove-Item -Force -Path $script:PidFile -ErrorAction SilentlyContinue
  Refresh-Ui
}

function Start-Tunnel {
  $publicBase = $publicUrlBox.Text.Trim().TrimEnd("/")
  $useNgrok = $publicBase -match "^https://(.+)$" -and $publicBase -notmatch "\.trycloudflare\.com$" -and $publicBase -notmatch "^https://127\.0\.0\.1" -and $publicBase -notmatch "^https://localhost"
  if ($useNgrok) {
    Start-NgrokTunnel -PublicBaseUrl $publicBase
    return
  }

  $cloudflared = Get-CloudflaredCommand
  if (-not $cloudflared) {
    [Windows.Forms.MessageBox]::Show("cloudflared.exe was not found. Install Cloudflare cloudflared first.", "DevSpace Launcher")
    return
  }

  if (Test-TunnelRunning) {
    Append-Status "Cloudflare tunnel is already running."
    Refresh-Ui
    return
  }

  Set-Content -Path $script:TunnelLogFile -Value "--- cloudflared tunnel start $(Get-Date -Format s) ---"

  $process = New-Object Diagnostics.Process
  $process.StartInfo.FileName = $cloudflared
  $process.StartInfo.Arguments = "tunnel --url http://127.0.0.1:$($portBox.Value)"
  $process.StartInfo.WorkingDirectory = $script:RootDir
  $process.StartInfo.UseShellExecute = $false
  $process.StartInfo.CreateNoWindow = $true
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError = $true
  $process.Start() | Out-Null

  Set-Content -Path $script:TunnelPidFile -Value $process.Id
  Append-Status "Started Cloudflare tunnel. PID: $($process.Id)"

  Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -MessageData $script:TunnelLogFile -Action {
    if ($EventArgs.Data) {
      Add-Content -Path $Event.MessageData -Value $EventArgs.Data
    }
  } | Out-Null
  Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -MessageData $script:TunnelLogFile -Action {
    if ($EventArgs.Data) {
      Add-Content -Path $Event.MessageData -Value $EventArgs.Data
    }
  } | Out-Null
  $process.BeginOutputReadLine()
  $process.BeginErrorReadLine()

  Start-Sleep -Seconds 6
  $url = Find-TunnelUrl
  if ($url) {
    $publicUrlBox.Text = $url
    Save-DevSpaceConfig -AllowedRoot $allowedRootBox.Text.Trim() -Port ([int]$portBox.Value) -PublicBaseUrl $publicUrlBox.Text.Trim()
    Append-Status "Tunnel URL detected: $url"
    Append-Status "MCP URL: $url/mcp"
    if (Test-DevSpaceRunning) {
      Append-Status "Restarting DevSpace so the new tunnel host is allowed."
      Restart-DevSpace
    }
  } else {
    Append-Status "Tunnel started. URL not detected yet; open cloudflared.log and paste the trycloudflare URL if needed."
  }

  Refresh-Ui
}

function Start-NgrokTunnel {
  param([string] $PublicBaseUrl)

  $ngrok = Get-NgrokCommand
  if (-not $ngrok) {
    [Windows.Forms.MessageBox]::Show("ngrok.exe was not found. Install ngrok first.", "DevSpace Launcher")
    return
  }

  if (Test-TunnelRunning) {
    Append-Status "A tunnel is already running."
    Refresh-Ui
    return
  }

  $domain = ([Uri]$PublicBaseUrl).Host
  Save-DevSpaceConfig -AllowedRoot $allowedRootBox.Text.Trim() -Port ([int]$portBox.Value) -PublicBaseUrl $PublicBaseUrl
  Set-Content -Path $script:NgrokLogFile -Value "--- ngrok tunnel start $(Get-Date -Format s) ---"

  $process = New-Object Diagnostics.Process
  $process.StartInfo.FileName = $ngrok
  $process.StartInfo.Arguments = "http --domain=$domain $($portBox.Value)"
  $process.StartInfo.WorkingDirectory = $script:RootDir
  $process.StartInfo.UseShellExecute = $false
  $process.StartInfo.CreateNoWindow = $true
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError = $true
  $process.Start() | Out-Null

  Set-Content -Path $script:NgrokPidFile -Value $process.Id
  Append-Status "Started ngrok tunnel for $domain. PID: $($process.Id)"
  Append-Status "MCP URL: $PublicBaseUrl/mcp"

  Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -MessageData $script:NgrokLogFile -Action {
    if ($EventArgs.Data) {
      Add-Content -Path $Event.MessageData -Value $EventArgs.Data
    }
  } | Out-Null
  Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -MessageData $script:NgrokLogFile -Action {
    if ($EventArgs.Data) {
      Add-Content -Path $Event.MessageData -Value $EventArgs.Data
    }
  } | Out-Null
  $process.BeginOutputReadLine()
  $process.BeginErrorReadLine()

  Start-Sleep -Seconds 3
  if (Test-DevSpaceRunning) {
    Append-Status "Restarting DevSpace so the ngrok host is allowed."
    Restart-DevSpace
  }

  Refresh-Ui
}

function Stop-Tunnel {
  $process = Get-TunnelProcess
  if (-not $process) {
    Append-Status "Cloudflare tunnel is not running."
    Refresh-Ui
    return
  }

  try {
    Stop-Process -Id $process.Id -Force
    Append-Status "Stopped Cloudflare tunnel. PID: $($process.Id)"
  } catch {
    Append-Status "Tunnel stop failed: $($_.Exception.Message)"
  }

  Remove-Item -Force -Path $script:TunnelPidFile -ErrorAction SilentlyContinue
  Remove-Item -Force -Path $script:NgrokPidFile -ErrorAction SilentlyContinue
  Refresh-Ui
}

function Run-Doctor {
  Save-DevSpaceConfig -AllowedRoot $allowedRootBox.Text.Trim() -Port ([int]$portBox.Value) -PublicBaseUrl $publicUrlBox.Text.Trim()
  Append-Status "Running devspace doctor..."

  $output = & npx.cmd --yes @waishnav/devspace doctor 2>&1
  $output | Add-Content -Path $script:LogFile

  $doctorForm = New-Object Windows.Forms.Form
  $doctorForm.Text = "DevSpace Doctor"
  $doctorForm.Width = 820
  $doctorForm.Height = 520
  $doctorForm.StartPosition = "CenterParent"

  $box = New-Object Windows.Forms.TextBox
  $box.Multiline = $true
  $box.ReadOnly = $true
  $box.ScrollBars = "Both"
  $box.Dock = "Fill"
  $box.Font = New-Object Drawing.Font("Consolas", 10)
  $box.Text = ($output -join "`r`n")
  $doctorForm.Controls.Add($box)
  $doctorForm.ShowDialog($form) | Out-Null
}

$existingConfig = Read-JsonFile $script:ConfigPath ([pscustomobject]@{})
$existingAuth = Read-JsonFile $script:AuthPath ([pscustomobject]@{})
$existingPublicBaseUrl = if ($existingConfig.publicBaseUrl) { [string]$existingConfig.publicBaseUrl } else { $script:DefaultStablePublicBaseUrl }
if ($existingPublicBaseUrl -match "^https://[a-zA-Z0-9-]+\.trycloudflare\.com/?$" -and -not (Get-TunnelProcess)) {
  $existingPublicBaseUrl = $script:DefaultStablePublicBaseUrl
}

$form = New-Object Windows.Forms.Form
$form.Text = "DevSpace Control"
$form.Width = 760
$form.Height = 610
$form.StartPosition = "CenterScreen"
$form.Font = New-Object Drawing.Font("Segoe UI", 10)

$title = New-Object Windows.Forms.Label
$title.Text = "DevSpace Control"
$title.Font = New-Object Drawing.Font("Segoe UI", 16, [Drawing.FontStyle]::Bold)
$title.Location = New-Object Drawing.Point(18, 16)
$title.Size = New-Object Drawing.Size(320, 34)
$form.Controls.Add($title)

$statusLabel = New-Object Windows.Forms.Label
$statusLabel.Text = "Stopped"
$statusLabel.Font = New-Object Drawing.Font("Segoe UI", 12, [Drawing.FontStyle]::Bold)
$statusLabel.Location = New-Object Drawing.Point(620, 22)
$statusLabel.Size = New-Object Drawing.Size(100, 28)
$form.Controls.Add($statusLabel)

$tunnelStatusLabel = New-Object Windows.Forms.Label
$tunnelStatusLabel.Text = "Tunnel stopped"
$tunnelStatusLabel.Font = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
$tunnelStatusLabel.Location = New-Object Drawing.Point(592, 50)
$tunnelStatusLabel.Size = New-Object Drawing.Size(130, 24)
$form.Controls.Add($tunnelStatusLabel)

$allowedRootLabel = New-Object Windows.Forms.Label
$allowedRootLabel.Text = "Allowed project root"
$allowedRootLabel.Location = New-Object Drawing.Point(22, 70)
$allowedRootLabel.Size = New-Object Drawing.Size(180, 24)
$form.Controls.Add($allowedRootLabel)

$allowedRootBox = New-Object Windows.Forms.TextBox
$allowedRootBox.Location = New-Object Drawing.Point(210, 68)
$allowedRootBox.Size = New-Object Drawing.Size(500, 28)
$allowedRootBox.Text = if ($existingConfig.allowedRoots -and $existingConfig.allowedRoots.Count -gt 0) { $existingConfig.allowedRoots[0] } else { $script:DefaultAllowedRoot }
$form.Controls.Add($allowedRootBox)

$portLabel = New-Object Windows.Forms.Label
$portLabel.Text = "Local port"
$portLabel.Location = New-Object Drawing.Point(22, 110)
$portLabel.Size = New-Object Drawing.Size(180, 24)
$form.Controls.Add($portLabel)

$portBox = New-Object Windows.Forms.NumericUpDown
$portBox.Location = New-Object Drawing.Point(210, 108)
$portBox.Size = New-Object Drawing.Size(120, 28)
$portBox.Minimum = 1
$portBox.Maximum = 65535
$portBox.Value = if ($existingConfig.port) { [int]$existingConfig.port } else { 7676 }
$form.Controls.Add($portBox)

$publicUrlLabel = New-Object Windows.Forms.Label
$publicUrlLabel.Text = "Public base URL"
$publicUrlLabel.Location = New-Object Drawing.Point(22, 150)
$publicUrlLabel.Size = New-Object Drawing.Size(180, 24)
$form.Controls.Add($publicUrlLabel)

$publicUrlBox = New-Object Windows.Forms.TextBox
$publicUrlBox.Location = New-Object Drawing.Point(210, 148)
$publicUrlBox.Size = New-Object Drawing.Size(500, 28)
$publicUrlBox.Text = $existingPublicBaseUrl
$form.Controls.Add($publicUrlBox)

$mcpUrlLabel = New-Object Windows.Forms.Label
$mcpUrlLabel.Text = "MCP URL"
$mcpUrlLabel.Location = New-Object Drawing.Point(22, 190)
$mcpUrlLabel.Size = New-Object Drawing.Size(180, 24)
$form.Controls.Add($mcpUrlLabel)

$mcpUrlBox = New-Object Windows.Forms.TextBox
$mcpUrlBox.Location = New-Object Drawing.Point(210, 188)
$mcpUrlBox.Size = New-Object Drawing.Size(500, 28)
$mcpUrlBox.ReadOnly = $true
$form.Controls.Add($mcpUrlBox)

$passwordLabel = New-Object Windows.Forms.Label
$passwordLabel.Text = "Owner password"
$passwordLabel.Location = New-Object Drawing.Point(22, 230)
$passwordLabel.Size = New-Object Drawing.Size(180, 24)
$form.Controls.Add($passwordLabel)

$passwordBox = New-Object Windows.Forms.TextBox
$passwordBox.Location = New-Object Drawing.Point(210, 228)
$passwordBox.Size = New-Object Drawing.Size(500, 28)
$passwordBox.ReadOnly = $true
$passwordBox.Text = if ($existingAuth.ownerToken) { $existingAuth.ownerToken } else { "" }
$form.Controls.Add($passwordBox)

$saveButton = New-Object Windows.Forms.Button
$saveButton.Text = "Save setup"
$saveButton.Location = New-Object Drawing.Point(22, 280)
$saveButton.Size = New-Object Drawing.Size(110, 34)
$saveButton.Add_Click({
  Save-DevSpaceConfig -AllowedRoot $allowedRootBox.Text.Trim() -Port ([int]$portBox.Value) -PublicBaseUrl $publicUrlBox.Text.Trim()
  Append-Status "Saved DevSpace config."
  Refresh-Ui
})
$form.Controls.Add($saveButton)

$startButton = New-Object Windows.Forms.Button
$startButton.Text = "Start"
$startButton.Location = New-Object Drawing.Point(146, 280)
$startButton.Size = New-Object Drawing.Size(90, 34)
$startButton.Add_Click({ Start-DevSpace })
$form.Controls.Add($startButton)

$stopButton = New-Object Windows.Forms.Button
$stopButton.Text = "Stop"
$stopButton.Location = New-Object Drawing.Point(250, 280)
$stopButton.Size = New-Object Drawing.Size(90, 34)
$stopButton.Add_Click({ Stop-DevSpace })
$form.Controls.Add($stopButton)

$doctorButton = New-Object Windows.Forms.Button
$doctorButton.Text = "Doctor"
$doctorButton.Location = New-Object Drawing.Point(354, 280)
$doctorButton.Size = New-Object Drawing.Size(90, 34)
$doctorButton.Add_Click({ Run-Doctor })
$form.Controls.Add($doctorButton)

$startTunnelButton = New-Object Windows.Forms.Button
$startTunnelButton.Text = "Start tunnel"
$startTunnelButton.Location = New-Object Drawing.Point(458, 280)
$startTunnelButton.Size = New-Object Drawing.Size(120, 34)
$startTunnelButton.Add_Click({ Start-Tunnel })
$form.Controls.Add($startTunnelButton)

$stopTunnelButton = New-Object Windows.Forms.Button
$stopTunnelButton.Text = "Stop tunnel"
$stopTunnelButton.Location = New-Object Drawing.Point(592, 280)
$stopTunnelButton.Size = New-Object Drawing.Size(120, 34)
$stopTunnelButton.Add_Click({ Stop-Tunnel })
$form.Controls.Add($stopTunnelButton)

$copyUrlButton = New-Object Windows.Forms.Button
$copyUrlButton.Text = "Copy MCP URL"
$copyUrlButton.Location = New-Object Drawing.Point(458, 326)
$copyUrlButton.Size = New-Object Drawing.Size(120, 34)
$copyUrlButton.Add_Click({
  [Windows.Forms.Clipboard]::SetText($mcpUrlBox.Text)
  Append-Status "Copied MCP URL."
})
$form.Controls.Add($copyUrlButton)

$copyPassButton = New-Object Windows.Forms.Button
$copyPassButton.Text = "Copy password"
$copyPassButton.Location = New-Object Drawing.Point(592, 326)
$copyPassButton.Size = New-Object Drawing.Size(120, 34)
$copyPassButton.Add_Click({
  if ($passwordBox.Text) {
    [Windows.Forms.Clipboard]::SetText($passwordBox.Text)
    Append-Status "Copied Owner password."
  }
})
$form.Controls.Add($copyPassButton)

$openConfigButton = New-Object Windows.Forms.Button
$openConfigButton.Text = "Open config folder"
$openConfigButton.Location = New-Object Drawing.Point(22, 326)
$openConfigButton.Size = New-Object Drawing.Size(150, 34)
$openConfigButton.Add_Click({
  New-Item -ItemType Directory -Force -Path $script:ConfigDir | Out-Null
  Start-Process explorer.exe $script:ConfigDir
})
$form.Controls.Add($openConfigButton)

$openLogButton = New-Object Windows.Forms.Button
$openLogButton.Text = "DevSpace log"
$openLogButton.Location = New-Object Drawing.Point(186, 326)
$openLogButton.Size = New-Object Drawing.Size(110, 34)
$openLogButton.Add_Click({
  if (-not (Test-Path $script:LogFile)) {
    New-Item -ItemType File -Force -Path $script:LogFile | Out-Null
  }
  Start-Process notepad.exe $script:LogFile
})
$form.Controls.Add($openLogButton)

$openTunnelLogButton = New-Object Windows.Forms.Button
$openTunnelLogButton.Text = "Tunnel log"
$openTunnelLogButton.Location = New-Object Drawing.Point(310, 326)
$openTunnelLogButton.Size = New-Object Drawing.Size(100, 34)
$openTunnelLogButton.Add_Click({
  $path = if (Test-Path $script:NgrokLogFile) { $script:NgrokLogFile } else { $script:TunnelLogFile }
  if (-not (Test-Path $path)) {
    New-Item -ItemType File -Force -Path $path | Out-Null
  }
  Start-Process notepad.exe $path
})
$form.Controls.Add($openTunnelLogButton)

$installReqsButton = New-Object Windows.Forms.Button
$installReqsButton.Text = "Install reqs"
$installReqsButton.Location = New-Object Drawing.Point(22, 372)
$installReqsButton.Size = New-Object Drawing.Size(110, 34)
$installReqsButton.Add_Click({ Install-Requirements })
$form.Controls.Add($installReqsButton)

$setupStepsButton = New-Object Windows.Forms.Button
$setupStepsButton.Text = "Setup steps"
$setupStepsButton.Location = New-Object Drawing.Point(146, 372)
$setupStepsButton.Size = New-Object Drawing.Size(110, 34)
$setupStepsButton.Add_Click({ Show-SetupSteps })
$form.Controls.Add($setupStepsButton)

$statusBox = New-Object Windows.Forms.TextBox
$statusBox.Location = New-Object Drawing.Point(22, 426)
$statusBox.Size = New-Object Drawing.Size(690, 120)
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = "Vertical"
$statusBox.Font = New-Object Drawing.Font("Consolas", 9)
$form.Controls.Add($statusBox)

$publicUrlBox.Add_TextChanged({ Refresh-Ui })
$portBox.Add_ValueChanged({
  if ($publicUrlBox.Text -match "^http://127\.0\.0\.1:\d+$") {
    $publicUrlBox.Text = "http://127.0.0.1:$($portBox.Value)"
  }
  Refresh-Ui
})

Refresh-Ui
Append-Status "Ready. Use a public HTTPS tunnel URL for ChatGPT; local URL is fine for local MCP clients."

$form.Add_FormClosing({
  if (Test-DevSpaceRunning) {
    $choice = [Windows.Forms.MessageBox]::Show(
      "DevSpace is still running. Stop it before closing?",
      "DevSpace Control",
      [Windows.Forms.MessageBoxButtons]::YesNoCancel,
      [Windows.Forms.MessageBoxIcon]::Question
    )
    if ($choice -eq [Windows.Forms.DialogResult]::Cancel) {
      $_.Cancel = $true
      return
    }
    if ($choice -eq [Windows.Forms.DialogResult]::Yes) {
      Stop-DevSpace
    }
  }
  if (Test-TunnelRunning) {
    Stop-Tunnel
  }
})

[void]$form.ShowDialog()
