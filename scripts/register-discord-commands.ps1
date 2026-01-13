# Script to register Discord slash commands
# This script registers the /valheim commands with Discord

param(
    [Parameter(Mandatory=$true)]
    [string]$ApplicationId,
    
    [Parameter(Mandatory=$true)]
    [string]$BotToken,
    
    [Parameter(Mandatory=$false)]
    [string]$FunctionAppUrl = "",
    
    [Parameter(Mandatory=$false)]
    [string]$GuildId = ""  # Optional: Register to specific guild (faster, for testing)
)

Write-Host "Discord Slash Command Registration" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
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

# Trim whitespace from token (common issue)
$BotToken = $BotToken.Trim()

# Remove "Bot " prefix if user accidentally included it
if ($BotToken.StartsWith("Bot ", [System.StringComparison]::OrdinalIgnoreCase)) {
    $BotToken = $BotToken.Substring(4).Trim()
    Write-Host "⚠️  Removed 'Bot ' prefix from token" -ForegroundColor Yellow
}

# Command definition - single command object (not array)
$command = @{
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
            type = 1  # SUB_COMMAND
        },
        @{
            name = "status"
            description = "Check server status"
            type = 1  # SUB_COMMAND
        }
    )
}

# Convert to JSON - send single object, not array
$jsonBody = $command | ConvertTo-Json -Depth 10 -Compress

Write-Host "Registering slash commands..." -ForegroundColor Yellow
Write-Host "Application ID: $ApplicationId" -ForegroundColor Gray
Write-Host ""

