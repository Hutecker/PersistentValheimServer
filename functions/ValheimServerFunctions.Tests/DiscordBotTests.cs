using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Moq;
using ValheimServerFunctions.Tests.Helpers;
using Xunit;

namespace ValheimServerFunctions.Tests;

/// <summary>
/// Comprehensive test suite for DiscordBot function covering all Discord Interactions API requirements
/// Based on: https://discord.com/developers/docs/interactions/overview
/// </summary>
public class DiscordBotTests : IDisposable
{
    private readonly ILoggerFactory _loggerFactory;
    private readonly Dictionary<string, string> _environmentVariables = new();
    
    public DiscordBotTests()
    {
        _loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
        
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", "");
        SetEnvironmentVariable("SERVER_PASSWORD", "test-password");
        SetEnvironmentVariable("SUBSCRIPTION_ID", "test-subscription-id");
        SetEnvironmentVariable("RESOURCE_GROUP_NAME", "test-rg");
        SetEnvironmentVariable("CONTAINER_GROUP_NAME", "test-container");
        SetEnvironmentVariable("SERVER_NAME", "Test Server");
        SetEnvironmentVariable("STORAGE_ACCOUNT_NAME", "teststorage");
        SetEnvironmentVariable("FILE_SHARE_NAME", "testshare");
        SetEnvironmentVariable("LOCATION", "eastus");
        SetEnvironmentVariable("AUTO_SHUTDOWN_MINUTES", "120");
    }
    
    private void SetEnvironmentVariable(string key, string value)
    {
        _environmentVariables[key] = value;
        Environment.SetEnvironmentVariable(key, value);
    }
    
    public void Dispose()
    {
        foreach (var key in _environmentVariables.Keys)
        {
            Environment.SetEnvironmentVariable(key, null);
        }
    }
    
    #region Interaction Type Tests (PING, APPLICATION_COMMAND)
    
    [Fact]
    public async Task HandlePing_ReturnsPong()
    {
        var (publicKey, signature, timestamp) = DiscordSignatureHelper.GenerateValidSignature("{\"type\":1}");
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var body = "{\"type\":1}";
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", signature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal(1, responseJson.GetProperty("type").GetInt32());
    }
    
    [Fact]
    public async Task HandleApplicationCommand_UnknownCommand_ReturnsErrorMessage()
    {
        var (publicKey, signature, timestamp) = DiscordSignatureHelper.GenerateValidSignature(
            "{\"type\":2,\"data\":{\"name\":\"unknown\",\"options\":[]}}"
        );
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var body = "{\"type\":2,\"data\":{\"name\":\"unknown\",\"options\":[]}}";
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", signature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal(4, responseJson.GetProperty("type").GetInt32());
        Assert.Contains("Unknown command", responseJson.GetProperty("data").GetProperty("content").GetString()!);
    }
    
    [Fact]
    public async Task HandleApplicationCommand_NoType_ReturnsPong()
    {
        // Arrange
        var (publicKey, signature, timestamp) = DiscordSignatureHelper.GenerateValidSignature("{}");
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var body = "{}";
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", signature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal(1, responseJson.GetProperty("type").GetInt32());
    }
    
    #endregion
    
    #region Signature Verification Tests
    
    [Fact]
    public async Task MissingSignatureHeaders_ReturnsUnauthorized()
    {
        var body = "{\"type\":2,\"data\":{\"name\":\"valheim\",\"options\":[{\"name\":\"status\"}]}}";
        var headers = new Dictionary<string, string>();
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        // Act
        var response = await bot.Run(request, functionContext);
        
        // Assert
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal("Unauthorized", responseJson.GetProperty("error").GetString());
    }
    
