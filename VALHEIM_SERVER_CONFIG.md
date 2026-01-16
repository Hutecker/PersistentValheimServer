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
| `BACKUPS` | Enable backups | `1` | Automatic backups enabled |
| `BACKUPS_RETENTION_DAYS` | Backup retention | `7` | Keep 7 days of backups |
| `UPDATE_CRON` | Auto-update schedule | `0 4 * * *` | Daily at 4 AM UTC |

### Port Configuration

The Valheim server requires three UDP ports:
- **2456**: Main game server port
- **2457**: Query server port  
- **2458**: Steam server port

All ports are correctly configured in our container group.

### Storage Configuration

- **Mount Point**: `/config` (container path)
- **Azure File Share**: `valheim-worlds`
- **World Save Location**: `/config/worlds/{WORLD_NAME}/`
- **Backup Location**: `/config/backups/`

World saves are stored as:
- `{WORLD_NAME}.db` - World data
- `{WORLD_NAME}.fwl` - World metadata

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

### Server Not Appearing in Browser

1. Verify `SERVER_PUBLIC=1` is set
2. Check ports 2456-2458 UDP are accessible
3. Ensure server has been running for at least 1-2 minutes
4. Try connecting via IP address instead

### World Not Loading

1. Verify world files exist in `/config/worlds/{WORLD_NAME}/`
2. Check file permissions (should be readable by container)
3. Ensure both `.db` and `.fwl` files are present
4. Check container logs for errors

### Connection Issues

1. Verify public IP is accessible
2. Check firewall rules allow UDP ports 2456-2458
3. Test connection from Valheim game client
4. Check server logs for connection attempts

## References

- [Valheim Fandom - Dedicated Servers](https://valheim.fandom.com/wiki/Dedicated_servers)
- [Official Valheim Server Guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/)
- [Docker Image Documentation](https://hub.docker.com/r/lloesche/valheim-server)
