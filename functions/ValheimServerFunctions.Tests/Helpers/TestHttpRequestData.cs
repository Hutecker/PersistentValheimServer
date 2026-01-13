using System.IO;
using System.Net;
using System.Text;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Moq;

namespace ValheimServerFunctions.Tests.Helpers;

/// <summary>
/// Helper to create HttpRequestData mocks for unit testing
/// </summary>
public static class TestHttpRequestData
{
    public static HttpRequestData Create(FunctionContext functionContext, string? body = null, Dictionary<string, string>? headers = null)
    {
        var mockRequest = new Mock<HttpRequestData>(functionContext);
        
        // Setup body stream
        var bodyStream = new MemoryStream();
        if (!string.IsNullOrEmpty(body))
        {
            var bodyBytes = Encoding.UTF8.GetBytes(body);
            bodyStream.Write(bodyBytes, 0, bodyBytes.Length);
            bodyStream.Position = 0;
        }
        mockRequest.Setup(r => r.Body).Returns(bodyStream);
        
        // Setup headers
        var headersCollection = new HttpHeadersCollection();
        if (headers != null)
        {
            foreach (var header in headers)
            {
                headersCollection.Add(header.Key, new[] { header.Value });
            }
        }
        mockRequest.Setup(r => r.Headers).Returns(headersCollection);
        
        // Setup other properties
        mockRequest.Setup(r => r.Method).Returns("POST");
        mockRequest.Setup(r => r.Url).Returns(new Uri("https://test.azurewebsites.net/api/DiscordBot"));
        mockRequest.Setup(r => r.Identities).Returns(Array.Empty<System.Security.Claims.ClaimsIdentity>());
        
        // Setup CreateResponse
        mockRequest.Setup(r => r.CreateResponse())
            .Returns(() => TestHttpResponseData.Create(functionContext));
        
        return mockRequest.Object;
    }
}