    [Fact]
    public async Task InvalidSignature_ReturnsUnauthorized()
    {
        // Arrange
        var body = "{\"type\":2,\"data\":{\"name\":\"valheim\",\"options\":[{\"name\":\"status\"}]}}";
        var (_, invalidSignature, timestamp) = DiscordSignatureHelper.GenerateInvalidSignature(body);
        var (publicKey, _, _) = DiscordSignatureHelper.GenerateValidSignature(body);
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", invalidSignature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        // Act
        var response = await bot.Run(request, functionContext);
        
        // Assert
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
    
    [Fact]
    public async Task ValidSignature_ProcessesRequest()
    {
        // Arrange
        var body = "{\"type\":2,\"data\":{\"name\":\"valheim\",\"options\":[{\"name\":\"status\"}]}}";
        var (publicKey, signature, timestamp) = DiscordSignatureHelper.GenerateValidSignature(body);
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", signature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
    
    [Fact]
    public async Task Ping_AllowsThroughWithoutValidSignature()
    {
        var body = "{\"type\":1}";
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", "invalid" },
            { "X-Signature-Timestamp", "1234567890" }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal(1, responseJson.GetProperty("type").GetInt32());
    }
    
    #endregion
    
    #region Response Type Tests
    
    [Fact]
    public async Task Response_ContainsContentTypeHeader()
    {
        var (publicKey, signature, timestamp) = DiscordSignatureHelper.GenerateValidSignature("{\"type\":1}");
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var body = "{\"type\":1}";
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", signature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        // Act
        var response = await bot.Run(request, functionContext);
        
        // Assert
        var contentType = response.Headers.GetValues("Content-Type").FirstOrDefault();
        Assert.Equal("application/json", contentType);
    }
    
    [Fact]
    public async Task StatusCommand_ReturnsChannelMessageResponse()
    {
        // Arrange
        var body = "{\"type\":2,\"data\":{\"name\":\"valheim\",\"options\":[{\"name\":\"status\"}]},\"token\":\"test-token\",\"application_id\":\"test-app-id\"}";
        var (publicKey, signature, timestamp) = DiscordSignatureHelper.GenerateValidSignature(body);
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", signature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal(4, responseJson.GetProperty("type").GetInt32());
        Assert.True(responseJson.GetProperty("data").TryGetProperty("content", out _));
    }
    
    [Fact]
    public async Task StartCommand_ReturnsDeferredResponse()
    {
        // Arrange
        var body = "{\"type\":2,\"data\":{\"name\":\"valheim\",\"options\":[{\"name\":\"start\"}]},\"token\":\"test-token\",\"application_id\":\"test-app-id\"}";
        var (publicKey, signature, timestamp) = DiscordSignatureHelper.GenerateValidSignature(body);
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", signature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal(5, responseJson.GetProperty("type").GetInt32());
    }
    
    #endregion
    
    #region Error Handling Tests
    
    [Fact]
    public async Task InvalidJson_ReturnsBadRequest()
    {
        // Arrange
        var body = "invalid json{";
        var headers = new Dictionary<string, string>();
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        // Act
        var response = await bot.Run(request, functionContext);
        
        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal("Invalid JSON", responseJson.GetProperty("error").GetString());
    }
    
    [Fact]
    public async Task EmptyBody_HandlesGracefully()
    {
        // Arrange
        var body = "";
        var headers = new Dictionary<string, string>();
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        // Act
        var response = await bot.Run(request, functionContext);
        
        Assert.True(response.StatusCode == HttpStatusCode.BadRequest || response.StatusCode == HttpStatusCode.OK);
    }
    
    #endregion
    
    #region Command Handling Tests
    
    [Fact]
    public async Task ValheimCommand_NoSubcommand_ReturnsErrorMessage()
    {
        // Arrange
        var body = "{\"type\":2,\"data\":{\"name\":\"valheim\",\"options\":[]},\"token\":\"test-token\",\"application_id\":\"test-app-id\"}";
        var (publicKey, signature, timestamp) = DiscordSignatureHelper.GenerateValidSignature(body);
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", signature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal(4, responseJson.GetProperty("type").GetInt32());
        Assert.Contains("No subcommand", responseJson.GetProperty("data").GetProperty("content").GetString()!);
    }
    
    [Fact]
    public async Task ValheimCommand_UnknownSubcommand_ReturnsErrorMessage()
    {
        // Arrange
        var body = "{\"type\":2,\"data\":{\"name\":\"valheim\",\"options\":[{\"name\":\"unknown\"}]},\"token\":\"test-token\",\"application_id\":\"test-app-id\"}";
        var (publicKey, signature, timestamp) = DiscordSignatureHelper.GenerateValidSignature(body);
        SetEnvironmentVariable("DISCORD_PUBLIC_KEY", publicKey);
        
        var headers = new Dictionary<string, string>
        {
            { "X-Signature-Ed25519", signature },
            { "X-Signature-Timestamp", timestamp }
        };
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var responseBody = TestHttpResponseData.GetBodyAsString(response);
        var responseJson = JsonSerializer.Deserialize<JsonElement>(responseBody);
        Assert.Equal(4, responseJson.GetProperty("type").GetInt32());
        Assert.Contains("Unknown subcommand", responseJson.GetProperty("data").GetProperty("content").GetString()!);
    }
    
    #endregion
    
    #region HTTP Method Tests
    
    [Fact]
    public async Task GetRequest_HandlesGracefully()
    {
        var body = "";
        var headers = new Dictionary<string, string>();
        
        var functionContext = new TestFunctionContext(_loggerFactory);
        var request = TestHttpRequestData.Create(functionContext, body, headers);
        var bot = new DiscordBot(_loggerFactory);
        
        var response = await bot.Run(request, functionContext);
        
        Assert.True(response.StatusCode == HttpStatusCode.BadRequest || response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.OK);
    }
    
    #endregion
}
