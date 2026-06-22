# DevSpace Control

DevSpace Control is a small Windows launcher for running `@waishnav/devspace` locally and exposing it through an MCP endpoint for tools such as ChatGPT.

> This project is an independent launcher and management UI for `@waishnav/devspace`.
>
> It is not affiliated with or maintained by the authors of `@waishnav/devspace`.
> Users must install and use `@waishnav/devspace` separately.

Double-click `Start-DevSpace-Launcher.bat` to open the DevSpace control UI.

## What the launcher does

- Saves DevSpace config in `%USERPROFILE%\.devspace`
- Generates the Owner password if it does not exist
- Starts and stops `npx @waishnav/devspace serve`
- Starts and stops a public tunnel
- Supports a stable ngrok domain when configured
- Falls back to a temporary Cloudflare quick tunnel when no stable public URL is configured
- Runs `devspace doctor`
- Copies the MCP URL and Owner password
- Opens DevSpace logs, tunnel logs, and the config folder

## Files in this repo

- `Start-DevSpace-Launcher.bat` - double-click launcher for Windows
- `DevSpace-Launcher.ps1` - main PowerShell UI and process manager
- `README.md` - project documentation
- `.gitignore` - keeps local logs, secrets, binaries, and machine-specific files out of git

Generated runtime files such as `*.log`, `*.pid`, tunnel logs, and local binaries are intentionally ignored.

## Default setup

- Allowed root: parent folder of this launcher directory
- Local port: `7676`
- Local MCP URL: `http://127.0.0.1:7676/mcp`

No public tunnel URL is included by default. If you use a stable ngrok or
reverse-proxy hostname, enter your own public base URL in the launcher.

The launcher writes DevSpace configuration to:

```text
%USERPROFILE%\.devspace\config.json
%USERPROFILE%\.devspace\auth.json
```

Do not commit the `.devspace` folder or copied Owner passwords.

## Requirements

- Windows
- PowerShell
- Node.js and npm, so `npx.cmd` is available
- `@waishnav/devspace`, launched through `npx @waishnav/devspace serve`
- Optional: ngrok for a stable public URL
- Optional: cloudflared for a temporary Cloudflare quick tunnel

## ChatGPT / MCP setup

For ChatGPT, use the `Start tunnel` button first.

If the public base URL is set to a stable ngrok hostname:

```text
https://your-static-ngrok-domain.ngrok-free.dev
```

then the launcher starts ngrok with:

```text
ngrok http --domain=your-static-ngrok-domain.ngrok-free.dev 7676
```

This requires:

- ngrok installed and authenticated with `ngrok config add-authtoken <token>`
- the static ngrok dev domain available in your ngrok account
- `bin/ngrok.exe` available locally, if your system ngrok version is too old

If the public base URL is local or empty, the launcher can use a temporary Cloudflare quick tunnel instead. Cloudflare quick tunnel URLs change whenever a new tunnel is created.

Normal browser visits to free ngrok domains may show a warning page. ChatGPT MCP requests use a non-browser user agent and should reach DevSpace directly. If the OAuth approval browser shows the ngrok warning, click through once to continue.

## Recommended start order

1. Click `Start tunnel`.
2. Wait for ngrok or Cloudflare to report the tunnel URL.
3. Click `Start`.
4. Click `Copy MCP URL`.
5. Connect your MCP client.
6. Use the Owner password when asked to approve access.

If you start DevSpace before the tunnel, the launcher restarts DevSpace after detecting the tunnel URL. DevSpace must be restarted whenever the public tunnel hostname changes, because its Host allowlist is built at startup.

## Local-only usage

For local MCP clients, you can use:

```text
http://127.0.0.1:7676/mcp
```

A public tunnel is only needed when the MCP client must reach this machine from outside localhost.

## Troubleshooting

### `npx.cmd was not found`

Install Node.js and npm, then reopen the launcher.

### ngrok does not start

Check that ngrok is installed and authenticated:

```text
ngrok config add-authtoken <token>
```

Also confirm that the configured static domain belongs to your ngrok account.

### Cloudflare tunnel URL is not detected

Open `cloudflared.log`, copy the `https://...trycloudflare.com` URL, and paste it into the Public base URL field if needed.

### MCP connection fails after the tunnel URL changes

Stop and start DevSpace again. The launcher normally handles this automatically, but a manual restart may be needed if the hostname changed outside the launcher.

### Port 7676 is already in use

Stop the other process using the port, or change the Local port field in the launcher before starting DevSpace.

## Before pushing to GitHub

Run:

```text
git status
```

Make sure only safe project files are staged. Do not push:

- `.env` files
- passwords, tokens, or API keys
- `%USERPROFILE%\.devspace\auth.json`
- tunnel credentials
- generated logs
- PID files
- downloaded binaries such as `bin/ngrok.exe`
- zip files and installer downloads

The `.gitignore` is set up to exclude common sensitive and generated files, but still review changes before every push.
