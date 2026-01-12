# Register Discord Slash Commands
# Run this script after creating your Discord bot application

param(
    [Parameter(Mandatory=$true)]
    [string]$ApplicationId,
    
    [Parameter(Mandatory=$true)]
    [string]$BotToken
)

$headers = @{
    "Authorization" = "Bot $BotToken"
    "Content-Type" = "application/json"
}

$commands = @(
    @{
        name = "valheim"
        description = "Control the Valheim server"
        options = @(
            @{
                name = "start"
                description = "Start the Valheim server"
                type = 1  # SUB_COMMAND
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
) | ConvertTo-Json -Depth 10

$uri = "https://discord.com/api/v10/applications/$ApplicationId/commands"

Write-Host "Registering Discord commands..." -ForegroundColor Yellow
Write-Host "Application ID: $ApplicationId" -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $commands
    Write-Host "Commands registered successfully!" -ForegroundColor Green
    Write-Host ($response | ConvertTo-Json -Depth 10)
} catch {
    Write-Host "Error registering commands: $_" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
    exit 1
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Go to https://discord.com/developers/applications/$ApplicationId/oauth2/url-generator"
Write-Host "2. Select scopes: 'bot' and 'applications.commands'"
Write-Host "3. Select permissions: 'Send Messages' and 'Use Slash Commands'"
Write-Host "4. Copy the generated URL and open it in a browser to invite the bot to your server"
Write-Host "5. Set the interaction endpoint URL in Discord Developer Portal:"
Write-Host "   https://discord.com/developers/applications/$ApplicationId/interactions"
