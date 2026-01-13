# Script to verify Discord slash commands are registered
# This script checks if commands are registered and shows their details

param(
    [Parameter(Mandatory=$true)]
    [string]$ApplicationId,
    
    [Parameter(Mandatory=$true)]
    [string]$BotToken,
    
    [Parameter(Mandatory=$false)]
    [string]$GuildId = ""  # Optional: Check guild-specific commands
)

Write-Host "Discord Slash Command Verification" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# Validate inputs
if ([string]::IsNullOrEmpty($ApplicationId)) {
    Write-Host "Error: Application ID is required" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrEmpty($BotToken)) {
    Write-Host "Error: Bot Token is required" -ForegroundColor Red
    exit 1
}

$headers = @{
    "Authorization" = "Bot $BotToken"
    "Content-Type" = "application/json"
}

try {
    # Check if guild-specific or global commands
    if (-not [string]::IsNullOrEmpty($GuildId)) {
        $url = "https://discord.com/api/v10/applications/$ApplicationId/guilds/$GuildId/commands"
        Write-Host "Checking guild-specific commands for server: $GuildId" -ForegroundColor Cyan
    } else {
        $url = "https://discord.com/api/v10/applications/$ApplicationId/commands"
        Write-Host "Checking global commands" -ForegroundColor Cyan
    }
    
    Write-Host "GET $url" -ForegroundColor Gray
    Write-Host ""
    
    $commands = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
    
    if ($commands.Count -eq 0) {
        Write-Host "⚠️  No commands found!" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Commands need to be registered. Run:" -ForegroundColor Yellow
        Write-Host "  .\scripts\register-discord-commands.ps1 -ApplicationId `"$ApplicationId`" -BotToken `"$BotToken`"" -ForegroundColor Green
        if (-not [string]::IsNullOrEmpty($GuildId)) {
            Write-Host "  -GuildId `"$GuildId`"" -ForegroundColor Green
        }
        exit 0
    }
    
    Write-Host "✅ Found $($commands.Count) registered command(s):" -ForegroundColor Green
    Write-Host ""
    
    foreach ($cmd in $commands) {
        Write-Host "Command: /$($cmd.name)" -ForegroundColor Green
        Write-Host "  Description: $($cmd.description)" -ForegroundColor White
        Write-Host "  ID: $($cmd.id)" -ForegroundColor Gray
        
        if ($cmd.options -and $cmd.options.Count -gt 0) {
            Write-Host "  Subcommands:" -ForegroundColor Cyan
            foreach ($option in $cmd.options) {
                Write-Host "    - /$($cmd.name) $($option.name): $($option.description)" -ForegroundColor White
            }
        }
        Write-Host ""
    }
    
    # Check if valheim command exists
    $valheimCmd = $commands | Where-Object { $_.name -eq "valheim" }
    if ($valheimCmd) {
        Write-Host "✅ /valheim command is registered!" -ForegroundColor Green
        
        # Check for required subcommands
        $requiredSubcommands = @("start", "stop", "status")
        $existingSubcommands = $valheimCmd.options | ForEach-Object { $_.name }
        $missing = $requiredSubcommands | Where-Object { $existingSubcommands -notcontains $_ }
        
        if ($missing.Count -eq 0) {
            Write-Host "✅ All required subcommands are present!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Missing subcommands: $($missing -join ', ')" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ /valheim command not found!" -ForegroundColor Red
        Write-Host "   Run the registration script to register it." -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "❌ Error checking commands: $_" -ForegroundColor Red
    Write-Host ""
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "Status Code: $statusCode" -ForegroundColor Red
        
        if ($statusCode -eq 401) {
            Write-Host "Authentication failed. Check your Bot Token." -ForegroundColor Yellow
        } elseif ($statusCode -eq 403) {
            Write-Host "Forbidden. Bot may not have required permissions." -ForegroundColor Yellow
        } elseif ($statusCode -eq 404) {
            Write-Host "Application not found. Check your Application ID." -ForegroundColor Yellow
        }
    }
    
    exit 1
}

Write-Host ""
Write-Host "💡 Tip: Test commands in Discord by typing '/valheim' in a channel" -ForegroundColor Cyan