try {
    # Register commands using Discord API
    # Build Authorization header - ensure proper formatting (exactly like Postman)
    $authHeader = "Bot $BotToken"
    
    # Use guild-specific endpoint if GuildId is provided (faster, for testing)
    # Otherwise use global endpoint (takes up to 1 hour to propagate)
    if (-not [string]::IsNullOrEmpty($GuildId)) {
        $GuildId = $GuildId.Trim()
        $url = "https://discord.com/api/v10/applications/$ApplicationId/guilds/$GuildId/commands"
        Write-Host "Registering to guild (server): $GuildId" -ForegroundColor Cyan
        Write-Host "(Guild-specific commands appear immediately)" -ForegroundColor Gray
    } else {
        $url = "https://discord.com/api/v10/applications/$ApplicationId/commands"
        Write-Host "Registering globally (takes up to 1 hour to propagate)" -ForegroundColor Cyan
    }
    
    Write-Host "POST $url" -ForegroundColor Gray
    Write-Host ""
    
    # Debug: Show the actual JSON being sent (first 200 chars)
    $jsonPreview = if ($jsonBody.Length -gt 200) { $jsonBody.Substring(0, 200) + "..." } else { $jsonBody }
    Write-Host "Request body: $jsonPreview" -ForegroundColor DarkGray
    Write-Host ""
    
    # Create headers using System.Net.Http.Headers.HttpRequestHeaders approach
    # This ensures headers are set exactly as Discord expects
    $headers = @{}
    $headers["Authorization"] = $authHeader
    $headers["Content-Type"] = "application/json"
    
    # Use WebRequest for more control (similar to Postman)
    $request = [System.Net.HttpWebRequest]::Create($url)
    $request.Method = "POST"
    $request.ContentType = "application/json"
    $request.Headers.Add("Authorization", $authHeader)
    
    # Write JSON body to request stream
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    $request.ContentLength = $bodyBytes.Length
    $requestStream = $request.GetRequestStream()
    $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
    $requestStream.Close()
    
    # Get response
    try {
        $response = $request.GetResponse()
        $responseStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream)
        $responseBody = $reader.ReadToEnd()
        $reader.Close()
        $responseStream.Close()
        $response.Close()
        
        # Parse JSON response
        $responseObj = $responseBody | ConvertFrom-Json
    } catch {
        # If there's an error, try Invoke-RestMethod as fallback
        Write-Host "⚠️  WebRequest failed, trying Invoke-RestMethod..." -ForegroundColor Yellow
        $responseObj = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $jsonBody -ErrorAction Stop
    }
    
    $response = $responseObj
    
    Write-Host "✅ Successfully registered slash commands!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Registered command: /valheim" -ForegroundColor Green
    Write-Host "  - /valheim start" -ForegroundColor White
    Write-Host "  - /valheim stop" -ForegroundColor White
    Write-Host "  - /valheim status" -ForegroundColor White
    Write-Host ""
    
    # Set interaction endpoint URL if Function App URL is provided
    if (-not [string]::IsNullOrEmpty($FunctionAppUrl)) {
        Write-Host "Setting interaction endpoint URL..." -ForegroundColor Yellow
        
        $interactionUrl = "$FunctionAppUrl/api/DiscordBot"
        $interactionBody = @{
            url = $interactionUrl
        } | ConvertTo-Json -Compress
        
        $interactionHeaders = @{
            "Authorization" = "Bot $BotToken"
            "Content-Type" = "application/json"
        }
        
        $interactionEndpointUrl = "https://discord.com/api/v10/applications/$ApplicationId/interactions-endpoint-url"
        
        try {
            Invoke-RestMethod -Uri $interactionEndpointUrl -Method Put -Headers $interactionHeaders -Body $interactionBody -ErrorAction Stop
            Write-Host "✅ Interaction endpoint URL set to: $interactionUrl" -ForegroundColor Green
        } catch {
            Write-Host "⚠️  Warning: Failed to set interaction endpoint URL: $_" -ForegroundColor Yellow
            Write-Host "   You can set it manually in Discord Developer Portal:" -ForegroundColor Yellow
            Write-Host "   - Go to https://discord.com/developers/applications/$ApplicationId/interactions" -ForegroundColor Gray
            Write-Host "   - Set Interaction Endpoint URL to: $interactionUrl" -ForegroundColor Gray
        }
    } else {
        Write-Host "⚠️  Function App URL not provided. Set interaction endpoint manually:" -ForegroundColor Yellow
        Write-Host "   1. Go to https://discord.com/developers/applications/$ApplicationId/interactions" -ForegroundColor Gray
        Write-Host "   2. Set Interaction Endpoint URL to your Function App URL + /api/DiscordBot" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "✅ Setup complete! You can now use /valheim commands in Discord." -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error registering commands: $_" -ForegroundColor Red
    Write-Host ""
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        
        # Try to read error response body
        $errorStream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorStream)
        $errorBodyText = $reader.ReadToEnd()
        $reader.Close()
        $errorStream.Close()
        
        $errorBody = $null
        try {
            $errorBody = $errorBodyText | ConvertFrom-Json -ErrorAction Stop
        } catch {
            # If JSON parsing fails, use raw text
            Write-Host "Error Response: $errorBodyText" -ForegroundColor Red
        }
        
        Write-Host "Status Code: $statusCode" -ForegroundColor Red
        
        if ($errorBody) {
            Write-Host "Error Code: $($errorBody.code)" -ForegroundColor Red
            Write-Host "Error Message: $($errorBody.message)" -ForegroundColor Red
        }
        
        if ($statusCode -eq 401) {
            Write-Host ""
            Write-Host "Authentication failed. Common issues:" -ForegroundColor Yellow
            Write-Host "  1. Bot Token is incorrect or expired" -ForegroundColor White
            Write-Host "  2. Bot Token format is wrong (should start with the token, not 'Bot ' prefix)" -ForegroundColor White
            Write-Host "  3. Bot hasn't been added to your Discord server" -ForegroundColor White
            Write-Host ""
            Write-Host "To get your Bot Token:" -ForegroundColor Cyan
            Write-Host "  1. Go to https://discord.com/developers/applications/$ApplicationId/bot" -ForegroundColor Gray
            Write-Host "  2. Click 'Reset Token' or 'Copy' to get your bot token" -ForegroundColor Gray
            Write-Host "  3. Make sure the token starts with letters/numbers (not 'Bot ')" -ForegroundColor Gray
        } elseif ($statusCode -eq 403) {
            Write-Host ""
            Write-Host "Forbidden. Common issues:" -ForegroundColor Yellow
            Write-Host "  1. Bot doesn't have 'applications.commands' scope" -ForegroundColor White
            Write-Host "  2. Bot hasn't been added to your Discord server" -ForegroundColor White
            Write-Host "  3. Missing 'bot' scope in OAuth2 URL" -ForegroundColor White
            Write-Host "  4. Bot token is invalid or expired" -ForegroundColor White
            Write-Host ""
            Write-Host "Debugging info:" -ForegroundColor Cyan
            Write-Host "  - Token length: $($BotToken.Length) characters" -ForegroundColor Gray
            Write-Host "  - Token starts with: $($BotToken.Substring(0, [Math]::Min(10, $BotToken.Length)))..." -ForegroundColor Gray
            Write-Host "  - Authorization header: Bot [REDACTED]" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Compare with Postman:" -ForegroundColor Yellow
            Write-Host "  - In Postman, set header 'Authorization' to: Bot $($BotToken.Substring(0, [Math]::Min(20, $BotToken.Length)))..." -ForegroundColor White
            Write-Host "  - Make sure there's exactly one space between 'Bot' and the token" -ForegroundColor White
        } elseif ($statusCode -eq 500 -or $statusCode -eq 503) {
            Write-Host ""
            Write-Host "Discord API Error. This might be:" -ForegroundColor Yellow
            Write-Host "  1. Temporary Discord API issue (try again in a few minutes)" -ForegroundColor White
            Write-Host "  2. Rate limiting (wait a bit and try again)" -ForegroundColor White
            Write-Host "  3. Bot not properly configured" -ForegroundColor White
        } elseif ($statusCode -eq 404) {
            Write-Host ""
            Write-Host "Application not found. Check:" -ForegroundColor Yellow
            Write-Host "  1. Application ID is correct" -ForegroundColor White
            Write-Host "  2. You have access to this application" -ForegroundColor White
        }
        
        if ($errorBody) {
            Write-Host ""
            Write-Host "Error details: $($errorBody | ConvertTo-Json)" -ForegroundColor Red
        }
    }
    
    exit 1
}
