using System;
using System.Linq;
using Azure.Core;
using Azure.Identity;
using Azure.ResourceManager;
using Azure.ResourceManager.ContainerInstance;
using Azure.ResourceManager.Resources;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace ValheimServerFunctions;

public class AutoShutdown
{
    private readonly ILogger _logger;
    private static readonly DefaultAzureCredential Credential = new();
    private static ArmClient? _armClient;

    public AutoShutdown(ILoggerFactory loggerFactory)
    {
        _logger = loggerFactory.CreateLogger<AutoShutdown>();
        InitializeClient();
    }

    private void InitializeClient()
    {
        _armClient = new ArmClient(Credential);
    }

    [Function("AutoShutdown")]
    public void Run([TimerTrigger("0 */5 * * * *")] TimerInfo myTimer)
    {
        var utcTimestamp = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ");
        _logger.LogInformation($"C# timer trigger function executed at: {utcTimestamp}");

        try
        {
            var subscriptionId = Environment.GetEnvironmentVariable("SUBSCRIPTION_ID");
            var resourceGroupName = Environment.GetEnvironmentVariable("RESOURCE_GROUP_NAME");
            var containerGroupName = Environment.GetEnvironmentVariable("CONTAINER_GROUP_NAME");
            var autoShutdownMinutes = int.Parse(Environment.GetEnvironmentVariable("AUTO_SHUTDOWN_MINUTES") ?? "120");

            if (_armClient == null || string.IsNullOrEmpty(subscriptionId) || string.IsNullOrEmpty(resourceGroupName) || string.IsNullOrEmpty(containerGroupName))
            {
                _logger.LogWarning("Azure client not initialized or configuration missing");
                return;
            }

            var subscription = _armClient.GetSubscriptionResource(SubscriptionResource.CreateResourceIdentifier(subscriptionId));
            var resourceGroup = subscription.GetResourceGroup(resourceGroupName);
            var containerGroup = resourceGroup.GetContainerGroup(containerGroupName);
            var instanceView = containerGroup.Value.GetInstanceView();

            if (instanceView?.State == "Running")
            {
                // Check if auto-shutdown time has passed
                // In production, store this in Azure Table Storage
                // For now, we'll use a simple time-based check

                // Get container start time
                if (instanceView.Events != null && instanceView.Events.Any())
                {
                    var startEvent = instanceView.Events
                        .FirstOrDefault(e => e.Count > 0);

                    if (startEvent?.FirstTimestamp != null)
                    {
                        var startTime = startEvent.FirstTimestamp.Value.DateTime;
                        var shutdownTime = startTime.AddMinutes(autoShutdownMinutes);

                        if (DateTime.UtcNow >= shutdownTime)
                        {
                            _logger.LogInformation("Auto-shutdown time reached. Stopping server...");
                            containerGroup.Value.Delete(WaitUntil.Started);
                            _logger.LogInformation("Server stopped successfully");
                        }
                        else
                        {
                            _logger.LogInformation($"Server still running. Auto-shutdown at {shutdownTime:yyyy-MM-dd HH:mm:ss} UTC");
                        }
                    }
                }
            }
            else
            {
                _logger.LogInformation("Server is not running, no action needed");
            }
        }
        catch (Exception ex)
        {
            // Container group might not exist (already stopped)
            _logger.LogInformation($"Container group not found or error: {ex.Message}");
        }
    }
}
