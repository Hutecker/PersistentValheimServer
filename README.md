# Persistent Valheim Server on Azure

A cost-effective, Discord-controlled Valheim dedicated server hosted on Azure.

## Architecture Overview

This solution uses:
- **Azure Container Instances (ACI)** - Runs the Valheim server on-demand with crossplay enabled (only pay when running)
- **Azure Container Registry (ACR)** - Hosts the Valheim Docker image (avoids Docker Hub rate limits)
- **Azure File Share** - Persistent storage for world saves
- **Azure Functions** - Discord bot integration, auto-shutdown logic, and join code retrieval
- **Azure Key Vault** - Secure storage for secrets (Discord token, server password)

### Cost Optimization Strategy

- Server only runs when needed (started via Discord)
- Automatic shutdown after configurable timeout (default: 12 hours)
- Uses Azure Container Instances (pay-per-second billing)
- Burstable compute tier for cost efficiency
- Estimated cost: ~$0.10-0.15/hour when running

## Features

✅ Discord channel control (start/stop server)  
✅ Automatic shutdown after inactivity  
✅ Persistent world saves  
✅ Save migration support  
✅ Infrastructure as Code (Bicep)  
✅ Cost-optimized for 5 players  
✅ **Crossplay support** (PC Steam, PC Game Pass, Xbox)  
✅ Easy connection via **Join Code** (no IP configuration needed)  

## Prerequisites

