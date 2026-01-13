# Persistent Valheim Server on Azure

A cost-effective, Discord-controlled Valheim dedicated server hosted on Azure.

## Architecture Overview

This solution uses:
- **Azure Container Instances (ACI)** - Runs the Valheim server on-demand (only pay when running)
- **Azure File Share** - Persistent storage for world saves
- **Azure Functions** - Discord bot integration and auto-shutdown logic
- **Azure Key Vault** - Secure storage for secrets (Discord token, server password)

### Cost Optimization Strategy

- Server only runs when needed (started via Discord)
- Automatic shutdown after configurable timeout (default: 2 hours)
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

## Prerequisites

- Azure subscription
- Azure CLI installed and logged in
- .NET 8.0 SDK installed
- Azure Functions Core Tools installed
- Discord bot token (create at https://discord.com/developers/applications)
- PowerShell execution policy configured (see [DEPLOYMENT_TROUBLESHOOTING.md](DEPLOYMENT_TROUBLESHOOTING.md))

## Quick Start

### 1. Deploy Infrastructure

```bash
# Set your variables
export RESOURCE_GROUP="valheim-server-rg"
export LOCATION="eastus"
export DISCORD_BOT_TOKEN="your-discord-bot-token"
export SERVER_PASSWORD="your-server-password"
export SERVER_NAME="YourServerName"

# Deploy
cd infrastructure
az deployment sub create \
  --location $LOCATION \
  --template-file main.bicep \
  --parameters resourceGroupName=$RESOURCE_GROUP \
               location=$LOCATION \
               discordBotToken=$DISCORD_BOT_TOKEN \
               serverPassword=$SERVER_PASSWORD \
               serverName=$SERVER_NAME
```

### 2. Configure Discord Bot

1. Create a Discord application at https://discord.com/developers/applications
2. Create a bot and copy the token
3. Invite bot to your server with `applications.commands` and `bot` scopes
4. Set the webhook URL in Discord (from Function App output)

### 3. Usage

In your Discord channel:
- `/valheim start` - Start the server
- `/valheim stop` - Stop the server
- `/valheim status` - Check server status

The server will automatically shut down after the configured timeout (default: 2 hours).

## Save Migration

See `scripts/migrate-save.md` for instructions on migrating an existing Valheim world save.

## Project Structure

```
.
├── infrastructure/          # Bicep IaC templates
│   ├── main.bicep         # Main deployment template
│   └── modules/           # Reusable modules
├── functions/              # Azure Functions
│   ├── DiscordBot/        # Discord command handler
│   └── AutoShutdown/      # Timer-triggered shutdown
├── scripts/               # Utility scripts
│   └── migrate-save.md    # Save migration guide
└── README.md              # This file
```

## Monitoring

- Application Insights dashboard for server metrics
- Discord notifications for server start/stop events
- Azure Monitor alerts for cost tracking

## Cost Estimates

- **Running**: ~$0.10-0.15/hour (ACI + Storage)
- **Stopped**: ~$0.01/day (Storage only)
- **Monthly (10 hours/week)**: ~$4-6/month

## References

- [Valheim Dedicated Server Guide (Fandom)](https://valheim.fandom.com/wiki/Dedicated_servers)
- [Official Valheim Dedicated Server Guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/)
- [Docker Image: lloesche/valheim-server](https://hub.docker.com/r/lloesche/valheim-server)

## Documentation

- [SETUP.md](SETUP.md) - Complete setup guide
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture details
- [VALHEIM_SERVER_CONFIG.md](VALHEIM_SERVER_CONFIG.md) - Valheim server configuration details
- [MANAGED_IDENTITY.md](MANAGED_IDENTITY.md) - Managed identity configuration and security
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Quick command reference

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.
