using System.Security.Cryptography;
using System.Text;
using NSec.Cryptography;

namespace ValheimServerFunctions.Tests.Helpers;

/// <summary>
/// Helper class to generate valid Discord signatures for testing
/// Based on Discord's signature verification algorithm: verify(timestamp + body, signature, public_key)
/// </summary>
public static class DiscordSignatureHelper
{
    /// <summary>
    /// Generates a valid ed25519 signature for Discord interaction testing
    /// </summary>
    public static (string PublicKeyHex, string SignatureHex, string Timestamp) GenerateValidSignature(string body)
    {
        // Generate a key pair for testing
        var algorithm = SignatureAlgorithm.Ed25519;
        var key = Key.Create(algorithm);
        var publicKey = key.PublicKey;
        
        // Use current timestamp
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        
        // Create message: timestamp + body (as per Discord spec)
        var message = Encoding.UTF8.GetBytes(timestamp + body);
        
        // Sign the message
        var signature = algorithm.Sign(key, message);
        
        // Convert to hex strings
        var publicKeyHex = Convert.ToHexString(publicKey.Export(KeyBlobFormat.RawPublicKey)).ToLowerInvariant();
        var signatureHex = Convert.ToHexString(signature).ToLowerInvariant();
        
        return (publicKeyHex, signatureHex, timestamp);
    }
    
    /// <summary>
    /// Generates an invalid signature (wrong key)
    /// </summary>
    public static (string PublicKeyHex, string SignatureHex, string Timestamp) GenerateInvalidSignature(string body)
    {
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        
        // Use a different key to sign, but return a different public key
        var algorithm = SignatureAlgorithm.Ed25519;
        var signingKey = Key.Create(algorithm);
        var wrongPublicKey = Key.Create(algorithm).PublicKey; // Different key!
        
        var message = Encoding.UTF8.GetBytes(timestamp + body);
        var signature = algorithm.Sign(signingKey, message);
        
        var publicKeyHex = Convert.ToHexString(wrongPublicKey.Export(KeyBlobFormat.RawPublicKey)).ToLowerInvariant();
        var signatureHex = Convert.ToHexString(signature).ToLowerInvariant();
        
        return (publicKeyHex, signatureHex, timestamp);
    }
}
