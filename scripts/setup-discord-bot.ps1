# Comprehensive Discord Bot Setup Script
# This script helps you set up and verify your Discord bot step by step

param(
    [Parameter(Mandatory=$true)]
    [string]$ApplicationId,
    
    [Parameter(Mandatory=$true)]
    [string]$BotToken,
    
    [Parameter(Mandatory=$false)]
    [string]$GuildId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$FunctionAppUrl = ""
)

Write-Host "Discord Bot Setup & Verification" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify bot token format
Write-Host "Step 1: Verifying Bot Token..." -ForegroundColor Yellow
if ($BotToken -match "^[A-Za-z0-9._-]+$") {
    Write-Host "✅ Bot Token format looks valid" -ForegroundColor Green
} else {
    Write-Host "⚠️  Bot Token format may be invalid" -ForegroundColor Yellow
    Write-Host "   Token should be alphanumeric with dots/dashes, no spaces" -ForegroundColor Gray
}
Write-Host ""

# Step 2: Test bot authentication
Write-Host "Step 2: Testing Bot Authentication..." -ForegroundColor Yellow
try {
    $headers = @{
        "Authorization" = "Bot $BotToken"
    }
    $botInfo = Invoke-RestMethod -Uri "https://discord.com/api/v10/users/@me" -Method Get -Headers $headers -ErrorAction Stop
    Write-Host "✅ Bot authentication successful!" -ForegroundColor Green
    Write-Host "   Bot Username: $($botInfo.username)#$($botInfo.discriminator)" -ForegroundColor Gray
    Write-Host "   Bot ID: $($botInfo.id)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Bot authentication failed!" -ForegroundColor Red
    Write-Host "   Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "   This usually means:" -ForegroundColor Yellow
    Write-Host "   1. Bot Token is incorrect or expired" -ForegroundColor White
    Write-Host "   2. Bot Token was reset in Discord Developer Portal" -ForegroundColor White
    Write-Host ""
    Write-Host "   Fix: Go to https://discord.com/developers/applications/$ApplicationId/bot" -ForegroundColor Cyan
    Write-Host "        and copy the Bot Token again" -ForegroundColor Cyan
    exit 1
}
Write-Host ""

# Step 3: Check if bot is in a server (if GuildId provided)
if (-not [string]::IsNullOrEmpty($GuildId)) {
    Write-Host "Step 3: Checking Bot in Server..." -ForegroundColor Yellow
    try {
        $guildMember = Invoke-RestMethod -Uri "https://discord.com/api/v10/guilds/$GuildId/members/$($botInfo.id)" -Method Get -Headers $headers -ErrorAction Stop
        Write-Host "✅ Bot is in the server!" -ForegroundColor Green
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 404) {
            Write-Host "❌ Bot is NOT in this server!" -ForegroundColor Red
            Write-Host ""
            Write-Host "   Add the bot to your server:" -ForegroundColor Yellow
            Write-Host "   1. Go to: https://discord.com/developers/applications/$ApplicationId/oauth2/url-generator" -ForegroundColor Cyan
            Write-Host "   2. Select scopes: 'bot' and 'applications.commands'" -ForegroundColor White
            Write-Host "   3. Select permissions: 'Send Messages', 'Use Slash Commands'" -ForegroundColor White
            Write-Host "   4. Copy the generated URL and open it in a browser" -ForegroundColor White
            Write-Host "   5. Select your server and authorize" -ForegroundColor White
            Write-Host ""
            Write-Host "   Then run this script again." -ForegroundColor Yellow
            exit 1
        } else {
            Write-Host "⚠️  Could not verify bot in server: $_" -ForegroundColor Yellow
        }
    }
    Write-Host ""
}

