using System.IO;
using System.Net;
using System.Text;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Moq;

namespace ValheimServerFunctions.Tests.Helpers;

/// <summary>
/// Helper to create HttpResponseData mocks for unit testing
/// </summary>
public static class TestHttpResponseData
{
    public static HttpResponseData Create(FunctionContext functionContext)
    {
        var mockResponse = new Mock<HttpResponseData>(functionContext);
        var headersCollection = new HttpHeadersCollection();
        var bodyStream = new MemoryStream();
        
        mockResponse.Setup(r => r.StatusCode).Returns(HttpStatusCode.OK);
        mockResponse.SetupProperty(r => r.StatusCode);
        mockResponse.Setup(r => r.Headers).Returns(headersCollection);
        mockResponse.Setup(r => r.Body).Returns(bodyStream);
        
        // Note: WriteStringAsync is an extension method and cannot be mocked with Moq
        // The extension method writes directly to the Body stream, which we've already set up
        // So it will work automatically - we just need to ensure the body stream is readable
        
        return mockResponse.Object;
    }
    
    public static string GetBodyAsString(HttpResponseData response)
    {
        if (response.Body is MemoryStream ms)
        {
            ms.Position = 0;
            using var reader = new StreamReader(ms, Encoding.UTF8, leaveOpen: true);
            return reader.ReadToEnd();
        }
        return string.Empty;
    }
}
