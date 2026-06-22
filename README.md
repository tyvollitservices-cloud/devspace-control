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

## ngrok setup

Use ngrok when you want one stable public URL for ChatGPT instead of a new
temporary Cloudflare URL every time.

1. Create or sign in to an ngrok account:

```text
https://dashboard.ngrok.com
```

2. Add your ngrok authtoken on this machine:

```powershell
ngrok config add-authtoken <your-ngrok-token>
```

3. In the ngrok dashboard, find or create a static dev domain. Free ngrok
accounts usually provide a domain like:

```text
https://your-static-ngrok-domain.ngrok-free.dev
```

4. Put that origin, without `/mcp`, into the launcher Public base URL field:

```text
https://your-static-ngrok-domain.ngrok-free.dev
```

When the public base URL is an ngrok hostname, the launcher starts:

```text
ngrok http --domain=your-static-ngrok-domain.ngrok-free.dev 7676
```

If your installed `ngrok.exe` is too old, download the latest ngrok v3 Windows
binary and place it at:

```text
bin/ngrok.exe
```

The launcher prefers `bin/ngrok.exe` when it exists.

If the public base URL is local or empty, the launcher can use a temporary Cloudflare quick tunnel instead. Cloudflare quick tunnel URLs change whenever a new tunnel is created.

Normal browser visits to free ngrok domains may show a warning page. ChatGPT MCP requests use a non-browser user agent and should reach DevSpace directly. If the OAuth approval browser shows the ngrok warning, click through once to continue.

## ChatGPT app setup

In ChatGPT, create a custom app/connector that points to DevSpace.

Use these fields:

```text
Name:
DevSpace

Description:
Local coding workspace on my machine

Connection:
Server URL

Server URL:
https://your-static-ngrok-domain.ngrok-free.dev/mcp

Authentication:
OAuth
```

Check the warning box:

```text
I understand and want to continue
```

You usually do not need Advanced OAuth settings. DevSpace publishes OAuth
discovery metadata and ChatGPT should detect it automatically.

If ChatGPT asks for manual OAuth values, use the same public base URL:

```text
Auth URL:
https://your-static-ngrok-domain.ngrok-free.dev/authorize

Token URL:
https://your-static-ngrok-domain.ngrok-free.dev/token

Registration URL:
https://your-static-ngrok-domain.ngrok-free.dev/register

Authorization server base:
https://your-static-ngrok-domain.ngrok-free.dev/

Resource:
https://your-static-ngrok-domain.ngrok-free.dev/mcp

Default scopes:
devspace

Base scopes:
devspace

Token endpoint auth method:
none

OIDC:
off
```

Leave OAuth Client ID and OAuth Client Secret blank unless ChatGPT explicitly
requires a user-defined client.

## Recommended start order

1. Click `Start tunnel`.
2. Wait for ngrok or Cloudflare to report the tunnel URL.
3. Click `Start`.
4. Click `Copy MCP URL`.
5. Connect your MCP client.
6. Use the Owner password when asked to approve access.

If you start DevSpace before the tunnel, the launcher restarts DevSpace after detecting the tunnel URL. DevSpace must be restarted whenever the public tunnel hostname changes, because its Host allowlist is built at startup.

## Test from ChatGPT

After the app is connected, ask ChatGPT to use DevSpace:

```text
Use DevSpace to open C:\path\to\your-project and run git status.
```

Expected behavior:

1. ChatGPT calls the DevSpace app.
2. DevSpace may open an OAuth approval page.
3. Paste the Owner password from the launcher.
4. ChatGPT can then open the workspace and run project commands.

Opening the MCP URL directly in a browser is not a valid connection test. This
response is expected:

```json
{"error":"invalid_token","error_description":"Missing Authorization header"}
```

It means DevSpace is reachable but protected by OAuth. To test reachability
without OAuth, open:

```text
https://your-static-ngrok-domain.ngrok-free.dev/healthz
```

Expected response:

```json
{"ok":true,"name":"devspace"}
```

You may also see this when manually opening OAuth or token URLs outside
ChatGPT:

```json
{"error":"invalid_client","error_description":"Client secret is required"}
```

That does not mean the ChatGPT app is broken. It means the request you made
manually did not match the OAuth client authentication method expected for that
endpoint. OAuth has several moving parts:

- ChatGPT discovers DevSpace OAuth metadata from the `.well-known` endpoints.
- ChatGPT registers or configures an OAuth client.
- ChatGPT sends the correct authorization request, PKCE challenge, redirect URI,
  resource value, scope, and token request.
- DevSpace validates that flow and returns a bearer token.
- ChatGPT uses that bearer token in the `Authorization` header when calling
  `/mcp`.

A browser address-bar request skips those protocol steps, so DevSpace can
correctly reject it with `invalid_token` or `invalid_client`. The real test is
to ask ChatGPT to use the DevSpace app and confirm DevSpace tool calls run.

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
