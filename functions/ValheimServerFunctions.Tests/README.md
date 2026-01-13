# Azure Functions Test Suite

This test suite provides comprehensive testing for the DiscordBot Azure Function, covering all Discord Interactions API requirements as specified in the [official documentation](https://discord.com/developers/docs/interactions/overview).

## Test Coverage

The test suite covers:

1. **Interaction Types**
   - PING (Type 1) → PONG response
   - APPLICATION_COMMAND (Type 2) → Command handling

2. **Signature Verification**
   - Valid ed25519 signature verification
   - Invalid signature rejection
   - Missing header handling
   - PING bypass for endpoint verification

3. **Response Types**
   - Type 1: PONG
   - Type 4: CHANNEL_MESSAGE_WITH_SOURCE
   - Type 5: DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE

4. **Command Handling**
   - `/valheim start` → Deferred response
   - `/valheim stop` → Immediate response
   - `/valheim status` → Immediate response
   - Unknown command handling

5. **Error Handling**
   - Invalid JSON
   - Missing headers
   - Internal errors

6. **HTTP Headers**
   - Content-Type: application/json verification

## Current Status

⚠️ **The test project currently has compilation errors** that need to be fixed:

1. **TestFunctionContext** - Needs to properly implement all abstract members of `FunctionContext`
2. **TestFunctionDefinition** - Needs to implement missing properties
3. **TestTraceContext** - Needs proper `TraceFlags` implementation
4. **Mock Setup** - HttpRequestData and HttpResponseData mocks need proper setup

## Running Tests

Once compilation issues are resolved:

```powershell
cd functions
dotnet test ValheimServerFunctions.Tests/ValheimServerFunctions.Tests.csproj
```

Tests are automatically executed as part of the deployment process in `deploy.ps1`.

## Fixing Compilation Errors

The test helpers need to properly implement Azure Functions interfaces. Key areas to fix:

1. **FunctionContext** - Implement `Items`, `Features`, and other abstract members
2. **FunctionDefinition** - Implement `PathToAssembly`, `InputBindings`, `OutputBindings`
3. **TraceContext** - Use correct `TraceFlags` enum from the Azure Functions SDK

Consider using a testing library specifically designed for Azure Functions, or simplify the tests to focus on testable logic (like signature verification) without full interface mocking.

## Test Structure

- `DiscordBotTests.cs` - Main test class with all test cases
- `Helpers/DiscordSignatureHelper.cs` - Helper to generate valid/invalid Discord signatures
- `Helpers/TestHttpRequestData.cs` - Mock HttpRequestData for testing
- `Helpers/TestHttpResponseData.cs` - Mock HttpResponseData for testing
- `Helpers/TestFunctionContext.cs` - Mock FunctionContext for testing

## References

- [Discord Interactions Overview](https://discord.com/developers/docs/interactions/overview)
- [Discord Security and Authorization](https://discord.com/developers/docs/interactions/receiving-and-responding#security-and-authorization)
- [Azure Functions Testing](https://learn.microsoft.com/en-us/azure/azure-functions/functions-test-a-function)
