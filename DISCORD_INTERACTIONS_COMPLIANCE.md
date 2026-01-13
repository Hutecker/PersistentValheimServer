# Discord Interactions API Compliance

This document verifies our implementation meets all Discord Interactions API requirements as specified in the [official documentation](https://discord.com/developers/docs/interactions/overview).

## ✅ Requirements Checklist

### 1. Request Verification (Security)
**Requirement**: All interaction requests MUST be cryptographically verified using ed25519 signatures.

**Status**: ✅ **IMPLEMENTED**
- ✅ Verifies `X-Signature-Ed25519` header
- ✅ Verifies `X-Signature-Timestamp` header  
- ✅ Uses ed25519 signature verification (Chaos.NaCl library)
- ✅ Rejects requests with invalid signatures
- ✅ Public key stored in Key Vault for security

**Implementation**: `VerifyDiscordSignature()` method in `DiscordBot.cs`

### 2. Response Types
**Requirement**: Must respond with correct interaction response types.

**Status**: ✅ **IMPLEMENTED**
- ✅ Type 1: PONG (for PING)
- ✅ Type 4: CHANNEL_MESSAGE_WITH_SOURCE (immediate responses)
- ✅ Type 5: DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE (for async operations)

**Implementation**: `HandleDiscordInteractionAsync()` method

### 3. Response Timing
**Requirement**: Must respond within 3 seconds or use deferred response (type 5).

**Status**: ✅ **IMPLEMENTED**
- ✅ `/valheim start` uses deferred response (type 5) for long-running operations
- ✅ `/valheim stop` and `/valheim status` respond immediately (< 3 seconds)
- ✅ Follow-up messages sent via webhook after deferred response

**Implementation**: `HandleStartCommandAsync()` returns type 5, then sends follow-up via webhook

### 4. Follow-up Messages
**Requirement**: Can send follow-up messages using interaction webhook.

**Status**: ✅ **IMPLEMENTED**
- ✅ Uses interaction webhook URL: `https://discord.com/api/v10/webhooks/{application_id}/{interaction_token}`
- ✅ Sends follow-up messages when server is ready
- ✅ Includes server IP and FQDN in follow-up message

**Implementation**: `SendFollowUpMessage()` method

### 5. Interaction Types Handled
**Requirement**: Must handle all relevant interaction types.

**Status**: ✅ **IMPLEMENTED**
- ✅ Type 1: PING → Returns PONG
- ✅ Type 2: APPLICATION_COMMAND → Handles slash commands

**Implementation**: `HandleDiscordInteractionAsync()` method

### 6. Error Handling
**Requirement**: Must handle errors gracefully and return appropriate responses.

**Status**: ✅ **IMPLEMENTED**
- ✅ Returns error messages with `flags: 64` (ephemeral)
- ✅ Logs errors for debugging
- ✅ Returns HTTP 401 for invalid signatures
- ✅ Returns HTTP 500 for internal errors

**Implementation**: Error handling in `Run()` and command handlers

### 7. Content-Type Headers
**Requirement**: Must set `Content-Type: application/json` in responses.

**Status**: ✅ **IMPLEMENTED**
- ✅ All responses include `Content-Type: application/json` header

**Implementation**: Response headers set in `Run()` method

## 🔧 Configuration Required

### Discord Public Key Setup

The Discord public key is required for signature verification. To get it:

1. **Go to Discord Developer Portal**: https://discord.com/developers/applications
2. **Select your application**
3. **Go to "General Information"**
4. **Copy the "Public Key"** (64-character hex string)
5. **Store in Key Vault**:
   ```powershell
   az keyvault secret set `
     --vault-name "valheim-kv-XXXXX" `
     --name "DiscordPublicKey" `
     --value "YOUR_PUBLIC_KEY_HERE"
   ```

Or set as environment variable:
```powershell
az functionapp config appsettings set `
  --resource-group "valheim-server-rg" `
  --name "valheim-func-XXXXX" `
  --settings "DISCORD_PUBLIC_KEY=YOUR_PUBLIC_KEY_HERE"
```

## 📋 Implementation Details

### Signature Verification Flow

1. **Extract Headers**: Get `X-Signature-Ed25519` and `X-Signature-Timestamp`
2. **Get Public Key**: Retrieve from Key Vault or environment variable
3. **Construct Message**: `timestamp + body`
4. **Verify Signature**: Use ed25519 to verify signature against public key
5. **Reject if Invalid**: Return 401 Unauthorized if verification fails

### Response Flow

1. **PING (Type 1)**: Immediately return PONG (Type 1)
2. **APPLICATION_COMMAND (Type 2)**:
   - **Immediate Commands** (`stop`, `status`): Return Type 4 response
   - **Async Commands** (`start`): Return Type 5 (deferred), then send follow-up via webhook

### Security Considerations

- ✅ **Signature Verification**: All requests verified before processing
- ✅ **Public Key Storage**: Stored securely in Key Vault
- ✅ **Error Logging**: Invalid requests logged for security monitoring
- ✅ **No Sensitive Data**: Bot token not exposed in responses

## 🧪 Testing

### Test Signature Verification

```powershell
# Test with invalid signature (should return 401)
Invoke-WebRequest -Uri "https://valheim-func-XXXXX.azurewebsites.net/api/DiscordBot" `
  -Method Post `
  -Headers @{
    "X-Signature-Ed25519" = "invalid"
    "X-Signature-Timestamp" = "1234567890"
  } `
  -Body '{"type":1}'
```

### Test Valid Interaction

Use Discord's slash command in your server - it will automatically include valid signatures.

## 📚 References

- [Discord Interactions Overview](https://discord.com/developers/docs/interactions/overview)
- [Security and Authorization](https://discord.com/developers/docs/interactions/receiving-and-responding#security-and-authorization)
- [Interaction Response Types](https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-response-object-interaction-callback-type)
- [Follow-up Messages](https://discord.com/developers/docs/interactions/receiving-and-responding#followup-messages)
