using System.Collections.Immutable;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace ValheimServerFunctions.Tests.Helpers;

/// <summary>
/// Test implementation of FunctionContext for unit testing
/// </summary>
public class TestFunctionContext : FunctionContext
{
    private readonly ILoggerFactory _loggerFactory;
    
    public TestFunctionContext(ILoggerFactory? loggerFactory = null)
    {
        _loggerFactory = loggerFactory ?? new LoggerFactory();
    }
    
    public override string InvocationId => Guid.NewGuid().ToString();
    
    public override string FunctionId => "TestFunction";
    
    public override TraceContext TraceContext => new TestTraceContext();
    
    public override BindingContext BindingContext => new TestBindingContext();
    
    public override RetryContext RetryContext => null!;
    
    public override IServiceProvider InstanceServices { get; set; } = null!;
    
    public override FunctionDefinition FunctionDefinition => new TestFunctionDefinition();
    
    public ILoggerFactory LoggerFactory => _loggerFactory;
    
    public override IDictionary<object, object?> Items { get; set; } = new Dictionary<object, object?>();
    
    public override IInvocationFeatures Features => new TestInvocationFeatures();
}

public class TestInvocationFeatures : IInvocationFeatures
{
    T IInvocationFeatures.Get<T>() => default(T)!;
    void IInvocationFeatures.Set<T>(T instance) { }
    public IEnumerator<KeyValuePair<Type, object>> GetEnumerator() => Enumerable.Empty<KeyValuePair<Type, object>>().GetEnumerator();
    System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();
}

public class TestTraceContext : TraceContext
{
    public override string TraceParent => "00-00000000000000000000000000000000-0000000000000000-00";
    public override string TraceState => "";
    public System.Diagnostics.ActivityTraceFlags Flags => System.Diagnostics.ActivityTraceFlags.None;
}

public class TestBindingContext : BindingContext
{
    public override IReadOnlyDictionary<string, object?> BindingData => new Dictionary<string, object?>();
}

// Simplified - we'll stub out the binding properties
// The actual FunctionBinding type is internal to the SDK, so we use dynamic
public class TestFunctionDefinition : FunctionDefinition
{
    public override string Id => "TestFunction";
    public override string Name => "TestFunction";
    public override string EntryPoint => "";
    public override string PathToAssembly => "";
    public override ImmutableArray<FunctionParameter> Parameters => ImmutableArray<FunctionParameter>.Empty;
    
    // Use the actual BindingMetadata type from the SDK
    // This will work if BindingMetadata is accessible, otherwise we'll need to use InternalsVisibleTo
    public override IImmutableDictionary<string, Microsoft.Azure.Functions.Worker.BindingMetadata> InputBindings 
        => ImmutableDictionary<string, Microsoft.Azure.Functions.Worker.BindingMetadata>.Empty;
    
    public override IImmutableDictionary<string, Microsoft.Azure.Functions.Worker.BindingMetadata> OutputBindings 
        => ImmutableDictionary<string, Microsoft.Azure.Functions.Worker.BindingMetadata>.Empty;
}