# Step 4: Check existing commands
Write-Host "Step 4: Checking Existing Commands..." -ForegroundColor Yellow
try {
    if (-not [string]::IsNullOrEmpty($GuildId)) {
        $url = "https://discord.com/api/v10/applications/$ApplicationId/guilds/$GuildId/commands"
    } else {
        $url = "https://discord.com/api/v10/applications/$ApplicationId/commands"
    }
    
    $existingCommands = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
    
    if ($existingCommands.Count -gt 0) {
        Write-Host "✅ Found $($existingCommands.Count) existing command(s)" -ForegroundColor Green
        $valheimCmd = $existingCommands | Where-Object { $_.name -eq "valheim" }
        if ($valheimCmd) {
            Write-Host "✅ /valheim command is already registered!" -ForegroundColor Green
            Write-Host "   Command ID: $($valheimCmd.id)" -ForegroundColor Gray
        } else {
            Write-Host "⚠️  /valheim command not found, will register it" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️  No commands found, will register them" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Could not check existing commands: $_" -ForegroundColor Yellow
    Write-Host "   Will attempt to register anyway" -ForegroundColor Gray
}
Write-Host ""

# Step 5: Register commands
Write-Host "Step 5: Registering Commands..." -ForegroundColor Yellow
try {
    # Command definition - single command object (not array)
    $command = @{
        name = "valheim"
        description = "Control the Valheim server"
        options = @(
            @{
                name = "start"
                description = "Start the Valheim server"
                type = 1
            },
            @{
                name = "stop"
                description = "Stop the Valheim server"
                type = 1
            },
            @{
                name = "status"
                description = "Check server status"
                type = 1
            }
        )
    }
    
    # Convert to JSON - send single object, not array
    $jsonBody = $command | ConvertTo-Json -Depth 10 -Compress
    
    if (-not [string]::IsNullOrEmpty($GuildId)) {
        $url = "https://discord.com/api/v10/applications/$ApplicationId/guilds/$GuildId/commands"
        Write-Host "   Registering to guild (server): $GuildId" -ForegroundColor Gray
    } else {
        $url = "https://discord.com/api/v10/applications/$ApplicationId/commands"
        Write-Host "   Registering globally" -ForegroundColor Gray
    }
    
    $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
    Write-Host "✅ Commands registered successfully!" -ForegroundColor Green
    Write-Host "   Command ID: $($response.id)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Failed to register commands!" -ForegroundColor Red
    Write-Host "   Error: $_" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorStream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorStream)
        $errorBodyText = $reader.ReadToEnd()
        $reader.Close()
        $errorStream.Close()
        
        Write-Host "   Status Code: $statusCode" -ForegroundColor Red
        Write-Host "   Error Details: $errorBodyText" -ForegroundColor Red
        
        if ($statusCode -eq 403) {
            Write-Host ""
            Write-Host "   Common fixes:" -ForegroundColor Yellow
            Write-Host "   1. Make sure bot is added to your server" -ForegroundColor White
            Write-Host "   2. Use OAuth2 URL Generator with 'bot' and 'applications.commands' scopes" -ForegroundColor White
            Write-Host "   3. Try registering to a specific guild (server) first" -ForegroundColor White
        }
    }
    exit 1
}
Write-Host ""

# Step 6: Set interaction endpoint
if (-not [string]::IsNullOrEmpty($FunctionAppUrl)) {
    Write-Host "Step 6: Setting Interaction Endpoint..." -ForegroundColor Yellow
    try {
        $interactionUrl = "$FunctionAppUrl/api/DiscordBot"
        $interactionBody = @{
            url = $interactionUrl
        } | ConvertTo-Json -Compress
        
        $interactionHeaders = @{
            "Authorization" = "Bot $BotToken"
            "Content-Type" = "application/json"
        }
        
        $interactionEndpointUrl = "https://discord.com/api/v10/applications/$ApplicationId/interactions-endpoint-url"
        Invoke-RestMethod -Uri $interactionEndpointUrl -Method Put -Headers $interactionHeaders -Body $interactionBody -ErrorAction Stop
        Write-Host "✅ Interaction endpoint set to: $interactionUrl" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Could not set interaction endpoint automatically" -ForegroundColor Yellow
        Write-Host "   Set it manually at:" -ForegroundColor Yellow
        Write-Host "   https://discord.com/developers/applications/$ApplicationId/interactions" -ForegroundColor Cyan
        Write-Host "   URL: $interactionUrl" -ForegroundColor Gray
    }
    Write-Host ""
}

# Step 7: Final verification
Write-Host "Step 7: Final Verification..." -ForegroundColor Yellow
try {
    if (-not [string]::IsNullOrEmpty($GuildId)) {
        $url = "https://discord.com/api/v10/applications/$ApplicationId/guilds/$GuildId/commands"
    } else {
        $url = "https://discord.com/api/v10/applications/$ApplicationId/commands"
    }
    
    $finalCommands = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop
    $valheimCmd = $finalCommands | Where-Object { $_.name -eq "valheim" }
    
    if ($valheimCmd) {
        Write-Host "✅ Verification successful!" -ForegroundColor Green
        Write-Host ""
        Write-Host "🎉 Setup Complete!" -ForegroundColor Green
        Write-Host ""
        Write-Host "You can now use these commands in Discord:" -ForegroundColor Cyan
        Write-Host "  /valheim start  - Start the server" -ForegroundColor White
        Write-Host "  /valheim stop   - Stop the server" -ForegroundColor White
        Write-Host "  /valheim status - Check server status" -ForegroundColor White
        Write-Host ""
        if (-not [string]::IsNullOrEmpty($GuildId)) {
            Write-Host "💡 Commands are registered to your server (appear immediately)" -ForegroundColor Gray
        } else {
            Write-Host "💡 Commands are registered globally (may take up to 1 hour to appear)" -ForegroundColor Gray
        }
    } else {
        Write-Host "⚠️  /valheim command not found after registration" -ForegroundColor Yellow
        Write-Host "   This might be a timing issue. Try again in a few seconds." -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠️  Could not verify commands: $_" -ForegroundColor Yellow
}

Write-Host ""
