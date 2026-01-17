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
        public ServerStatus Status { get; set; } = ServerStatus.Stopped;
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
            
            if (!VerifyDiscordSignature(req, body))
            {
                _logger.LogWarning("Invalid Discord signature - request rejected");
                var unauthorizedResponse = req.CreateResponse(HttpStatusCode.Unauthorized);
                unauthorizedResponse.Headers.Add(AppConstants.ContentTypeHeader, AppConstants.ContentTypeJson);
                await unauthorizedResponse.WriteStringAsync(JsonSerializer.Serialize(new { error = "Unauthorized" }));
                return unauthorizedResponse;
            }
            
            JsonElement data;
            try
            {
                data = JsonSerializer.Deserialize<JsonElement>(body);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to parse request body as JSON");
                var badRequestResponse = req.CreateResponse(HttpStatusCode.BadRequest);
                badRequestResponse.Headers.Add(AppConstants.ContentTypeHeader, AppConstants.ContentTypeJson);
                await badRequestResponse.WriteStringAsync(JsonSerializer.Serialize(new { error = "Invalid JSON" }));
                return badRequestResponse;
            }

            var responseData = await HandleDiscordInteractionAsync(data);
            var response = req.CreateResponse(HttpStatusCode.OK);
            response.Headers.Add(AppConstants.ContentTypeHeader, AppConstants.ContentTypeJson);

            await response.WriteStringAsync(JsonSerializer.Serialize(responseData));
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing request");
            var errorResponse = req.CreateResponse(HttpStatusCode.InternalServerError);
            errorResponse.Headers.Add(AppConstants.ContentTypeHeader, AppConstants.ContentTypeJson);
            await errorResponse.WriteStringAsync(JsonSerializer.Serialize(new { error = ex.Message }));
            return errorResponse;
        }
    }

    private bool VerifyDiscordSignature(HttpRequestData req, string body)
    {
        try
        {
            if (!req.Headers.TryGetValues(AppConstants.DiscordSignatureHeader, out var signatureHeader) ||
                !req.Headers.TryGetValues(AppConstants.DiscordTimestampHeader, out var timestampHeader))
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

            var publicKeyHex = Environment.GetEnvironmentVariable(EnvVars.DiscordPublicKey);

            if (string.IsNullOrEmpty(publicKeyHex))
            {
                _logger.LogError("Discord public key not configured - signature verification cannot proceed");
                return false;
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
            return CreatePongResponse();

        var interactionType = (DiscordInteractionType)typeElement.GetInt32();

        if (interactionType == DiscordInteractionType.Ping)
            return CreatePongResponse();

        if (interactionType == DiscordInteractionType.ApplicationCommand)
        {
            if (!data.TryGetProperty("data", out var dataElement))
                return CreateMessageResponse("Unknown command");

            if (!dataElement.TryGetProperty("name", out var nameElement))
                return CreateMessageResponse("Unknown command");

            var commandName = nameElement.GetString();
            if (commandName != AppConstants.ValheimCommandName)
                return CreateMessageResponse("Unknown command");

            if (!dataElement.TryGetProperty("options", out var optionsElement) || optionsElement.ValueKind != JsonValueKind.Array)
                return CreateMessageResponse("No subcommand provided");

            var options = optionsElement.EnumerateArray().ToList();
            if (options.Count == 0)
                return CreateMessageResponse("No subcommand provided");

            var subcommand = options[0].GetProperty("name").GetString();

            return subcommand switch
            {
                AppConstants.StartSubcommand => await HandleStartCommandAsync(data),
                AppConstants.StopSubcommand => HandleStopCommand(),
                AppConstants.StatusSubcommand => HandleStatusCommand(),
                _ => CreateMessageResponse("Unknown subcommand")
            };
        }

        return CreatePongResponse();
    }

    private static object CreatePongResponse() => new { type = (int)DiscordResponseType.Pong };

    private static object CreateMessageResponse(string content, DiscordMessageFlags flags = DiscordMessageFlags.None)
    {
        if (flags == DiscordMessageFlags.None)
            return new { type = (int)DiscordResponseType.ChannelMessageWithSource, data = new { content } };
        
        return new { type = (int)DiscordResponseType.ChannelMessageWithSource, data = new { content, flags = (int)flags } };
    }

    private static object CreateDeferredResponse() => new { type = (int)DiscordResponseType.DeferredChannelMessageWithSource };

    private async Task<object> HandleStartCommandAsync(JsonElement interactionData)
    {
        try
        {
            if (!interactionData.TryGetProperty("token", out var tokenElement) ||
                !interactionData.TryGetProperty("application_id", out var appIdElement))
            {
                return CreateMessageResponse("**Error** Missing interaction data", DiscordMessageFlags.Ephemeral);
            }

            var interactionToken = tokenElement.GetString();
            var applicationId = appIdElement.GetString();

            _ = Task.Run(async () =>
            {
                try
                {
                    await StartServerAndNotify(applicationId, interactionToken);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error in background server start task");
                    await SendFollowUpMessage(applicationId, interactionToken, $"**Error** {ex.Message}");
                }
            });

            return CreateDeferredResponse();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in start command");
            return CreateMessageResponse($"**Error** Error starting server: {ex.Message}", DiscordMessageFlags.Ephemeral);
        }
    }

    private object HandleStopCommand()
    {
        try
        {
            var (success, message) = StopServer();
            return CreateMessageResponse(message, success ? DiscordMessageFlags.None : DiscordMessageFlags.Ephemeral);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in stop command");
            return CreateMessageResponse($"Error stopping server: {ex.Message}", DiscordMessageFlags.Ephemeral);
        }
    }

    private object HandleStatusCommand()
    {
        try
        {
            var containerState = GetContainerState();
            var stateKey = Environment.GetEnvironmentVariable(EnvVars.ContainerGroupName) ?? AppConstants.ContainerName;
            
            if (containerState == ContainerState.Running)
            {
                if (_serverStates.TryGetValue(stateKey, out var state) && state.StartedAt.HasValue && state.AutoShutdownTime.HasValue)
                {
                    var timeRemaining = state.AutoShutdownTime.Value - DateTime.UtcNow;
                    if (timeRemaining.TotalSeconds > 0)
                    {
                        var mins = (int)timeRemaining.TotalMinutes;
                        return CreateMessageResponse($"Server is **RUNNING**\nAuto-shutdown in {mins} minutes");
                    }
                    return CreateMessageResponse("Server is **RUNNING**\n[WARNING] Auto-shutdown time has passed");
                }
                return CreateMessageResponse("Server is **RUNNING**");
            }

            if (containerState == ContainerState.Stopped || containerState == ContainerState.Terminated)
            {
                return CreateMessageResponse("Server is **STOPPED**\nUse `/valheim start` to start the server.");
            }

            return CreateMessageResponse("**Error** Unable to determine server status.\nPlease try again or use `/valheim start` to start the server.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in status command");
            return CreateMessageResponse($"Error checking status: {ex.Message}");
        }
    }

    private ContainerState GetContainerState()
    {
        try
        {
            var subscriptionId = Environment.GetEnvironmentVariable(EnvVars.SubscriptionId);
            var resourceGroupName = Environment.GetEnvironmentVariable(EnvVars.ResourceGroupName);
            var containerGroupName = Environment.GetEnvironmentVariable(EnvVars.ContainerGroupName);

            if (_armClient == null || string.IsNullOrEmpty(subscriptionId) || string.IsNullOrEmpty(resourceGroupName) || string.IsNullOrEmpty(containerGroupName))
                return ContainerState.Unknown;

            var subscription = _armClient.GetSubscriptionResource(SubscriptionResource.CreateResourceIdentifier(subscriptionId));
            var resourceGroup = subscription.GetResourceGroup(resourceGroupName).Value;
            var containerGroup = resourceGroup.GetContainerGroup(containerGroupName);
            
            var containerGroupResource = containerGroup.Value;
            var containerGroupData = containerGroupResource.Get().Value;
            
            if (containerGroupData.Data.Containers != null && containerGroupData.Data.Containers.Count > 0)
            {
                var container = containerGroupData.Data.Containers[0];
                var stateString = container.InstanceView?.CurrentState?.State;
                return ContainerStateHelper.ParseContainerState(stateString);
            }

            return ContainerState.Stopped;
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            _logger.LogInformation("Container group does not exist - server has not been started");
            return ContainerState.Stopped;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking server status");
            return ContainerState.Unknown;
        }
    }

    private (bool Success, string Message) StartServer()
    {
        try
        {
            var subscriptionId = Environment.GetEnvironmentVariable(EnvVars.SubscriptionId);
            var resourceGroupName = Environment.GetEnvironmentVariable(EnvVars.ResourceGroupName);
            var containerGroupName = Environment.GetEnvironmentVariable(EnvVars.ContainerGroupName);

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
                    var state = ContainerStateHelper.ParseContainerState(existingContainer.InstanceView?.CurrentState?.State);
                    
                    if (state == ContainerState.Running)
                        return (true, "Server is already running!");

                    if (state == ContainerState.Stopped || state == ContainerState.Terminated)
                    {
                        _logger.LogInformation("Deleting stopped container group before recreating...");
                        containerGroupResource.Delete(WaitUntil.Completed);
                    }
                }
            }
            catch (RequestFailedException ex) when (ex.Status == 404)
            {
                _logger.LogInformation("Container group doesn't exist yet, will create new one");
            }
            catch (Exception ex)
            {
                _logger.LogInformation($"Container group doesn't exist yet: {ex.Message}");
            }

            var serverPassword = Environment.GetEnvironmentVariable(EnvVars.ServerPassword);
            if (string.IsNullOrEmpty(serverPassword))
            {
                return (false, $"{EnvVars.ServerPassword} app setting not configured");
            }
            var serverName = Environment.GetEnvironmentVariable(EnvVars.ServerName) ?? AppConstants.DefaultServerName;
            var storageAccountName = Environment.GetEnvironmentVariable(EnvVars.StorageAccountName);
            var fileShareName = Environment.GetEnvironmentVariable(EnvVars.FileShareName);
            var location = Environment.GetEnvironmentVariable(EnvVars.Location) ?? AppConstants.DefaultLocation;

            if (string.IsNullOrEmpty(storageAccountName) || string.IsNullOrEmpty(fileShareName))
                return (false, "Storage account configuration missing");

            var storageAccount = resourceGroup.GetStorageAccount(storageAccountName).Value;
            var keys = storageAccount.GetKeys();
            var storageKey = keys.First().Value;

            var azureLocation = new AzureLocation(location);
            var container = new ContainerInstanceContainer(AppConstants.ContainerName, AppConstants.ContainerImage, 
                new ContainerResourceRequirements(new ContainerResourceRequestsContent(AppConstants.ContainerCpuCores, AppConstants.ContainerMemoryGb)))
            {
                EnvironmentVariables =
                {
                    new ContainerEnvironmentVariable("SERVER_NAME") { Value = serverName },
                    new ContainerEnvironmentVariable("WORLD_NAME") { Value = AppConstants.DefaultWorldName },
                    new ContainerEnvironmentVariable("SERVER_PASS") { SecureValue = serverPassword },
                    new ContainerEnvironmentVariable("SERVER_PUBLIC") { Value = "1" },
                    new ContainerEnvironmentVariable("BACKUPS") { Value = "1" },
                    new ContainerEnvironmentVariable("BACKUPS_RETENTION_DAYS") { Value = "7" },
                    new ContainerEnvironmentVariable("UPDATE_CRON") { Value = "0 4 * * *" }
                },
                VolumeMounts =
                {
                    new ContainerVolumeMount(AppConstants.VolumeNameWorldData, AppConstants.VolumeMountPath)
                },
                Ports =
                {
                    new ContainerPort(AppConstants.ValheimPort1) { Protocol = ContainerNetworkProtocol.Udp },
                    new ContainerPort(AppConstants.ValheimPort2) { Protocol = ContainerNetworkProtocol.Udp },
                    new ContainerPort(AppConstants.ValheimPort3) { Protocol = ContainerNetworkProtocol.Udp }
                }
            };

            var ipAddressPorts = new List<ContainerGroupPort>
            {
                new ContainerGroupPort(AppConstants.ValheimPort1) { Protocol = ContainerGroupNetworkProtocol.Udp },
                new ContainerGroupPort(AppConstants.ValheimPort2) { Protocol = ContainerGroupNetworkProtocol.Udp },
                new ContainerGroupPort(AppConstants.ValheimPort3) { Protocol = ContainerGroupNetworkProtocol.Udp }
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
                    new ContainerVolume(AppConstants.VolumeNameWorldData)
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
            var autoShutdownMinutes = int.Parse(Environment.GetEnvironmentVariable(EnvVars.AutoShutdownMinutes) ?? AppConstants.DefaultAutoShutdownMinutes.ToString());
            _serverStates[stateKey] = new ServerState
            {
                Status = ServerStatus.Starting,
                StartedAt = DateTime.UtcNow,
                AutoShutdownTime = DateTime.UtcNow.AddMinutes(autoShutdownMinutes)
            };

            return (true, $"Server is starting! It will automatically shut down in {autoShutdownMinutes} minutes.");
        }
        catch (RequestFailedException ex) when (ex.Status == 409 && ex.ErrorCode == "MissingSubscriptionRegistration")
        {
            _logger.LogError(ex, "Container Instance resource provider not registered");
            return (false, "**Configuration Error**\n\n" +
                "Your Azure subscription is not registered to use Container Instances.\n\n" +
                "**To fix this:**\n" +
                "1. Go to Azure Portal → Subscriptions → Your Subscription → Resource providers\n" +
                "2. Search for 'Microsoft.ContainerInstance'\n" +
                "3. Click 'Register' and wait for it to complete\n\n" +
                "Or use Azure CLI:\n" +
                "`az provider register --namespace Microsoft.ContainerInstance`\n\n" +
                "After registration completes (usually 1-2 minutes), try starting the server again.");
        }
        catch (RequestFailedException ex) when (ex.Status == 409 && ex.ErrorCode == "RegistryErrorResponse")
        {
            _logger.LogError(ex, "Docker registry error when pulling container image");
            return (false, "**Docker Registry Error**\n\n" +
                "Unable to pull the container image from Docker Hub. This is usually a temporary issue.\n\n" +
                "**Possible causes:**\n" +
                "• Docker Hub is experiencing issues\n" +
                "• Rate limiting from Docker Hub (anonymous pulls)\n" +
                "• Network connectivity issues\n\n" +
                "**What to do:**\n" +
                "• Wait a few minutes and try again\n" +
                "• Check Docker Hub status: https://status.docker.com\n" +
                "• If the issue persists, the container image may need to be pulled to a private Azure Container Registry");
        }
        catch (RequestFailedException ex)
        {
            _logger.LogError(ex, "Azure API error starting server. Status: {Status}, ErrorCode: {ErrorCode}", ex.Status, ex.ErrorCode);
            return (false, $"**Azure Error** ({ex.Status})\n\n{ex.Message}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error starting server");
            return (false, $"Error starting server: {ex.Message}");
        }
    }

    private async Task StartServerAndNotify(string? applicationId, string? interactionToken)
    {
        try
        {
            if (string.IsNullOrEmpty(applicationId) || string.IsNullOrEmpty(interactionToken))
            {
                _logger.LogError("Missing interaction token or application ID");
                return;
            }

            await SendFollowUpMessage(applicationId, interactionToken, "Server is starting... This may take 2-3 minutes.");

            var (success, message) = StartServer();
            
            if (!success)
            {
                await SendFollowUpMessage(applicationId, interactionToken, $"**Error** {message}");
                return;
            }

            var subscriptionId = Environment.GetEnvironmentVariable(EnvVars.SubscriptionId);
            var resourceGroupName = Environment.GetEnvironmentVariable(EnvVars.ResourceGroupName);
            var containerGroupName = Environment.GetEnvironmentVariable(EnvVars.ContainerGroupName);
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
                        await SendFollowUpMessage(applicationId, interactionToken, "**Error** Azure clients not initialized");
                        return;
                    }

                    var subscription = _armClient.GetSubscriptionResource(SubscriptionResource.CreateResourceIdentifier(subscriptionId));
                    var resourceGroup = subscription.GetResourceGroup(resourceGroupName).Value;
                    var containerGroup = resourceGroup.GetContainerGroup(containerGroupName);
                    var containerGroupResource = containerGroup.Value;
                    var containerGroupData = containerGroupResource.Get().Value;
                    
                    ContainerState state = ContainerState.Unknown;
                    if (containerGroupData.Data.Containers != null && containerGroupData.Data.Containers.Count > 0)
                    {
                        var container = containerGroupData.Data.Containers[0];
                        state = ContainerStateHelper.ParseContainerState(container.InstanceView?.CurrentState?.State);
                    }

                    if (state == ContainerState.Running)
                    {
                        var ipAddressData = containerGroupData.Data.IPAddress;
                        if (ipAddressData != null)
                        {
                            serverIp = ipAddressData.IP?.ToString();
                            serverFqdn = ipAddressData.Fqdn;
                        }

                        var autoShutdownMinutes = int.Parse(Environment.GetEnvironmentVariable(EnvVars.AutoShutdownMinutes) ?? AppConstants.DefaultAutoShutdownMinutes.ToString());
                        var stateKey = containerGroupName;
                        _serverStates[stateKey] = new ServerState
                        {
                            Status = ServerStatus.Running,
                            StartedAt = DateTime.UtcNow,
                            AutoShutdownTime = DateTime.UtcNow.AddMinutes(autoShutdownMinutes)
                        };

                        var readyMessage = new StringBuilder();
                        readyMessage.AppendLine("**Success! Server is ready!**");
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
                    else if (state == ContainerState.Failed || state == ContainerState.Stopped)
                    {
                        await SendFollowUpMessage(applicationId, interactionToken, 
                            $"**Error** Server failed to start. Status: {state}");
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
                "**TIMEOUT** Server is taking longer than expected to start. Please check the status with `/valheim status`");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in StartServerAndNotify");

            if (!string.IsNullOrEmpty(applicationId) && !string.IsNullOrEmpty(interactionToken))
            {
                try
                {
                    await SendFollowUpMessage(applicationId, interactionToken, $"**Error** {ex.Message}");
                }
                catch
                {
                }
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
            var webhookUrl = $"{AppConstants.DiscordApiBaseUrl}/webhooks/{applicationId}/{interactionToken}";
            
            var payload = new
            {
                content = content
            };

            var json = JsonSerializer.Serialize(payload);
            var contentData = new StringContent(json, Encoding.UTF8, AppConstants.ContentTypeJson);

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
            var subscriptionId = Environment.GetEnvironmentVariable(EnvVars.SubscriptionId);
            var resourceGroupName = Environment.GetEnvironmentVariable(EnvVars.ResourceGroupName);
            var containerGroupName = Environment.GetEnvironmentVariable(EnvVars.ContainerGroupName);

            if (_armClient == null || string.IsNullOrEmpty(subscriptionId) || string.IsNullOrEmpty(resourceGroupName) || string.IsNullOrEmpty(containerGroupName))
                return (false, "Azure clients not initialized");

            var subscription = _armClient.GetSubscriptionResource(SubscriptionResource.CreateResourceIdentifier(subscriptionId));
            var resourceGroup = subscription.GetResourceGroup(resourceGroupName).Value;
            
            ContainerGroupResource containerGroupResource;
            try
            {
                var containerGroup = resourceGroup.GetContainerGroup(containerGroupName);
                containerGroupResource = containerGroup.Value;
            }
            catch (RequestFailedException ex) when (ex.Status == 404)
            {
                _logger.LogInformation("Container group does not exist - server is already stopped");
                return (true, "Server is already stopped!");
            }
            
            var containerGroupData = containerGroupResource.Get().Value;
            
            ContainerState state = ContainerState.Unknown;
            if (containerGroupData.Data.Containers != null && containerGroupData.Data.Containers.Count > 0)
            {
                var container = containerGroupData.Data.Containers[0];
                state = ContainerStateHelper.ParseContainerState(container.InstanceView?.CurrentState?.State);
            }
            
            if (state == ContainerState.Stopped || state == ContainerState.Terminated)
                return (true, "Server is already stopped!");

            containerGroupResource.Delete(WaitUntil.Started);

            _serverStates[containerGroupName] = new ServerState
            {
                Status = ServerStatus.Stopped,
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
