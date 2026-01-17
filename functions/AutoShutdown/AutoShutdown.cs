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
    public void Run([TimerTrigger("0 */60 * * * *")] TimerInfo myTimer)
    {
        var utcTimestamp = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ");
        _logger.LogInformation($"AutoShutdown timer trigger executed at: {utcTimestamp}");

        try
        {
            var subscriptionId = Environment.GetEnvironmentVariable(EnvVars.SubscriptionId);
            var resourceGroupName = Environment.GetEnvironmentVariable(EnvVars.ResourceGroupName);
            var containerGroupName = Environment.GetEnvironmentVariable(EnvVars.ContainerGroupName);
            var autoShutdownMinutes = int.Parse(Environment.GetEnvironmentVariable(EnvVars.AutoShutdownMinutes) ?? AppConstants.DefaultAutoShutdownMinutes.ToString());

            if (_armClient == null || string.IsNullOrEmpty(subscriptionId) || string.IsNullOrEmpty(resourceGroupName) || string.IsNullOrEmpty(containerGroupName))
            {
                _logger.LogWarning("Azure client not initialized or configuration missing");
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
                var instanceView = containerGroupData.Data.Containers?[0].InstanceView;
                if (instanceView?.Events != null && instanceView.Events.Any())
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
                            containerGroupResource.Delete(Azure.WaitUntil.Started);
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
            _logger.LogInformation($"Container group not found or error: {ex.Message}");
        }
    }
}