- Azure subscription
- Azure CLI installed and logged in
- .NET 10.0 SDK installed
- **Azure Functions Core Tools** (installed automatically by deploy script, or manually: `npm install -g azure-functions-core-tools@4`)
- Node.js (required for Azure Functions Core Tools installation)
- Discord bot token and public key (create at https://discord.com/developers/applications)
- PowerShell execution policy configured:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

## Quick Start

### 1. Create Discord Bot

1. Go to https://discord.com/developers/applications
2. Create a new application
3. Go to **Bot** section → Click **Add Bot** → Copy the **Bot Token**
4. Go to **General Information** → Copy the **Public Key** (64-character hex string)
5. Go to **OAuth2 → URL Generator**:
   - Select scopes: `bot`, `applications.commands`
   - Select permissions: Send Messages, Use Slash Commands
   - Copy the URL and open it to invite the bot to your server

### 2. Deploy Infrastructure

Run the deployment script with your values:

```powershell
.\scripts\deploy.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -Location "eastus" `
  -DiscordBotToken "YOUR_DISCORD_BOT_TOKEN_HERE" `
  -DiscordPublicKey "YOUR_64_CHARACTER_HEX_PUBLIC_KEY_HERE" `
  -ServerPassword "YOUR_SERVER_PASSWORD_HERE" `
  -ServerName "My Valheim Server" `
  -AutoShutdownMinutes 720 `
  -MonthlyBudgetLimit 30.0 `
  -BudgetAlertEmail "your-email@example.com"
```

**Example with placeholder values:**

```powershell
.\scripts\deploy.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -Location "eastus" `
  -DiscordBotToken "MTQ2MDM2NTA0NTEzMjMwMDMwOA.GE1tcd.example_token_here" `
  -DiscordPublicKey "9220348032faaf2e50d7a71af23f69a80492b966a6e363e7ccbb12a81880cf0c" `
  -ServerPassword "YourSecurePassword123" `
  -ServerName "My Valheim Server" `
  -AutoShutdownMinutes 720 `
  -MonthlyBudgetLimit 30.0 `
  -BudgetAlertEmail "your-email@example.com"
```

**Note:** Replace all placeholder values with your actual:
- Discord Bot Token (from Discord Developer Portal → Bot section)
- Discord Public Key (64-character hex string from General Information)
- Server Password (your Valheim server password)
- Email address for budget alerts (optional but recommended)

The script will:
- Deploy all Azure infrastructure (Storage, Key Vault, Function App) via Bicep
- Configure Function App settings, including Key Vault references for secrets
- Set up managed identity and role assignments
- Build, test, and deploy the Function App code

#### Code-Only Deployment

For faster iterations during development, you can deploy only the Function App code without redeploying infrastructure:

```powershell
.\scripts\deploy.ps1 `
  -CodeOnly `
  -FunctionAppName "valheim-func" `
  -ResourceGroupName "valheim-server-rg" `
  -Location "eastus" `
  -DiscordBotToken "YOUR_DISCORD_BOT_TOKEN_HERE" `
  -DiscordPublicKey "YOUR_64_CHARACTER_HEX_PUBLIC_KEY_HERE" `
  -ServerPassword "YOUR_SERVER_PASSWORD_HERE" `
  -ServerName "My Valheim Server" `
  -AutoShutdownMinutes 720 `
  -MonthlyBudgetLimit 30.0 `
  -BudgetAlertEmail "your-email@example.com"
```

**Note:** When using `-CodeOnly`:
- The `-FunctionAppName` parameter is required
- Infrastructure deployment is skipped (faster for code changes)
- All other parameters are still required (they're validated but not used)
- To find your Function App name: `az functionapp list --resource-group "valheim-server-rg" --query '[0].name' -o tsv`

### 3. Configure Discord Interactions Endpoint

After deployment, set the interactions endpoint in Discord:

1. Go to https://discord.com/developers/applications → Your Application → **Interactions**
2. Set **Interaction Endpoint URL** to the Function App URL shown at the end of deployment (format: `https://<function-app-name>.azurewebsites.net/api/DiscordBot`)
   - The exact Function App name will be displayed in the deployment output
   - Example: `https://valheim-func-abc123.azurewebsites.net/api/DiscordBot`
3. Register slash commands using the JSON shown at the end of deployment

### 4. Migrate World Save (Optional)

If you have an existing world save, use the migration script:

```powershell
.\scripts\migrate-save.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -StorageAccountName "valheimsa" `
  -FileShareName "valheim-worlds" `
  -WorldName "Dedicated" `
  -WorldDbPath "C:\path\to\world.db" `
  -WorldFwlPath "C:\path\to\world.fwl"
```

#### Finding Your World Save Files on Windows

Valheim stores world saves in the following location:

**Local Saves:**
```
%UserProfile%\AppData\LocalLow\IronGate\Valheim\worlds_local
```

**Full Path Example:**
```
C:\Users\YourUsername\AppData\LocalLow\IronGate\Valheim\worlds_local
```

**To find your world files:**
1. Press `Win + R` to open Run dialog
2. Type: `%UserProfile%\AppData\LocalLow\IronGate\Valheim\worlds_local`
3. Press Enter
4. You'll see files like:
   - `YourWorldName.db` - World data file
   - `YourWorldName.fwl` - World metadata file

**Important Notes:**
- If your world is in **Steam Cloud**, first move it to local:
  - In Valheim: **Manage Saves** → Select your world → **Move to Local**
- The world name in the file names must match the `-WorldName` parameter
- You need **both** `.db` and `.fwl` files for a complete world

**Example Migration:**
If your world is named "MyWorld" and you found:
- `C:\Users\YourUsername\AppData\LocalLow\IronGate\Valheim\worlds_local\MyWorld.db`
- `C:\Users\YourUsername\AppData\LocalLow\IronGate\Valheim\worlds_local\MyWorld.fwl`

Run:
```powershell
.\scripts\migrate-save.ps1 `
  -ResourceGroupName "valheim-server-rg" `
  -StorageAccountName "valheimsa" `
  -FileShareName "valheim-worlds" `
  -WorldName "MyWorld" `
  -WorldDbPath "C:\Users\YourUsername\AppData\LocalLow\IronGate\Valheim\worlds_local\MyWorld.db" `
  -WorldFwlPath "C:\Users\YourUsername\AppData\LocalLow\IronGate\Valheim\worlds_local\MyWorld.fwl"
```

### 5. Usage

In your Discord channel:
- `/valheim start` - Start the server (provides join code when ready)
- `/valheim stop` - Stop the server (saves world automatically)
- `/valheim status` - Check server status and get current join code

The server will automatically shut down after the configured timeout (default: 12 hours).

### 6. Connecting to the Server

Once the server is started, the Discord bot will provide a **Join Code** for easy connection.

**Crossplay Support:**
This server uses the `-crossplay` flag, enabling connections from:
- **PC (Steam)**
- **PC (Microsoft Store/Game Pass)**
- **Xbox**
- **PlayStation** (when available)

**To Connect in Valheim:**

1. **Enable Crossplay** in your Valheim settings (required for join code)
2. Open Valheim
3. Click **"Join Game"**
4. Click **"Join by Code"**
5. Enter the **6-digit Join Code** from the Discord bot (e.g., `821680`)
6. Enter the server password
7. Click **"Connect"**

**Discord Bot Output:**
When you run `/valheim start` or `/valheim status`, the bot will show:
```
🎮 Join Code: 821680

To Connect (PC & Console):
1. Enable Crossplay in Valheim settings
2. Join Game → Join by Code
3. Enter: 821680
4. Enter server password
```

**Important Notes:**
- **Crossplay Required:** You must enable Crossplay in Valheim settings to use join codes
- **Wait Time:** The server may take 3-5 minutes to fully initialize after container starts
- **Join Code Changes:** A new join code is generated each time the server starts
- If connection fails, wait 1-2 more minutes and try again

**Server Ports (for reference):**
- Ports `2456`, `2457`, `2458` (UDP) are exposed for game traffic
- With crossplay, connections route through PlayFab relay servers

**Troubleshooting Connection Issues:**

If you get "Failed to connect":
1. **Enable Crossplay:** Ensure Crossplay is enabled in Valheim settings
2. **Wait longer:** Server may need 3-5 minutes to fully initialize
3. **Get fresh code:** Run `/valheim status` to get the current join code
4. **Verify server status:** Confirm server is running in Discord
5. **Check container logs:** In Azure Portal → Container Instance → Logs

## Project Structure

```
.
├── infrastructure/          # Bicep IaC templates
│   └── main.bicep         # Main deployment template
├── functions/              # Azure Functions
│   ├── DiscordBot/        # Discord command handler
│   ├── AutoShutdown/     # Timer-triggered shutdown
│   └── ValheimServerFunctions.Tests/  # Unit tests
└── scripts/               # Deployment scripts
    ├── deploy.ps1         # Main deployment script
    └── migrate-save.ps1   # World save migration utility
```

## Architecture

- **Azure Container Instances (ACI)**: Runs Valheim server on-demand
- **Azure Container Registry (ACR)**: Hosts Valheim Docker image (Basic tier, ~$5/month)
- **Azure File Share**: Persistent storage for world saves
- **Azure Functions (Flex Consumption)**: Discord bot and auto-shutdown logic (.NET 10.0 isolated)
- **Azure Key Vault**: Secure storage for secrets (accessed via Key Vault references in app settings)
- **Managed Identity**: System-assigned identity for secure resource access
- **Application Insights**: Monitoring and logging

## Cost Estimates

- **Running**: ~$0.10-0.15/hour (ACI + Storage)
- **Stopped**: ~$0.01/day (Storage only)
- **Azure Container Registry**: ~$5/month (Basic tier, avoids Docker Hub rate limits)
- **Monthly (10 hours/week)**: ~$9-11/month (including ACR)
- **Budget & Alerts**: **FREE** (no additional cost)

### Why Azure Container Registry?

Docker Hub has rate limits for anonymous image pulls (100 per 6 hours). Azure Container Instances share IP ranges, so you can hit these limits even with infrequent use, causing server start failures. ACR provides:
- No rate limits within Azure network
- Faster container startup (same datacenter)
- Reliable image pulls every time

### Budget Alerts

The deployment includes budget monitoring with alerts at:
- **50%** of budget ($15) - Early warning
- **75%** of budget ($22.50) - Approaching limit
- **90%** of budget ($27) - Critical warning
- **100%** of budget ($30) - Budget exceeded
- **80% forecasted** - Predictive alert based on spending trends

Alerts are sent via email (if `-BudgetAlertEmail` is provided during deployment).

## References

- [Valheim Dedicated Server Guide](https://valheim.fandom.com/wiki/Dedicated_servers)
- [Docker Image: lloesche/valheim-server](https://hub.docker.com/r/lloesche/valheim-server)
- [Azure Functions Flex Consumption](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-how-to)
