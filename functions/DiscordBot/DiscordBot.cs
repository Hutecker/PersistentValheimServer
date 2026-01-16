using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Azure.Core;
using Azure.Identity;
using Azure;
using Azure.ResourceManager;
using Azure.ResourceManager.ContainerInstance;
using Azure.ResourceManager.ContainerInstance.Models;
using Azure.ResourceManager.Resources;
using Azure.ResourceManager.Storage;
using Azure.ResourceManager.Storage.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using NSec.Cryptography;

namespace ValheimServerFunctions;

public class DiscordBot
{
    private readonly ILogger _logger;
    private static readonly DefaultAzureCredential Credential = new();
    private static ArmClient? _armClient;
    private static readonly Dictionary<string, ServerState> _serverStates = new();

    private class ServerState
    {
        public string Status { get; set; } = "stopped";
        public DateTime? StartedAt { get; set; }
        public DateTime? AutoShutdownTime { get; set; }
    }

    public DiscordBot(ILoggerFactory loggerFactory)
    {
        _logger = loggerFactory.CreateLogger<DiscordBot>();
        InitializeClients();
    }

    private void InitializeClients()
    {
        _armClient = new ArmClient(Credential);
    }

    [Function("DiscordBot")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequestData req,
        FunctionContext executionContext)
    {
        _logger.LogInformation("Discord bot function processed a request.");

        try
        {
            var body = await new StreamReader(req.Body).ReadToEndAsync();
            
            JsonElement data;
            try
            {
                data = JsonSerializer.Deserialize<JsonElement>(body);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to parse request body as JSON");
                var badRequestResponse = req.CreateResponse(HttpStatusCode.BadRequest);
                badRequestResponse.Headers.Add("Content-Type", "application/json");
                await badRequestResponse.WriteStringAsync(JsonSerializer.Serialize(new { error = "Invalid JSON" }));
                return badRequestResponse;
            }
            
            bool isPing = false;
            if (data.TryGetProperty("type", out var typeElement))
            {
                var interactionType = typeElement.GetInt32();
                isPing = (interactionType == 1);
            }
            
            if (!isPing && !VerifyDiscordSignature(req, body))
            {
                _logger.LogWarning("Invalid Discord signature - request rejected");
                var unauthorizedResponse = req.CreateResponse(HttpStatusCode.Unauthorized);
                unauthorizedResponse.Headers.Add("Content-Type", "application/json");
                await unauthorizedResponse.WriteStringAsync(JsonSerializer.Serialize(new { error = "Unauthorized" }));
                return unauthorizedResponse;
            }
            
            if (isPing)
            {
                _logger.LogInformation("Received PING request (endpoint verification)");
                if (!VerifyDiscordSignature(req, body))
                {
                    _logger.LogWarning("PING signature verification failed, but allowing through for endpoint verification");
                }
            }

            var responseData = await HandleDiscordInteractionAsync(data);
            var response = req.CreateResponse(HttpStatusCode.OK);
            response.Headers.Add("Content-Type", "application/json");

            await response.WriteStringAsync(JsonSerializer.Serialize(responseData));
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing request");
            var errorResponse = req.CreateResponse(HttpStatusCode.InternalServerError);
            errorResponse.Headers.Add("Content-Type", "application/json");
            await errorResponse.WriteStringAsync(JsonSerializer.Serialize(new { error = ex.Message }));
            return errorResponse;
        }
    }

