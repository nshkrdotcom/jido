# Getting Started with Jido

Welcome to Jido! This guide will introduce you to building composable, maintainable workflows using Jido's action-based architecture. Whether you're building complex business processes, integrating multiple services, or orchestrating distributed tasks, Jido provides a robust foundation for your workflows.

## Understanding Jido's Core Concepts

Before we dive into code, let's understand why Jido exists and when you should use it. 

### Why Actions?

You might be wondering: "Why should I wrap my code in Actions when I could just write regular Elixir functions?" This is an excellent question. The truth is, if you're building a standard Elixir application without agents, you probably shouldn't use Actions – regular Elixir modules and functions would be simpler and more direct.

Actions exist specifically to support agent systems. When you're building agents that need to make autonomous decisions about what steps to take, you need a way to package functionality into discrete, composable units that the agent can reason about and combine in novel ways. Think of Actions as LEGO bricks for agents – standardized, well-described building blocks that can be assembled in different combinations to solve problems.

The Action system provides several critical features for agent-based systems:
- Standardized metadata that agents can use to understand what each Action does
- Schema validation to ensure inputs are correct before execution
- Consistent error handling and compensation patterns
- Built-in telemetry and observability
- Dynamic composition through workflows and chains

If you're not building agent systems, you should implement your logic directly in Elixir. But if you are working with agents, this foundation of composable Actions becomes essential for enabling autonomous behavior.

Now, let's understand the key concepts that make up Jido:

### Actions
An Action is the fundamental building block in Jido. Think of an Action as a single, well-defined task that takes some input, performs a specific operation, and produces an output. Actions are designed to be small, focused, and composable – like UNIX commands that you can pipe together.

For example, an Action might:
- Format and validate user input
- Call an external API
- Transform data
- Send a notification

### Workflows
A Workflow is a sequence of Actions that work together to accomplish a larger goal. Workflows can be as simple as two Actions in sequence or as complex as dozens of Actions with conditional paths and error handling. The power of Jido comes from being able to compose simple Actions into sophisticated Workflows.

### Chains
A Chain is how we connect Actions together into a Workflow. When you chain Actions, the output of each Action becomes available to the next Action in the chain. Think of it like a pipeline where data flows through each step, getting enriched or transformed along the way.

Now, let's see how to build these concepts in practice.

## Setting Up Your Project

First, add Jido to your project's dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Creating Your First Action

Let's create a simple Action that formats user data. This example will help you understand the basic structure of an Action and how Jido handles data transformation.

```elixir
defmodule MyApp.Actions.FormatUser do
  use Jido.Action,
    name: "format_user",
    description: "Formats user data by trimming whitespace and normalizing email",
    schema: [
      name: [
        type: :string, 
        required: true,
        doc: "User's full name - will be trimmed"
      ],
      email: [
        type: :string,
        required: true,
        doc: "Email address - will be converted to lowercase"
      ],
      age: [
        type: :integer,
        required: true,
        doc: "User's age in years"
      ]
    ]

  @impl true
  def run(params, _context) do
    %{name: name, email: email, age: age} = params

    {:ok, %{
      formatted_name: String.trim(name),
      email: String.downcase(email),
      age: age,
      is_adult: age >= 18
    }}
  end
end
```

Let's break down what's happening here:

1. We define our Action as a module using `use Jido.Action`
2. We provide metadata about our Action:
   - `name`: A unique identifier for the Action
   - `description`: What the Action does
   - `schema`: The expected input parameters and their types
3. We implement the `run/2` callback which contains our Action's logic
4. We return a tuple `{:ok, result}` with our transformed data

The schema is particularly important – it's how Jido validates input before running your Action. If someone tries to run this Action with invalid input (like a missing email or an age that's not a number), Jido will return an error before your code even runs.

## Running Your First Action

There are two ways to run an Action. Let's understand both approaches:

### 1. Direct Execution

The simplest way to run an Action is to call it directly:

```elixir
# Notice the trailing space in name and uppercase email - our Action will clean these
{:ok, result} = FormatUser.run(%{
  name: "John Doe ",          
  email: "JOHN@EXAMPLE.COM",  
  age: 30
})
```

This will give us:
```elixir
%{
  formatted_name: "John Doe",    # Space removed
  email: "john@example.com",     # Converted to lowercase
  age: 30,
  is_adult: true                 # Derived from age
}
```

Direct execution is great for testing and development, but it doesn't give you all of Jido's runtime features.

### 2. Using the Workflow Runtime

For production use, you'll want to use Jido's Workflow runtime:

```elixir
{:ok, result} = Jido.Workflow.run(FormatUser, %{
  name: "John Doe",
  email: "john@example.com",
  age: 30
})
```

The Workflow runtime provides several benefits:
- Telemetry events for monitoring
- Consistent error handling
- Timeout management
- Retries and circuit breaking
- Context passing

## Building More Complex Actions

Now that we understand basic Actions, let's create two more that we'll use to build a complete user registration workflow:

