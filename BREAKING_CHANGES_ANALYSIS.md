# Breaking Changes Analysis: Jido Agent Type System Refactor

## Overview

This document analyzes the breaking changes introduced by the Jido Agent type system refactor that centralizes all agent structs to use a single `%Jido.Agent{}` type instead of individual agent-specific structs like `%CallbackTrackingAgent{}`.

## Breaking Changes Summary

### 1. Struct Type Unification
- **Before**: Each agent had its own struct (`%CallbackTrackingAgent{}`, `%BasicAgent{}`, etc.)
- **After**: All agents use the base `%Jido.Agent{}` struct
- **Impact**: Direct struct construction in tests and other code fails

### 2. Removed defstruct from Macro
- **Before**: `defstruct @struct_keys` generated agent-specific structs
- **After**: No `defstruct` in the macro, only base `Jido.Agent` struct exists
- **Impact**: Modules no longer have their own struct definition

### 3. Constructor Changes
- **Before**: `struct(__MODULE__, ...)` created agent-specific structs
- **After**: `%Jido.Agent{...}` creates base struct with all fields
- **Impact**: All agents now have the same struct shape

### 4. Pattern Matching Updates
- **Before**: Functions matched on `%__MODULE__{}`
- **After**: Functions match on `%Jido.Agent{}`
- **Impact**: More consistent but breaks existing pattern matches

### 5. Type Specification Changes
- **Before**: `@type t :: %__MODULE__{}`
- **After**: `@type t :: %Jido.Agent{}`
- **Impact**: Type system now unified but breaks existing type assumptions

## Root Cause Analysis

The changes were made to address **37 Dialyzer type system violations** by:

1. **Centralizing type definitions** - Single source of truth for agent structure
2. **Eliminating type inconsistencies** - All agents now have the same base type
3. **Simplifying internal handling** - No need to handle different struct types
4. **Improving type safety** - Dialyzer can better understand the unified type system

## Impact Assessment

### Test Failures
- **Primary Issue**: `test/jido/agent/server_callback_test.exs:10` - Direct struct construction fails
- **Error**: `CallbackTrackingAgent.__struct__/1 is undefined`
- **Scope**: Any code that directly constructs agent structs

### Affected Code Patterns
```elixir
# This no longer works:
agent = %CallbackTrackingAgent{
  id: Jido.Util.generate_id(),
  state: %{...},
  # ... other fields
}

# This is now required:
agent = %Jido.Agent{
  id: Jido.Util.generate_id(),
  name: "callback_tracking_agent",
  state: %{...},
  # ... other fields
}
```

## Proposed Solutions

### Option 1: Backwards Compatibility Layer (Recommended)
Maintain both struct types but internally use `Jido.Agent`:

```elixir
# In the macro, add:
@struct_keys Keyword.keys(@agent_server_schema)
defstruct @struct_keys

# Override __struct__ to return Jido.Agent:
def __struct__(fields \\ []) do
  base_fields = [
    id: nil,
    name: @validated_opts[:name],
    description: @validated_opts[:description],
    # ... other base fields
  ]
  
  struct(Jido.Agent, Keyword.merge(base_fields, fields))
end
```

**Pros**: 
- Zero breaking changes
- Maintains API compatibility
- Still achieves type system goals
- Gradual migration path

**Cons**: 
- Slightly more complex implementation
- Maintains dual struct approach

### Option 2: Constructor Function Approach
Replace direct struct construction with constructor functions:

```elixir
# Add to each agent module:
def new(id, opts \\ []) do
  %Jido.Agent{
    id: id,
    name: "callback_tracking_agent",
    # ... populate from opts
  }
end
```

**Pros**:
- Clean API
- Type safety maintained
- Flexible construction

**Cons**:
- Still breaks existing code
- Requires updating all construction sites

### Option 3: Update All Usage Sites
Simply update all code to use `%Jido.Agent{}`:

**Pros**:
- Cleanest long-term solution
- No complexity overhead
- Fully unified type system

**Cons**:
- Maximum breaking change impact
- Requires updating all tests and dependent code

## Recommended Implementation Plan

### Phase 1: Backwards Compatibility (Immediate)
1. Restore `defstruct` in the macro with compatibility layer
2. Make `%AgentModule{}` construction work but return `%Jido.Agent{}`
3. Update pattern matching to accept both types
4. Ensure type specs work with both approaches

### Phase 2: Migration Support (Next Release)
1. Add deprecation warnings for direct struct construction
2. Provide migration tools/documentation
3. Update all internal usage to new patterns

### Phase 3: Full Migration (Future Release)
1. Remove backwards compatibility layer
2. Migrate all remaining usage sites
3. Simplify to single struct approach

## Technical Implementation Details

### Compatibility Layer Structure
```elixir
# In the macro quote block:
@struct_keys Keyword.keys(@agent_server_schema)
defstruct @struct_keys

# Custom __struct__ that returns Jido.Agent
def __struct__(fields \\ []) do
  base_agent_fields = [
    id: nil,
    name: @validated_opts[:name],
    description: @validated_opts[:description],
    category: @validated_opts[:category],
    tags: @validated_opts[:tags],
    vsn: @validated_opts[:vsn],
    schema: @validated_opts[:schema],
    actions: @validated_opts[:actions] || [],
    runner: @validated_opts[:runner],
    dirty_state?: false,
    pending_instructions: :queue.new(),
    state: %{},
    result: nil
  ]
  
  struct(Jido.Agent, Keyword.merge(base_agent_fields, fields))
end
```

### Pattern Matching Updates
```elixir
# Functions should accept both patterns:
def set(%Jido.Agent{} = agent, attrs, opts), do: # implementation
def set(%{__struct__: module} = agent, attrs, opts) when module != Jido.Agent do
  # Convert to Jido.Agent and delegate
  jido_agent = struct(Jido.Agent, Map.from_struct(agent))
  set(jido_agent, attrs, opts)
end
```

## Testing Strategy

### Validation Tests
1. **Backwards Compatibility**: Ensure `%CallbackTrackingAgent{}` construction works
2. **Type Consistency**: Verify all agents return `%Jido.Agent{}` internally
3. **Pattern Matching**: Test both old and new patterns work
4. **Dialyzer Compliance**: Confirm type system violations are resolved

### Migration Tests
1. **Gradual Migration**: Test mixed usage patterns
2. **Deprecation Warnings**: Verify warnings are shown appropriately
3. **Full Migration**: Test complete migration to new approach

## Risk Assessment

### Low Risk
- Backwards compatibility approach maintains existing API
- Type system benefits are preserved
- Migration can be gradual

### Medium Risk
- Increased complexity in macro implementation
- Need to maintain dual code paths temporarily
- Potential confusion during migration period

### High Risk
- Complete breaking change without compatibility layer
- Immediate failure of all dependent code
- Difficult rollback if issues arise

## Conclusion

The **backwards compatibility layer approach (Option 1)** is recommended as it:
- Maintains existing API contracts
- Achieves the type system goals
- Provides a safe migration path
- Minimizes immediate disruption

This approach allows the type system benefits to be realized while providing time for dependent code to migrate gracefully.