    private bool VerifyDiscordSignature(HttpRequestData req, string body)
    {
        try
        {
            if (!req.Headers.TryGetValues("X-Signature-Ed25519", out var signatureHeader) ||
                !req.Headers.TryGetValues("X-Signature-Timestamp", out var timestampHeader))
            {
                _logger.LogWarning("Missing Discord signature headers - request rejected");
                return false;
            }

            var signatureHex = signatureHeader.FirstOrDefault();
            var timestamp = timestampHeader.FirstOrDefault();

            if (string.IsNullOrEmpty(signatureHex) || string.IsNullOrEmpty(timestamp))
            {
                _logger.LogWarning("Empty Discord signature headers - request rejected");
                return false;
            }

            var publicKeyHex = Environment.GetEnvironmentVariable("DISCORD_PUBLIC_KEY");

            if (string.IsNullOrEmpty(publicKeyHex))
            {
                _logger.LogWarning("Discord public key not configured - signature verification skipped");
                return true;
            }

            var signature = HexStringToBytes(signatureHex);
            var publicKey = HexStringToBytes(publicKeyHex);

            if (signature == null || signature.Length != 64 || publicKey == null || publicKey.Length != 32)
            {
                _logger.LogWarning("Invalid signature or public key format");
                return false;
            }

            var messageBytes = Encoding.UTF8.GetBytes(timestamp + body);
            
            try
            {
                var algorithm = SignatureAlgorithm.Ed25519;
                var publicKeyBlob = PublicKey.Import(algorithm, publicKey, KeyBlobFormat.RawPublicKey);
                
                var isValid = algorithm.Verify(publicKeyBlob, messageBytes, signature);
                
                if (!isValid)
                {
                    _logger.LogWarning("Discord signature verification failed - request rejected");
                    return false;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during ed25519 signature verification");
                return false;
            }

            _logger.LogInformation("Discord signature verified successfully");
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error verifying Discord signature");
            return false;
        }
    }

    private static byte[]? HexStringToBytes(string hex)
    {
        try
        {
            if (hex.Length % 2 != 0)
                return null;
            
            var bytes = new byte[hex.Length / 2];
            for (int i = 0; i < bytes.Length; i++)
            {
                bytes[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            }
            return bytes;
        }
        catch
        {
            return null;
        }
    }

    private async Task<object> HandleDiscordInteractionAsync(JsonElement data)
    {
        if (!data.TryGetProperty("type", out var typeElement))
            return new { type = 1 }; // PONG

        var interactionType = typeElement.GetInt32();

        if (interactionType == 1) // PING
            return new { type = 1 }; // PONG

        if (interactionType == 2) // APPLICATION_COMMAND
        {
            if (!data.TryGetProperty("data", out var dataElement))
                return new { type = 4, data = new { content = "Unknown command" } };

            if (!dataElement.TryGetProperty("name", out var nameElement))
                return new { type = 4, data = new { content = "Unknown command" } };

            var commandName = nameElement.GetString();
            if (commandName != "valheim")
                return new { type = 4, data = new { content = "Unknown command" } };

            if (!dataElement.TryGetProperty("options", out var optionsElement) || optionsElement.ValueKind != JsonValueKind.Array)
                return new { type = 4, data = new { content = "No subcommand provided" } };

            var options = optionsElement.EnumerateArray().ToList();
            if (options.Count == 0)
                return new { type = 4, data = new { content = "No subcommand provided" } };

            var subcommand = options[0].GetProperty("name").GetString();

            return subcommand switch
            {
                "start" => await HandleStartCommandAsync(data),
                "stop" => HandleStopCommand(),
                "status" => HandleStatusCommand(),
                _ => new { type = 4, data = new { content = "Unknown subcommand" } }
            };
        }

        return new { type = 1 }; // PONG
    }

    private async Task<object> HandleStartCommandAsync(JsonElement interactionData)
    {
        try
        {
            if (!interactionData.TryGetProperty("token", out var tokenElement) ||
                !interactionData.TryGetProperty("application_id", out var appIdElement))
            {
                return new
                {
                    type = 4,
                    data = new
                    {
                        content = "[ERROR] Missing interaction data",
                        flags = 64
                    }
                };
            }

            var interactionToken = tokenElement.GetString();
            var applicationId = appIdElement.GetString();

            _ = Task.Run(async () =>
            {
                try
                {
                    await StartServerAndNotify(interactionData, applicationId, interactionToken);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error in background server start task");
                    await SendFollowUpMessage(applicationId, interactionToken, $"[ERROR] {ex.Message}");
                }
            });

            return new
            {
                type = 5
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in start command");
            return new
            {
                type = 4,
                data = new
                {
                    content = $"[ERROR] Error starting server: {ex.Message}",
                    flags = 64
                }
            };
        }
    }

    private object HandleStopCommand()
    {
        try
        {
            var (success, message) = StopServer();
            return new
            {
                type = 4,
                data = new
                {
                    content = message,
                    flags = success ? 0 : 64
                }
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in stop command");
            return new
            {
                type = 4,
                data = new
                {
                    content = $"Error stopping server: {ex.Message}",
                    flags = 64
                }
            };
        }
    }

    private object HandleStatusCommand()
    {
        try
        {
            var status = GetServerStatus();
            var stateKey = Environment.GetEnvironmentVariable("CONTAINER_GROUP_NAME") ?? "valheim-server";
            
            if (status == "running")
            {
                if (_serverStates.TryGetValue(stateKey, out var state) && state.StartedAt.HasValue && state.AutoShutdownTime.HasValue)
                {
                    var timeRemaining = state.AutoShutdownTime.Value - DateTime.UtcNow;
                    if (timeRemaining.TotalSeconds > 0)
                    {
                        var mins = (int)timeRemaining.TotalMinutes;
                        return new
                        {
                            type = 4,
                            data = new { content = $"[RUNNING] Server is **RUNNING**\nAuto-shutdown in {mins} minutes" }
                        };
                    }
                    return new
                    {
                        type = 4,
                        data = new { content = "[RUNNING] Server is **RUNNING**\n[WARNING] Auto-shutdown time has passed" }
                    };
                }
                return new
                {
                    type = 4,
                    data = new { content = "[RUNNING] Server is **RUNNING**" }
                };
            }

            if (status == "stopped")
            {
                return new
                {
                    type = 4,
                    data = new { content = "[STOPPED] Server is **STOPPED**" }
                };
            }

            return new
            {
                type = 4,
                data = new { content = $"[UNKNOWN] Server status: **{status.ToUpper()}**" }
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in status command");
            return new
            {
                type = 4,
                data = new { content = $"Error checking status: {ex.Message}" }
            };
        }
    }

    private string GetServerStatus()
    {
        try
        {
            var subscriptionId = Environment.GetEnvironmentVariable("SUBSCRIPTION_ID");
            var resourceGroupName = Environment.GetEnvironmentVariable("RESOURCE_GROUP_NAME");
            var containerGroupName = Environment.GetEnvironmentVariable("CONTAINER_GROUP_NAME");

            if (_armClient == null || string.IsNullOrEmpty(subscriptionId) || string.IsNullOrEmpty(resourceGroupName) || string.IsNullOrEmpty(containerGroupName))
                return "unknown";

            var subscription = _armClient.GetSubscriptionResource(SubscriptionResource.CreateResourceIdentifier(subscriptionId));
            var resourceGroup = subscription.GetResourceGroup(resourceGroupName).Value;
            var containerGroup = resourceGroup.GetContainerGroup(containerGroupName);
            
            var containerGroupResource = containerGroup.Value;
            var containerGroupData = containerGroupResource.Get().Value;
            
            if (containerGroupData.Data.Containers != null && containerGroupData.Data.Containers.Count > 0)
            {
                var container = containerGroupData.Data.Containers[0];
                var state = container.InstanceView?.CurrentState?.State ?? "Unknown";
                return state.ToLower();
            }

            return "stopped";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking server status");
            return "unknown";
        }
    }

    private (bool Success, string Message) StartServer()
    {
        try
        {
            var subscriptionId = Environment.GetEnvironmentVariable("SUBSCRIPTION_ID");
            var resourceGroupName = Environment.GetEnvironmentVariable("RESOURCE_GROUP_NAME");
            var containerGroupName = Environment.GetEnvironmentVariable("CONTAINER_GROUP_NAME");

            if (_armClient == null || string.IsNullOrEmpty(subscriptionId) || string.IsNullOrEmpty(resourceGroupName) || string.IsNullOrEmpty(containerGroupName))
                return (false, "Azure clients not initialized");

            var subscription = _armClient.GetSubscriptionResource(SubscriptionResource.CreateResourceIdentifier(subscriptionId));
            var resourceGroup = subscription.GetResourceGroup(resourceGroupName).Value;

            try
            {
                var containerGroup = resourceGroup.GetContainerGroup(containerGroupName);
                var containerGroupResource = containerGroup.Value;
                var existingContainerGroupData = containerGroupResource.Get().Value;
                
                if (existingContainerGroupData.Data.Containers != null && existingContainerGroupData.Data.Containers.Count > 0)
                {
                    var existingContainer = existingContainerGroupData.Data.Containers[0];
                    var state = existingContainer.InstanceView?.CurrentState?.State ?? "Unknown";
                    
                    if (state.Equals("Running", StringComparison.OrdinalIgnoreCase))
                        return (true, "Server is already running!");

                    if (state.Equals("Stopped", StringComparison.OrdinalIgnoreCase) || state.Equals("Terminated", StringComparison.OrdinalIgnoreCase))
                    {
                        _logger.LogInformation("Deleting stopped container group before recreating...");
                        containerGroupResource.Delete(WaitUntil.Completed);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogInformation($"Container group doesn't exist yet: {ex.Message}");
            }

            var serverPassword = Environment.GetEnvironmentVariable("SERVER_PASSWORD");
            if (string.IsNullOrEmpty(serverPassword))
            {
                return (false, "SERVER_PASSWORD app setting not configured");
            }
            var serverName = Environment.GetEnvironmentVariable("SERVER_NAME") ?? "Valheim Server";
            var storageAccountName = Environment.GetEnvironmentVariable("STORAGE_ACCOUNT_NAME");
            var fileShareName = Environment.GetEnvironmentVariable("FILE_SHARE_NAME");
            var location = Environment.GetEnvironmentVariable("LOCATION") ?? "eastus";

            if (string.IsNullOrEmpty(storageAccountName) || string.IsNullOrEmpty(fileShareName))
                return (false, "Storage account configuration missing");

            // ACI doesn't support managed identity for Azure Files mounts, so retrieve key using managed identity
            var storageAccount = resourceGroup.GetStorageAccount(storageAccountName).Value;
            var keys = storageAccount.GetKeys();
            var storageKey = keys.First().Value;

            var azureLocation = new AzureLocation(location);
            var container = new ContainerInstanceContainer("valheim-server", "lloesche/valheim-server:latest", 
                new ContainerResourceRequirements(new ContainerResourceRequestsContent(2.0, 4.0)))
            {
                EnvironmentVariables =
                {
                    new ContainerEnvironmentVariable("SERVER_NAME") { Value = serverName },
                    new ContainerEnvironmentVariable("WORLD_NAME") { Value = "Dedicated" },
                    new ContainerEnvironmentVariable("SERVER_PASS") { SecureValue = serverPassword },
                    new ContainerEnvironmentVariable("SERVER_PUBLIC") { Value = "1" },
                    new ContainerEnvironmentVariable("BACKUPS") { Value = "1" },
                    new ContainerEnvironmentVariable("BACKUPS_RETENTION_DAYS") { Value = "7" },
                    new ContainerEnvironmentVariable("UPDATE_CRON") { Value = "0 4 * * *" }
                },
                VolumeMounts =
                {
                    new ContainerVolumeMount("world-data", "/config")
                },
                Ports =
                {
                    new ContainerPort(2456) { Protocol = ContainerNetworkProtocol.Udp },
                    new ContainerPort(2457) { Protocol = ContainerNetworkProtocol.Udp },
                    new ContainerPort(2458) { Protocol = ContainerNetworkProtocol.Udp }
                }
            };

            var ipAddressPorts = new List<ContainerGroupPort>
            {
                new ContainerGroupPort(2456) { Protocol = ContainerGroupNetworkProtocol.Udp },
                new ContainerGroupPort(2457) { Protocol = ContainerGroupNetworkProtocol.Udp },
                new ContainerGroupPort(2458) { Protocol = ContainerGroupNetworkProtocol.Udp }
            };

            var ipAddress = new ContainerGroupIPAddress(ipAddressPorts, ContainerGroupIPAddressType.Public)
            {
                DnsNameLabel = $"valheim-{GetHashString(resourceGroupName).Substring(0, 8)}"
            };

            var containerGroupData = new ContainerGroupData(azureLocation, new[] { container }, ContainerInstanceOperatingSystemType.Linux)
            {
                RestartPolicy = ContainerGroupRestartPolicy.Never,
                Volumes =
                {
                    new ContainerVolume("world-data")
                    {
                        AzureFile = new ContainerInstanceAzureFileVolume(fileShareName, storageAccountName)
                        {
                            StorageAccountKey = storageKey
                        }
                    }
                },
                IPAddress = ipAddress
            };

            _logger.LogInformation("Creating container group...");
            resourceGroup.GetContainerGroups().CreateOrUpdate(WaitUntil.Started, containerGroupName, containerGroupData);

            var stateKey = containerGroupName;
            var autoShutdownMinutes = int.Parse(Environment.GetEnvironmentVariable("AUTO_SHUTDOWN_MINUTES") ?? "120");
            _serverStates[stateKey] = new ServerState
            {
                Status = "starting",
                StartedAt = DateTime.UtcNow,
                AutoShutdownTime = DateTime.UtcNow.AddMinutes(autoShutdownMinutes)
            };

            return (true, $"Server is starting! It will automatically shut down in {autoShutdownMinutes} minutes.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error starting server");
            return (false, $"Error starting server: {ex.Message}");
        }
    }

    private async Task StartServerAndNotify(JsonElement interactionData, string? applicationId, string? interactionToken)
    {
        try
        {
            if (string.IsNullOrEmpty(applicationId) || string.IsNullOrEmpty(interactionToken))
            {
                _logger.LogError("Missing interaction token or application ID");
                return;
            }

            await SendFollowUpMessage(applicationId, interactionToken, "[STARTING] Server is starting... This may take 2-3 minutes.");

            var (success, message) = StartServer();
            
            if (!success)
            {
                await SendFollowUpMessage(applicationId, interactionToken, $"[ERROR] {message}");
                return;
            }

            var subscriptionId = Environment.GetEnvironmentVariable("SUBSCRIPTION_ID");
            var resourceGroupName = Environment.GetEnvironmentVariable("RESOURCE_GROUP_NAME");
            var containerGroupName = Environment.GetEnvironmentVariable("CONTAINER_GROUP_NAME");
            var maxWaitTime = TimeSpan.FromMinutes(5);
            var pollInterval = TimeSpan.FromSeconds(10);
            var startTime = DateTime.UtcNow;
            string? serverIp = null;
            string? serverFqdn = null;

            _logger.LogInformation("Polling for server to be ready...");

            while (DateTime.UtcNow - startTime < maxWaitTime)
            {
                try
                {
                    if (_armClient == null || string.IsNullOrEmpty(subscriptionId) || 
                        string.IsNullOrEmpty(resourceGroupName) || string.IsNullOrEmpty(containerGroupName))
                    {
                        await SendFollowUpMessage(applicationId, interactionToken, "[ERROR] Azure clients not initialized");
                        return;
                    }

                    var subscription = _armClient.GetSubscriptionResource(SubscriptionResource.CreateResourceIdentifier(subscriptionId));
                    var resourceGroup = subscription.GetResourceGroup(resourceGroupName).Value;
                    var containerGroup = resourceGroup.GetContainerGroup(containerGroupName);
                    var containerGroupResource = containerGroup.Value;
                    var containerGroupData = containerGroupResource.Get().Value;
                    
                    string? state = null;
                    if (containerGroupData.Data.Containers != null && containerGroupData.Data.Containers.Count > 0)
                    {
                        var container = containerGroupData.Data.Containers[0];
                        state = container.InstanceView?.CurrentState?.State;
                    }

                    if (state != null && state.Equals("Running", StringComparison.OrdinalIgnoreCase))
                    {
                        var ipAddressData = containerGroupData.Data.IPAddress;
                        if (ipAddressData != null)
                        {
                            serverIp = ipAddressData.IP?.ToString();
                            serverFqdn = ipAddressData.Fqdn;
                        }

                        var autoShutdownMinutes = int.Parse(Environment.GetEnvironmentVariable("AUTO_SHUTDOWN_MINUTES") ?? "120");
                        var stateKey = containerGroupName;
                        _serverStates[stateKey] = new ServerState
                        {
                            Status = "running",
                            StartedAt = DateTime.UtcNow,
                            AutoShutdownTime = DateTime.UtcNow.AddMinutes(autoShutdownMinutes)
                        };

                        var readyMessage = new StringBuilder();
                        readyMessage.AppendLine("[SUCCESS] **Server is ready!**");
                        readyMessage.AppendLine();
                        
                        if (!string.IsNullOrEmpty(serverIp))
                        {
                            readyMessage.AppendLine($"**IP Address:** `{serverIp}`");
                        }
                        
                        if (!string.IsNullOrEmpty(serverFqdn))
                        {
                            readyMessage.AppendLine($"**FQDN:** `{serverFqdn}`");
                        }
                        
                        readyMessage.AppendLine();
                        readyMessage.AppendLine($"Auto-shutdown in {autoShutdownMinutes} minutes");
                        readyMessage.AppendLine();
                        readyMessage.AppendLine("You can now connect to the server in Valheim!");

                        await SendFollowUpMessage(applicationId, interactionToken, readyMessage.ToString());
                        _logger.LogInformation($"Server is ready! IP: {serverIp}");
                        return;
                    }
                    else if (state != null && (state.Equals("Failed", StringComparison.OrdinalIgnoreCase) || state.Equals("Stopped", StringComparison.OrdinalIgnoreCase)))
                    {
                        await SendFollowUpMessage(applicationId, interactionToken, 
                            $"[ERROR] Server failed to start. Status: {state}");
                        return;
                    }

                    await Task.Delay(pollInterval);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error polling server status, will retry");
                    await Task.Delay(pollInterval);
                }
            }

            await SendFollowUpMessage(applicationId, interactionToken, 
                "[TIMEOUT] Server is taking longer than expected to start. Please check the status with `/valheim status`");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in StartServerAndNotify");
            try
            {
                if (interactionData.TryGetProperty("token", out var tokenElement) &&
                    interactionData.TryGetProperty("application_id", out var appIdElement))
                {
                    await SendFollowUpMessage(appIdElement.GetString(), tokenElement.GetString(), 
                        $"[ERROR] {ex.Message}");
                }
            }
            catch
            {
            }
        }
    }

    private async Task SendFollowUpMessage(string? applicationId, string? interactionToken, string content)
    {
        if (string.IsNullOrEmpty(applicationId) || string.IsNullOrEmpty(interactionToken))
        {
            _logger.LogWarning("Cannot send follow-up message: missing application ID or token");
            return;
        }

        try
        {
            using var httpClient = new HttpClient();
            var webhookUrl = $"https://discord.com/api/v10/webhooks/{applicationId}/{interactionToken}";
            
            var payload = new
            {
                content = content
            };

            var json = JsonSerializer.Serialize(payload);
            var contentData = new StringContent(json, Encoding.UTF8, "application/json");

            var response = await httpClient.PostAsync(webhookUrl, contentData);
            
            if (!response.IsSuccessStatusCode)
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                _logger.LogError($"Failed to send Discord follow-up message. Status: {response.StatusCode}, Error: {errorContent}");
            }
            else
            {
                _logger.LogInformation("Successfully sent Discord follow-up message");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Exception sending Discord follow-up message");
        }
    }

    private (bool Success, string Message) StopServer()
    {
        try
        {
            var subscriptionId = Environment.GetEnvironmentVariable("SUBSCRIPTION_ID");
            var resourceGroupName = Environment.GetEnvironmentVariable("RESOURCE_GROUP_NAME");
            var containerGroupName = Environment.GetEnvironmentVariable("CONTAINER_GROUP_NAME");

            if (_armClient == null || string.IsNullOrEmpty(subscriptionId) || string.IsNullOrEmpty(resourceGroupName) || string.IsNullOrEmpty(containerGroupName))
                return (false, "Azure clients not initialized");

            var subscription = _armClient.GetSubscriptionResource(SubscriptionResource.CreateResourceIdentifier(subscriptionId));
            var resourceGroup = subscription.GetResourceGroup(resourceGroupName).Value;
            var containerGroup = resourceGroup.GetContainerGroup(containerGroupName);
            var containerGroupResource = containerGroup.Value;
            var containerGroupData = containerGroupResource.Get().Value;
            
            string? state = null;
            if (containerGroupData.Data.Containers != null && containerGroupData.Data.Containers.Count > 0)
            {
                var container = containerGroupData.Data.Containers[0];
                state = container.InstanceView?.CurrentState?.State;
            }
            
            if (state != null && (state.Equals("Stopped", StringComparison.OrdinalIgnoreCase) || state.Equals("Terminated", StringComparison.OrdinalIgnoreCase)))
                return (true, "Server is already stopped!");

            containerGroupResource.Delete(WaitUntil.Started);

            _serverStates[containerGroupName] = new ServerState
            {
                Status = "stopped",
                StartedAt = null,
                AutoShutdownTime = null
            };

            return (true, "Server is shutting down...");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error stopping server");
            return (false, $"Error stopping server: {ex.Message}");
        }
    }

    private static string GetHashString(string input)
    {
        var bytes = Encoding.UTF8.GetBytes(input);
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash).ToLower();
    }
}
