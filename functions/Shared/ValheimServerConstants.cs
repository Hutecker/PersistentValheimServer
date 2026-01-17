namespace ValheimServerFunctions;

public enum DiscordInteractionType
{
    Ping = 1,
    ApplicationCommand = 2,
    MessageComponent = 3,
    ApplicationCommandAutocomplete = 4,
    ModalSubmit = 5
}

public enum DiscordResponseType
{
    Pong = 1,
    ChannelMessageWithSource = 4,
    DeferredChannelMessageWithSource = 5,
    DeferredUpdateMessage = 6,
    UpdateMessage = 7
}

[Flags]
public enum DiscordMessageFlags
{
    None = 0,
    Ephemeral = 64,
    SuppressEmbeds = 4,
    Urgent = 16
}

public enum ContainerState
{
    Unknown,
    Running,
    Stopped,
    Terminated,
    Failed,
    Waiting,
    Starting
}

public enum ServerStatus
{
    Unknown,
    Starting,
    Running,
    Stopping,
    Stopped
}

public static class AppConstants
{
    public const string ContentTypeHeader = "Content-Type";
    public const string ContentTypeJson = "application/json";
    public const string DiscordSignatureHeader = "X-Signature-Ed25519";
    public const string DiscordTimestampHeader = "X-Signature-Timestamp";
    
    public const string DiscordApiBaseUrl = "https://discord.com/api/v10";
    public const string ValheimCommandName = "valheim";
    
    public const string StartSubcommand = "start";
    public const string StopSubcommand = "stop";
    public const string StatusSubcommand = "status";
    
    public const string ContainerName = "valheim-server";
    public const string ContainerImage = "docker.io/lloesche/valheim-server:latest";
    public const string VolumeNameWorldData = "world-data";
    public const string VolumeMountPath = "/config";
    public const string DefaultWorldName = "Dedicated";
    public const double ContainerCpuCores = 2.0;
    public const double ContainerMemoryGb = 4.0;
    
    public const int ValheimPort1 = 2456;
    public const int ValheimPort2 = 2457;
    public const int ValheimPort3 = 2458;
    
    public const string DefaultLocation = "eastus";
    public const string DefaultServerName = "Valheim Server";
    public const int DefaultAutoShutdownMinutes = 120;
}

public static class EnvVars
{
    public const string DiscordPublicKey = "DISCORD_PUBLIC_KEY";
    public const string SubscriptionId = "SUBSCRIPTION_ID";
    public const string ResourceGroupName = "RESOURCE_GROUP_NAME";
    public const string ContainerGroupName = "CONTAINER_GROUP_NAME";
    public const string ServerPassword = "SERVER_PASSWORD";
    public const string ServerName = "SERVER_NAME";
    public const string StorageAccountName = "STORAGE_ACCOUNT_NAME";
    public const string FileShareName = "FILE_SHARE_NAME";
    public const string Location = "LOCATION";
    public const string AutoShutdownMinutes = "AUTO_SHUTDOWN_MINUTES";
}

public static class ContainerStateHelper
{
    public static ContainerState ParseContainerState(string? stateString)
    {
        if (string.IsNullOrEmpty(stateString))
            return ContainerState.Unknown;

        return stateString.ToLowerInvariant() switch
        {
            "running" => ContainerState.Running,
            "stopped" => ContainerState.Stopped,
            "terminated" => ContainerState.Terminated,
            "failed" => ContainerState.Failed,
            "waiting" => ContainerState.Waiting,
            "starting" => ContainerState.Starting,
            _ => ContainerState.Unknown
        };
    }
}
