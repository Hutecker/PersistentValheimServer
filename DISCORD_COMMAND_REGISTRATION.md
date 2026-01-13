# Discord Command Registration Guide

This guide helps you register and verify Discord slash commands for your Valheim server bot.

## Quick Start

### Option 1: Automated Setup (Recommended)

Use the comprehensive setup script that handles everything:

```powershell
.\scripts\setup-discord-bot.ps1 `
  -ApplicationId "1460365045132300308" `
  -BotToken "YOUR_BOT_TOKEN" `
  -GuildId "YOUR_SERVER_ID" `
  -FunctionAppUrl "https://valheim-func-vmaygfpvthejm.azurewebsites.net"
```

**Get your Server ID (Guild ID):**
1. Enable Developer Mode in Discord: Settings → Advanced → Developer Mode (ON)
2. Right-click your Discord server name → Copy Server ID

### Option 2: Manual Registration

1. **Register Commands:**
   ```powershell
   .\scripts\register-discord-commands.ps1 `
     -ApplicationId "1460365045132300308" `
     -BotToken "YOUR_BOT_TOKEN" `
     -FunctionAppUrl "https://valheim-func-vmaygfpvthejm.azurewebsites.net" `
     -GuildId "YOUR_SERVER_ID"  # Optional, but recommended for testing
   ```

2. **Verify Commands:**
   ```powershell
   .\scripts\verify-discord-commands.ps1 `
     -ApplicationId "1460365045132300308" `
     -BotToken "YOUR_BOT_TOKEN" `
     -GuildId "YOUR_SERVER_ID"  # Optional
   ```

## Prerequisites

### 1. Bot Must Be Added to Your Server

Before registering commands, add the bot to your Discord server:

1. Go to: https://discord.com/developers/applications/1460365045132300308/oauth2/url-generator
2. Select **Scopes**:
   - ✅ `bot`
   - ✅ `applications.commands`
3. Select **Bot Permissions** (optional but recommended):
   - Send Messages
   - Use Slash Commands
4. Copy the generated URL and open it in a browser
5. Select your Discord server and click "Authorize"

### 2. Get Required Values

- **Application ID**: `1460365045132300308` (from Discord Developer Portal)
- **Bot Token**: Get from https://discord.com/developers/applications/1460365045132300308/bot
- **Server ID (Guild ID)**: Right-click server → Copy Server ID (requires Developer Mode)
- **Function App URL**: `https://valheim-func-vmaygfpvthejm.azurewebsites.net`

## Troubleshooting

### Error 403: Forbidden

**Cause**: Bot not added to server or missing scopes

**Fix**:
1. Add bot to server using OAuth2 URL Generator
2. Make sure both `bot` and `applications.commands` scopes are selected
3. Try registering to a specific guild (server) first instead of globally

### Error 401: Unauthorized

**Cause**: Invalid or expired bot token

**Fix**:
1. Go to https://discord.com/developers/applications/1460365045132300308/bot
2. Click "Reset Token" or "Copy" to get a new token
3. Make sure token doesn't have "Bot " prefix (script adds it automatically)

### Error 40333: Internal Network Error

**Cause**: Bot configuration issue or Discord API temporary issue

**Fix**:
1. Verify bot is added to your server
2. Wait a few minutes and try again (may be rate limiting)
3. Try registering to a specific guild instead of globally

### Commands Not Appearing in Discord

**For Guild-Specific Commands** (with `-GuildId`):
- Should appear immediately
- Make sure bot is in the server
- Try typing `/valheim` in a channel

**For Global Commands** (without `-GuildId`):
- Can take up to 1 hour to propagate
- Use guild-specific registration for testing
- Verify bot is in the server

## Testing Commands

After registration:

1. Open Discord and go to your server
2. Type `/valheim` in any channel
3. You should see:
   - `/valheim start` - Start the server
   - `/valheim stop` - Stop the server
   - `/valheim status` - Check server status

## Setting Interaction Endpoint

The interaction endpoint tells Discord where to send command interactions.

**Automatic** (via script):
- Scripts automatically set the endpoint if `-FunctionAppUrl` is provided

**Manual**:
1. Go to: https://discord.com/developers/applications/1460365045132300308/interactions
2. Set **Interaction Endpoint URL** to:
   ```
   https://valheim-func-vmaygfpvthejm.azurewebsites.net/api/DiscordBot
   ```
3. Click "Save Changes"

## Verification Checklist

- [ ] Bot token is valid (test with setup script)
- [ ] Bot is added to your Discord server
- [ ] Commands are registered (verify with verification script)
- [ ] Interaction endpoint is set
- [ ] Commands appear when typing `/valheim` in Discord
- [ ] Commands respond when used (test `/valheim status`)

## Scripts Reference

### `setup-discord-bot.ps1`
Comprehensive setup script that:
- Verifies bot token
- Checks bot in server
- Registers commands
- Sets interaction endpoint
- Verifies everything worked

### `register-discord-commands.ps1`
Simple command registration script

### `verify-discord-commands.ps1`
Checks if commands are registered and shows their details

## Next Steps

After commands are registered:

1. **Test in Discord**: Type `/valheim status` to test
2. **Configure Public Key**: See `DISCORD_INTERACTIONS_COMPLIANCE.md` for signature verification setup
3. **Monitor Logs**: Check Azure Function App logs for interaction requests

## References

- [Discord Slash Commands](https://discord.com/developers/docs/interactions/application-commands)
- [Discord Interactions Overview](https://discord.com/developers/docs/interactions/overview)
- [Discord OAuth2](https://discord.com/developers/docs/topics/oauth2)