```elixir
defmodule MyApp.Actions.EnrichUserData do
  use Jido.Action,
    name: "enrich_user_data",
    description: "Adds username and avatar URL to user data",
    schema: [
      formatted_name: [type: :string, required: true],
      email: [type: :string, required: true]
    ]

  def run(%{formatted_name: name, email: email}, _context) do
    {:ok, %{
      username: generate_username(name),
      avatar_url: get_gravatar_url(email)
    }}
  end

  defp generate_username(name) do
    name
    |> String.downcase()
    |> String.replace(" ", ".")
  end

  defp get_gravatar_url(email) do
    hash = :crypto.hash(:md5, email) |> Base.encode16(case: :lower)
    "https://www.gravatar.com/avatar/#{hash}"
  end
end

defmodule MyApp.Actions.NotifyUser do
  use Jido.Action,
    name: "notify_user",
    description: "Sends welcome notification to user",
    schema: [
      email: [type: :string, required: true],
      username: [type: :string, required: true]
    ]

  def run(%{email: email, username: username}, _context) do
    # In a real app, you'd send an actual email
    Logger.info("Sending welcome email to #{email}")
    
    {:ok, %{
      notification_sent: true,
      notification_type: "welcome_email",
      recipient: %{
        email: email,
        username: username
      }
    }}
  end
end
```

Each Action has a single responsibility and clearly defined inputs and outputs. This modularity makes our code easier to test and maintain.

## Chaining Actions Together

Now comes the powerful part – we can chain these Actions together to create a complete user registration workflow. When we chain Actions, the output of each Action is automatically merged with the existing data and passed to the next Action.

```elixir
{:ok, result} = Chain.chain(
  [
    FormatUser,
    EnrichUserData,
    NotifyUser
  ],
  %{
    name: "John Doe",
    email: "john@example.com",
    age: 30
  }
)
```

Here's what happens in this chain:

1. `FormatUser` runs first:
   - Takes the raw input
   - Formats the name and email
   - Adds the is_adult flag

2. `EnrichUserData` runs next:
   - Gets the formatted name and email from previous step
   - Adds username and avatar URL
   - Results are merged with existing data

3. `NotifyUser` runs last:
   - Uses the email and username from previous steps
   - Sends the notification
   - Adds notification status to results

The final result contains all the accumulated data:
```elixir
%{
  formatted_name: "John Doe",
  email: "john@example.com",
  age: 30,
  is_adult: true,
  username: "john.doe",
  avatar_url: "https://www.gravatar.com/avatar/...",
  notification_sent: true,
  notification_type: "welcome_email",
  recipient: %{
    email: "john@example.com",
    username: "john.doe"
  }
}
```

## Advanced Chain Features

As your workflows grow more complex, Jido provides several advanced features:

### Passing Context

Context lets you provide additional data that any Action in the chain can access:

```elixir
Chain.chain(
  [FormatUser, EnrichUserData, NotifyUser],
  user_data,
  context: %{
    tenant_id: "123",
    environment: "test"
  }
)
```

This is useful for passing configuration, authentication info, or other cross-cutting concerns.

### Overriding Parameters

You can override specific parameters for individual Actions in the chain:

```elixir
Chain.chain(
  [
    {FormatUser, [name: "Jane Doe"]},  # Override name just for this Action
    EnrichUserData,
    NotifyUser
  ],
  user_data
)
```

This is particularly useful when you need to customize behavior for specific cases.

### Async Execution

For long-running workflows, you can run Actions asynchronously:

```elixir
# Start the workflow
async_ref = Jido.Workflow.run_async(FormatUser, user_data)

# Do other work...

# Get the result when you need it
{:ok, result} = Jido.Workflow.await(async_ref)
```

## Testing Your Actions

Testing is a crucial part of working with Jido. Here's how to test your Actions thoroughly:

```elixir
defmodule MyApp.Actions.UserRegistrationTest do
  use ExUnit.Case, async: true
  
  @valid_user_data %{
    name: "John Doe ",
    email: "JOHN@EXAMPLE.COM",
    age: 30
  }
  
  describe "individual action tests" do
    test "FormatUser formats and validates user data" do
      {:ok, result} = FormatUser.run(@valid_user_data, %{})
      
      assert result.formatted_name == "John Doe"
      assert result.email == "john@example.com"
      assert result.is_adult == true
    end
  end
  
  describe "chaining actions" do
    test "chains all user registration actions together" do
      {:ok, result} = Chain.chain(
        [FormatUser, EnrichUserData, NotifyUser],
        @valid_user_data
      )
      
      assert result.formatted_name == "John Doe"
      assert result.username == "john.doe"
      assert result.notification_sent == true
    end
    
    test "chain stops on first error" do
      invalid_data = %{@valid_user_data | email: nil}
      
      {:error, error} = Chain.chain(
        [FormatUser, EnrichUserData, NotifyUser],
        invalid_data
      )
      
      assert error.type == :validation_error
    end
  end
end
```

The complete test suite in `test/workflow/user_registration_test.exs` shows more examples, including:
- Testing async workflows
- Testing with context
- Testing parameter overrides
- Testing error conditions

## Best Practices

As you build with Jido, keep these principles in mind:

1. **Single Responsibility**: Each Action should do one thing well. If an Action is doing too much, split it into smaller Actions.

2. **Clear Contracts**: Use schemas to define clear input requirements. Document what each parameter is for.

3. **Error Handling**: Return clear error messages. Use the Error structs provided by Jido.

4. **Testing**: Test Actions both individually and in chains. Test happy paths and error cases.

5. **Stateless Design**: Actions should be stateless and idempotent when possible. Use context for state that needs to be shared.

6. **Documentation**: Document your Actions, especially any side effects or external dependencies.

## Next Steps

Now that you understand the basics, you can explore:

- More complex workflow patterns
- Error compensation and rollbacks
- Integration with external services
- Custom Action behaviors
- Telemetry and monitoring

The complete test suite provides many more examples and patterns to learn from.

Happy building with Jido!