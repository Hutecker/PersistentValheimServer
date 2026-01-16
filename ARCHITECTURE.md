# Architecture Overview

## System Design

This solution provides a cost-effective, Discord-controlled Valheim dedicated server using Azure services.

```
┌─────────────┐
│   Discord   │
│    Users    │
└──────┬──────┘
       │ Slash Commands
       ▼
┌─────────────────────────────────┐
│   Azure Function App            │
│   ┌───────────────────────────┐ │
│   │  DiscordBot Function      │ │
│   │  - Handle /valheim start  │ │
│   │  - Handle /valheim stop   │ │
│   │  - Handle /valheim status │ │
│   └───────────────────────────┘ │
│   ┌───────────────────────────┐ │
│   │  AutoShutdown Function    │ │
│   │  - Timer trigger          │ │
│   │  - Check shutdown time    │ │
│   │  - Stop container if due  │ │
│   └───────────────────────────┘ │
└──────┬──────────────────────────┘
       │
       │ Azure SDK
       ▼
┌─────────────────────────────────┐
│  Azure Container Instances (ACI) │
│  ┌─────────────────────────────┐ │
│  │  Valheim Server Container   │ │
│  │  - lloesche/valheim-server  │ │
│  │  - 2 CPU, 4 GB RAM          │ │
│  │  - Public IP + DNS          │ │
│  └─────────────────────────────┘ │
└──────┬──────────────────────────┘
       │
       │ Azure File Share Mount
       ▼
┌─────────────────────────────────┐
│     Azure File Share            │
│  ┌───────────────────────────┐  │
│  │  /config/worlds/          │  │
│  │  - Dedicated.db          │  │
│  │  - Dedicated.fwl         │  │
│  │  - backups/              │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

## Components

### 1. Azure Container Instances (ACI)

**Purpose**: Hosts the Valheim dedicated server

**Configuration**:
- Image: `lloesche/valheim-server:latest`
- Resources: 2 CPU cores, 4 GB RAM
- Ports: 2456-2458 UDP
- Restart Policy: Never (controlled via Discord)
- Storage: Azure File Share mounted at `/config`

**Cost**: ~$0.10-0.15/hour when running, $0 when stopped

### 2. Azure File Share

**Purpose**: Persistent storage for world saves

**Configuration**:
- Size: 100 GB quota
- SKU: Standard LRS (lowest cost)
- Mounted to container at `/config`

**Cost**: ~$0.01/day (storage only)

### 3. Azure Functions

**Purpose**: Server control logic

**Functions**:
- **DiscordBot**: HTTP trigger for Discord interactions
- **AutoShutdown**: Timer trigger

**Configuration**:
- Runtime: .NET 10.0 (dotnet-isolated)
- Plan: Flex Consumption (FC1) - enhanced scalability and features
- Identity: System-assigned managed identity
- Deployment: Blob container deployment (One Deploy method)
- Secrets: Accessed via Key Vault references in app settings (not direct Key Vault calls)

**Cost**: ~$0.20/month (minimal usage)

### 4. Azure Key Vault

**Purpose**: Secure storage for secrets

**Secrets**:
- Discord Bot Token
- Discord Public Key (for signature verification)
- Valheim Server Password

**Access**: Function App accesses secrets via Key Vault references in app settings (resolved by Azure platform at runtime)

**Cost**: ~$0.03/month

### 5. Application Insights

**Purpose**: Monitoring and logging

**Features**:
- Function execution logs
- Container logs
- Performance metrics
- Cost tracking

**Cost**: First 5 GB free, then ~$2.30/GB

## Data Flow

### Starting the Server

1. User types `/valheim start` in Discord
2. Discord sends interaction to Function App endpoint
3. DiscordBot function:
   - Reads secrets from environment variables (resolved from Key Vault references)
   - Gets storage account key via Azure SDK
   - Creates container group via Azure SDK
   - Returns confirmation message
4. Container starts (1-3 minutes)
5. Server becomes available

### Stopping the Server

1. User types `/valheim stop` in Discord
2. DiscordBot function:
   - Deletes container group
   - Returns confirmation
3. Container stops immediately
4. World saves persist in File Share

### Auto-Shutdown

1. AutoShutdown function runs on configurable timer
2. Checks if container is running
3. Calculates time since start
4. If timeout exceeded, deletes container group
5. World saves remain in File Share

## Security

### Authentication & Authorization

- **Discord**: Bot token and public key stored in Key Vault, accessed via app setting references
- **Discord Interactions**: Ed25519 signature verification using Discord public key
- **Azure**: Managed identity for Function App to access Azure resources
- **Key Vault**: RBAC authorization, Function App has "Key Vault Secrets User" role
- **Storage**: Function App has "Storage Account Contributor" and "Storage File Data SMB Share Elevated Contributor" roles
- **Container Instances**: Function App has "Azure Container Instances Contributor" role

### Network Security

- Container has public IP (required for Valheim)
- Function App uses HTTPS only
- Key Vault uses private endpoints (optional)

## Cost Optimization

### Strategies

1. **On-Demand Compute**: Server only runs when needed
2. **Auto-Shutdown**: Prevents forgotten running instances
3. **Consumption Plan**: Functions only charge for executions
4. **Standard LRS Storage**: Lowest cost storage tier
5. **Container Instances**: Pay-per-second billing

### Estimated Monthly Costs

**Scenario: 10 hours/week usage**

- ACI (10 hrs/week × 4 weeks × $0.12/hr): ~$4.80
- File Share (100 GB × $0.06/GB): ~$6.00
- Functions (minimal): ~$0.20
- Key Vault: ~$0.03
- Application Insights (5 GB free): $0.00
- **Total: ~$11/month**

**When Stopped**: ~$6/month (storage only)

## Scalability

### Current Limits

- **Players**: Supports up to 10 players (Valheim limit)
- **World Size**: Limited by 100 GB file share
- **Concurrent Servers**: 1 (can be scaled)

### Scaling Options

1. **Increase Container Resources**: Edit Bicep template
2. **Multiple Servers**: Deploy additional container groups
3. **Premium File Share**: For better performance
4. **VM Instead of ACI**: For faster startup (higher cost)

## Monitoring

### Metrics Tracked

- Container start/stop events
- Function execution times
- Storage usage
- Cost per day/week/month
- Server uptime

### Alerts

- Budget exceeded
- Container failed to start
- Function errors
- Storage quota approaching limit

## Disaster Recovery

### Backups

- World saves automatically backed up by container
- Backups stored in File Share
- Retention: 7 days (configurable)

### Recovery

1. World saves persist in File Share
2. Container can be recreated anytime
3. No data loss on container deletion

## Future Enhancements

- [ ] Web dashboard for server management
- [ ] Player count monitoring
- [ ] Automated world backups to Blob Storage
- [ ] SMS/Email notifications
- [ ] Scheduled server start/stop
- [ ] Multiple world support
- [ ] Server performance metrics
