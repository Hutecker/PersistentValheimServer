c# World Save Data Persistence

This document explains how world save data is persisted and protected from data loss.

## Persistence Architecture

### Storage Layer
- **Azure File Share**: `valheim-worlds` (100 GB quota)
- **Storage Account**: Standard LRS (Locally Redundant Storage)
- **Location**: Same region as the container instances
- **Access**: Mounted to container at `/config`

### Container Configuration
- **Mount Point**: `/config` → Azure File Share
- **World Save Location**: `/config/worlds/{WORLD_NAME}/`
- **Backup Location**: `/config/backups/` (automatic, 7-day retention)
- **World Name**: `Dedicated` (default, configurable via `WORLD_NAME` env var)

### Data Flow
```
Container Instance
    ↓ (mounts)
Azure File Share (valheim-worlds)
    ├── worlds/
    │   └── Dedicated/
    │       ├── Dedicated.db (world data)
    │       └── Dedicated.fwl (world metadata)
    └── backups/
        └── [timestamped backups]
```

## Persistence Guarantees

### ✅ What Persists
1. **World Save Files**: Stored in Azure File Share (survives container deletion)
2. **Automatic Backups**: Container creates daily backups (7-day retention)
3. **Container Restarts**: Data persists across container restarts
4. **Container Deletions**: Data persists when container is stopped/deleted
5. **Infrastructure Updates**: Data persists during Bicep redeployments

### ⚠️ What Doesn't Persist
1. **In-Memory State**: Any unsaved game state is lost when container stops
2. **Container Logs**: Logs are ephemeral (use Application Insights for persistence)
3. **Temporary Files**: Any files outside `/config` are lost

## Protection Mechanisms

### 1. Automatic Backups
- **Frequency**: Managed by container (lloesche/valheim-server image)
- **Retention**: 7 days (configurable via `BACKUPS_RETENTION_DAYS`)
- **Location**: `/config/backups/` in Azure File Share
- **Format**: Timestamped backups

### 2. Migration Safeguards
The migration script (`scripts/migrate-save.ps1`) includes:

- **Existence Check**: Detects if a world already exists
- **Automatic Backup**: Creates backup before overwriting existing worlds
- **User Confirmation**: Prompts before overwriting
- **Name Validation**: Warns if world file names don't match `WORLD_NAME`
- **Backup Location**: Backups stored in `backups/migration-backup-{timestamp}/`

### 3. Container Lifecycle
- **Restart Policy**: `Never` (container doesn't auto-restart, preventing conflicts)
- **Clean Shutdown**: Container saves world before stopping
- **Same Mount**: Every container instance uses the same Azure File Share mount

## Migration Safety

### Before Migration
1. ✅ Check if world already exists
2. ✅ Create backup of existing world (if present)
3. ✅ Validate world name matches `WORLD_NAME` environment variable
4. ✅ Prompt user for confirmation before overwriting

### During Migration
1. ✅ Upload files with correct naming (`{WORLD_NAME}.db` and `{WORLD_NAME}.fwl`)
2. ✅ Preserve existing backups
3. ✅ Create timestamped backup of existing world

### After Migration
1. ✅ Verify files uploaded successfully
2. ✅ Provide summary of migration
3. ✅ Document backup location

## Best Practices

### 1. World Name Consistency
- **Default**: Container uses `WORLD_NAME=Dedicated`
- **Migration**: Ensure migrated world files match this name
- **Alternative**: Update `WORLD_NAME` environment variable to match your world name

### 2. Regular Backups
- Container creates automatic backups
- Consider manual backups before major migrations
- Backups stored in Azure File Share (persistent)

### 3. Testing Migrations
- Test migrations on a non-production world first
- Verify world appears in server list after migration
- Check backup was created successfully

### 4. Monitoring
- Monitor Azure File Share usage (100 GB quota)
- Check backup directory for recent backups
- Review Application Insights logs for save operations

## Troubleshooting

### World Not Appearing After Migration
1. **Check World Name**: Ensure `WORLD_NAME` matches your world file names
2. **Verify File Names**: Files must be named `{WORLD_NAME}.db` and `{WORLD_NAME}.fwl`
3. **Check File Location**: Files must be in `worlds/{WORLD_NAME}/` directory
4. **Review Container Logs**: Check Application Insights for errors

### Data Loss Concerns
1. **Check Backups**: Look in `backups/` directory in Azure File Share
2. **Migration Backups**: Check `backups/migration-backup-{timestamp}/`
3. **Container Backups**: Check automatic backups in `backups/` directory
4. **Azure File Share Snapshots**: Consider enabling Azure File Share snapshots for additional protection

### Storage Issues
1. **Quota**: 100 GB should be plenty, but monitor usage
2. **Backup Cleanup**: Old backups (>7 days) are automatically cleaned up
3. **Manual Cleanup**: Can manually delete old backups if needed

## Future Enhancements

### Potential Improvements
1. **Azure File Share Snapshots**: Enable point-in-time recovery
2. **Cross-Region Replication**: For disaster recovery
3. **Backup to Blob Storage**: Long-term archival backups
4. **Automated Backup Verification**: Verify backup integrity
5. **World Name Auto-Detection**: Auto-detect world name from files

## References

- [Azure Files Documentation](https://docs.microsoft.com/azure/storage/files/)
- [Valheim Server Documentation](https://valheim.fandom.com/wiki/Dedicated_servers)
- [lloesche/valheim-server Docker Image](https://hub.docker.com/r/lloesche/valheim-server)
