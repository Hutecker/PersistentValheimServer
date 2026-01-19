# Valheim Server Configuration

This document details how our implementation aligns with the official Valheim dedicated server requirements.

## Official Requirements

Based on the official Valheim server documentation:
- **Ports**: 2456-2458 UDP (required for game, query, and Steam services)
- **Server Name**: Displayed in server browser
- **Server Password**: Required for private servers
- **World Name**: Used for save file naming
- **Public Server**: Set to 1 for public listing, 0 for private

## Docker Image Configuration

We use the `lloesche/valheim-server` Docker image, which is a popular, well-maintained container for Valheim servers.

### Environment Variables

| Variable | Purpose | Our Value | Notes |
|----------|---------|-----------|-------|
| `SERVER_NAME` | Server display name | Configurable | Set via deployment parameter |
| `WORLD_NAME` | World save name | `Dedicated` | Default, can be changed |
| `SERVER_PASS` | Server password | From Key Vault | Secure storage |
| `SERVER_PUBLIC` | Public listing | `1` | Set to 1 for public server |
| `SERVER_ARGS` | Server launch args | `-crossplay` | Enables PC & Console crossplay |
| `BACKUPS` | Enable backups | `1` | Automatic backups enabled |
| `BACKUPS_RETENTION_DAYS` | Backup retention | `7` | Keep 7 days of backups |
| `UPDATE_CRON` | Auto-update schedule | `0 4 * * *` | Daily at 4 AM UTC |

### Crossplay Configuration

The server is configured with `-crossplay` flag which:
- Enables cross-platform play (PC Steam, PC Game Pass, Xbox)
- Uses PlayFab backend instead of Steam-only networking
- Generates a 6-digit **Join Code** for easy connections
- Allows both PC and console players to join using the same code

### Port Configuration

The Valheim server requires three UDP ports:
- **2456**: Main game server port
- **2457**: Query server port  
- **2458**: Steam server port

All ports are correctly configured in our container group.

### Storage Configuration

- **Mount Point**: `/config` (container path)
- **Azure File Share**: `valheim-worlds`
- **World Save Location**: `/config/worlds_local/` (files directly in this folder)
- **Backup Location**: `/config/backups/`

World saves are stored as:
- `worlds_local/{WORLD_NAME}.db` - World data
- `worlds_local/{WORLD_NAME}.fwl` - World metadata

**Note:** With crossplay enabled, the Valheim server stores saves directly in `worlds_local/` rather than in world-name subdirectories.

## Server Requirements

### Minimum Requirements (Official)
- **CPU**: 2 cores (we use 2 cores)
- **RAM**: 2 GB (we use 4 GB for better performance)
- **Storage**: ~1 GB for server + world saves (we allocate 100 GB)

### Recommended for 5-10 Players
- **CPU**: 2-4 cores [OK] (we use 2 cores - sufficient for 5 players)
- **RAM**: 4 GB [OK] (we use 4 GB)
- **Network**: Stable connection with low latency

## Server Settings

### Public vs Private

Our server is configured as **public** (`SERVER_PUBLIC=1`), which means:
- Server appears in Valheim's server browser
- Players can find it by name
- Still requires password to join

To make it private (invite-only), set `SERVER_PUBLIC=0`.

### World Persistence

World saves are automatically persisted to Azure File Share:
- Saves survive container restarts
- Automatic backups every 6 hours (container default)
- Backup retention: 7 days (configurable)

## Alignment with Official Guides

### [OK] Requirements Met

1. **Port Configuration**: All required UDP ports (2456-2458) are exposed
2. **Server Password**: Securely stored and configured
3. **World Persistence**: World saves stored in persistent Azure File Share
4. **Server Name**: Configurable via deployment parameters
5. **Public Listing**: Configurable (default: public)
6. **Backups**: Automatic backups enabled with retention policy

### 📝 Additional Features

Beyond official requirements, we've added:
- Discord bot control for start/stop
- Auto-shutdown for cost savings
- Infrastructure as Code (Bicep)
- Secure secret management (Key Vault)
- Monitoring and logging (Application Insights)

## Docker Image Details

**Image**: `lloesche/valheim-server:latest`

**Source**: https://hub.docker.com/r/lloesche/valheim-server

**Features**:
- Automatic game updates
- Built-in backup system
- Health checks
- Log management
- Steam integration

**Documentation**: See the Docker Hub page for full environment variable reference.

## Troubleshooting

### Cannot Get Join Code

1. Run `/valheim status` in Discord to get the current join code
2. Check container logs in Azure Portal for "registered with join code" message
3. Ensure server has been running for at least 2-3 minutes
4. The join code changes each time the server starts

### World Not Loading

1. Verify world files exist in `/config/worlds_local/` directory
2. Check file permissions (should be readable by container)
3. Ensure both `.db` and `.fwl` files are present
4. Check container logs for errors

### Connection Issues

1. **Enable Crossplay:** Ensure Crossplay is enabled in your Valheim settings
2. Use **Join by Code** (not Join by IP) with the 6-digit join code
3. Verify the join code is current (get fresh code from `/valheim status`)
4. Wait 3-5 minutes after server start for full initialization
5. Check container logs for PlayFab registration status

### Console Players Cannot Connect

1. Verify `-crossplay` is in `SERVER_ARGS` environment variable
2. Ensure console players have Crossplay enabled in their settings
3. Console players must use Join by Code (not IP address)
4. Verify all players are on the same Valheim version

## References

- [Valheim Fandom - Dedicated Servers](https://valheim.fandom.com/wiki/Dedicated_servers)
- [Official Valheim Server Guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/)
- [Docker Image Documentation](https://hub.docker.com/r/lloesche/valheim-server)
