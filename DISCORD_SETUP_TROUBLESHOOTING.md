# Discord Bot Setup Troubleshooting

## Error 40333: "internal network error"

This error typically indicates a bot configuration issue. Follow these steps:

### Step 1: Verify Bot Setup

1. **Go to Discord Developer Portal**: https://discord.com/developers/applications
2. **Select your application** (Application ID: 1460365045132300308)
3. **Go to "Bot" section** (left sidebar)
4. **Verify**:
   - ✅ Bot is created
   - ✅ "Public Bot" is enabled (if you want it public)
   - ✅ "Message Content Intent" is enabled (if needed)
   - ✅ Bot token is valid (click "Reset Token" if needed)

### Step 2: Add Bot to Your Server

1. **Go to "OAuth2" → "URL Generator"** (left sidebar)
2. **Select scopes**:
   - ✅ `bot`
   - ✅ `applications.commands`
3. **Select bot permissions** (optional, but recommended):
   - Send Messages
   - Use Slash Commands
4. **Copy the generated URL** and open it in a browser
5. **Select your Discord server** and authorize the bot

### Step 3: Verify Bot Token

1. **Go to "Bot" section**
2. **Click "Reset Token"** if the token seems invalid
3. **Copy the new token** (starts with letters/numbers, NOT "Bot ")
4. **Update your deployment** with the new token if needed

### Step 4: Try Registration Again

After completing steps 1-3, try registering commands again:

```powershell
.\scripts\register-discord-commands.ps1 `
  -ApplicationId "1460365045132300308" `
  -BotToken "YOUR_NEW_BOT_TOKEN" `
  -FunctionAppUrl "https://valheim-func-vmaygfpvthejm.azurewebsites.net"
```

## Alternative: Manual Registration via Discord Developer Portal

If the script continues to fail, you can register commands manually:

1. **Go to**: https://discord.com/developers/applications/1460365045132300308/commands
2. **Click "New Command"**
3. **Fill in**:
   - Name: `valheim`
   - Description: `Control the Valheim server`
4. **Add subcommands**:
   - Click "Add Subcommand"
   - Name: `start`, Description: `Start the Valheim server`
   - Click "Add Subcommand"
   - Name: `stop`, Description: `Stop the Valheim server`
   - Click "Add Subcommand"
   - Name: `status`, Description: `Check server status`
5. **Click "Save Changes"**

## Set Interaction Endpoint URL

1. **Go to**: https://discord.com/developers/applications/1460365045132300308/interactions
2. **Set Interaction Endpoint URL** to:
   ```
   https://valheim-func-vmaygfpvthejm.azurewebsites.net/api/DiscordBot
   ```
3. **Click "Save Changes"**

## Common Issues

### Bot Token Invalid
- Reset the bot token in Discord Developer Portal
- Make sure you're using the token (not the client secret)
- Token should start with letters/numbers, not "Bot "

### Bot Not Added to Server
- Use OAuth2 URL Generator to add bot to your server
- Make sure `bot` and `applications.commands` scopes are selected

### Missing Permissions
- Bot needs to be in the server where you want to use commands
- Bot needs `applications.commands` scope

### Rate Limiting
- Discord API has rate limits
- Wait a few minutes and try again if you see rate limit errors

## Verify Setup

After setup, test in Discord:
1. Type `/valheim` in a channel where the bot is present
2. You should see the command appear with subcommands
3. Try `/valheim status` to test
