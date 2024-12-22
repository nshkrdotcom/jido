# Getting Started with Jido

Welcome to the **Jido** Elixir module! This guide is designed to help you get up and running with Jido, even if you've never built anything with agents before. We'll walk you through writing actions, combining them into workflow commands, loading these commands into an agent, defining and running an agent, and finally integrating your agent into a Phoenix supervision tree to send commands via PubSub.

## Table of Contents

1. [Introduction](#introduction)
2. [Writing Actions](#writing-actions)
   - [Defining an Action](#defining-an-action)
   - [Example: Creating a Simple Log Action](#example-creating-a-simple-log-action)
3. [Writing and Combining Actions into Workflow Commands](#writing-and-combining-actions-into-workflow-commands)
   - [Defining a Command](#defining-a-command)
   - [Combining Actions into a Command](#combining-actions-into-a-command)
   - [Example: Creating a Greeting Command](#example-creating-a-greeting-command)
4. [Loading Commands into an Agent](#loading-commands-into-an-agent)
   - [Defining an Agent](#defining-an-agent)
   - [Assigning Commands to the Agent](#assigning-commands-to-the-agent)
   - [Example: Setting Up a Basic Agent](#example-setting-up-a-basic-agent)
5. [Running an Agent](#running-an-agent)
   - [Starting the Agent](#starting-the-agent)
   - [Sending Commands to the Agent](#sending-commands-to-the-agent)
   - [Example: Executing a Command](#example-executing-a-command)
6. [Integrating with Phoenix Supervision Tree](#integrating-with-phoenix-supervision-tree)
   - [Adding the Agent to the Supervision Tree](#adding-the-agent-to-the-supervision-tree)
   - [Sending Commands via PubSub](#sending-commands-via-pubsub)
   - [Example: Supervising the Agent in Phoenix](#example-supervising-the-agent-in-phoenix)
7. [Conclusion](#conclusion)

---

## Introduction

**Jido** is a robust Elixir framework designed to manage complex workflows through agents and actions. By leveraging Elixir's powerful concurrency and fault-tolerance features, Jido allows you to define reusable actions, combine them into commands, and orchestrate these commands within agents. This guide will help you harness the full potential of Jido to build scalable and maintainable applications.

---

## Writing Actions

Actions are the fundamental building blocks in Jido. They represent discrete operations that your agent can perform, such as logging messages, manipulating data, or interacting with external systems.

### Defining an Action

To define an action in Jido, you need to create a module that uses the `Jido.Action` behaviour. This involves specifying the action's name, description, and schema (input parameters). Each action must implement the `run/2` function, which contains the logic to execute the action.

Here's a breakdown of the steps:

1. **Use the `Jido.Action` behaviour:**
   ```elixir
   use Jido.Action,
     name: "action_name",
     description: "Description of the action",
     schema: [
       param1: [type: :string, required: true],
       param2: [type: :integer, default: 10]
     ]
Implement the run/2 function:
elixir
Copy code
@impl true
def run(params, _context) do
  # Action logic here
  {:ok, %{result: "Action executed successfully"}}
end
Example: Creating a Simple Log Action
Let's create a simple action that logs a message.

elixir
Copy code
defmodule Jido.Actions.Basic.Log do
  @moduledoc """
  Logs a message with a specified level.
  """

  use Jido.Action,
    name: "log_action",
    description: "Logs a message at a specified log level",
    schema: [
      level: [type: {:in, [:debug, :info, :warn, :error]}, default: :info, doc: "Log level"],
      message: [type: :string, required: true, doc: "Message to log"]
    ]

  require Logger

  @impl true
  def run(%{level: level, message: message}, _context) do
    case level do
      :debug -> Logger.debug(message)
      :info -> Logger.info(message)
      :warn -> Logger.warn(message)
      :error -> Logger.error(message)
    end

    {:ok, %{message: "Logged at #{level} level"}}
  end
end
Explanation:

Module Definition: We define a module Jido.Actions.Basic.Log that uses the Jido.Action behaviour.
Action Metadata: We specify the action's name as "log_action", provide a description, and define the schema for input parameters.
Run Function: The run/2 function logs the provided message at the specified log level using Elixir's Logger module.
Writing and Combining Actions into Workflow Commands
Commands in Jido are sequences of actions that define a complete workflow. By combining multiple actions into a single command, you can orchestrate complex operations within your agents.

Defining a Command
To define a command, you create a module that uses the Jido.Command behaviour. Commands specify a list of actions that should be executed in order when the command is invoked.

elixir
Copy code
defmodule Jido.Commands.MyCommand do
  @moduledoc """
  A command that performs a series of actions.
  """

  use Jido.Command

  alias Jido.Actions.Basic.Log
  alias Jido.Actions.Basic.Sleep

  @impl true
  def commands do
    [
      my_workflow: [
        description: "Performs a custom workflow",
        schema: [
          user: [type: :string, required: true],
          delay: [type: :integer, default: 1000]
        ]
      ]
    ]
  end

  @impl true
  def handle_command(:my_workflow, _agent, %{user: user, delay: delay}) do
    {:ok, [
      {Log, level: :info, message: "Starting workflow for #{user}"},
      {Sleep, duration_ms: delay},
      {Log, level: :info, message: "Completed workflow for #{user}"}
    ]}
  end
end
Combining Actions into a Command
In the above example, the command :my_workflow combines three actions:

Log Action: Logs the start of the workflow.
Sleep Action: Introduces a delay.
Log Action: Logs the completion of the workflow.
By structuring commands this way, you can create reusable and modular workflows that agents can execute.

Example: Creating a Greeting Command
Let's create a command that greets a user, waits for a moment, and then says goodbye.

elixir
Copy code
defmodule Jido.Commands.GreetCommand do
  @moduledoc """
  A command that greets a user, waits, and then bids farewell.
  """

  use Jido.Command

  alias Jido.Actions.Basic.Log
  alias Jido.Actions.Basic.Sleep

  @impl true
  def commands do
    [
      greet: [
        description: "Greets a user and says goodbye after a delay",
        schema: [
          name: [type: :string, required: true],
          delay: [type: :integer, default: 1000, doc: "Delay in milliseconds"]
        ]
      ]
    ]
  end

  @impl true
  def handle_command(:greet, _agent, %{name: name, delay: delay}) do
    {:ok, [
      {Log, level: :info, message: "Hello, #{name}!"},
      {Sleep, duration_ms: delay},
      {Log, level: :info, message: "Goodbye, #{name}!"}
    ]}
  end
end
Explanation:

Command Definition: The :greet command takes a name and an optional delay.
Action Sequence: It logs a greeting, sleeps for the specified duration, and then logs a farewell.
Schema Validation: The command ensures that the name parameter is provided and that delay defaults to 1000 milliseconds if not specified.
Loading Commands into an Agent
Agents in Jido are entities that manage and execute commands. By loading commands into an agent, you equip it with the ability to perform predefined workflows.

Defining an Agent
To define an agent, you create a module that uses the Jido.Agent behaviour. Agents have unique names, descriptions, categories, tags, versions, commands, and schemas for their state.

elixir
Copy code
defmodule MyApp.Agents.GreetingAgent do
  @moduledoc """
  An agent that handles greeting workflows.
  """

  use Jido.Agent,
    name: "greeting_agent",
    description: "Handles greeting and farewell workflows",
    category: "communication",
    tags: ["greeting", "farewell"],
    vsn: "1.0.0",
    commands: [Jido.Commands.GreetCommand],
    schema: [
      last_greeted: [type: :string, default: nil]
    ]
end
Assigning Commands to the Agent
When defining the agent, you specify the list of commands it can execute via the commands option. This ensures that the agent knows how to handle each command when invoked.

Example:

In the GreetingAgent above, we assigned the GreetCommand:

elixir
Copy code
commands: [Jido.Commands.GreetCommand]
This tells the agent to use the GreetCommand module when handling the :greet command.

Example: Setting Up a Basic Agent
Let's set up an agent that can handle greeting commands.

elixir
Copy code
defmodule MyApp.Agents.BasicGreetingAgent do
  @moduledoc """
  A basic agent that performs greeting workflows.
  """

  use Jido.Agent,
    name: "basic_greeting_agent",
    description: "Performs basic greeting workflows",
    category: "utility",
    tags: ["greeting", "basic"],
    vsn: "1.0.0",
    commands: [Jido.Commands.GreetCommand],
    schema: [
      last_greeted: [type: :string, default: nil]
    ]
end
Explanation:

Name & Description: Identifies the agent and describes its purpose.
Category & Tags: Helps categorize and tag the agent for easier management.
Version (vsn): Tracks the agent's version.
Commands: Assigns the GreetCommand to the agent.
Schema: Defines the agent's state, in this case, tracking the last_greeted user.
Running an Agent
Once you've defined your agent and loaded it with commands, it's time to run the agent and execute commands.

Starting the Agent
Agents are typically started under a supervision tree to ensure they are monitored and can recover from failures.

Example:

elixir
Copy code
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start the PubSub system
      {Phoenix.PubSub, name: MyApp.PubSub},
      
      # Start the Greeting Agent
      {MyApp.Agents.BasicGreetingAgent, []}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
Explanation:

Phoenix.PubSub: Initializes the PubSub system required for communication.
BasicGreetingAgent: Starts the agent under the supervision tree.
Sending Commands to the Agent
Commands can be sent to the agent either synchronously or asynchronously.

Synchronous (act/3): Waits for the command to complete and returns the result.
Asynchronous (act_async/3): Sends the command without waiting for completion.
Example: Sending a Synchronous Command

elixir
Copy code
{:ok, new_state} = Jido.Agent.act(MyApp.Agents.BasicGreetingAgent, :greet, %{name: "Alice"})
Example: Sending an Asynchronous Command

elixir
Copy code
:ok = Jido.Agent.act_async(MyApp.Agents.BasicGreetingAgent, :greet, %{name: "Bob"})
Example: Executing a Command
Let's execute the :greet command to greet a user named "Charlie".

elixir
Copy code
defmodule MyApp.GreetingController do
  use MyAppWeb, :controller

  alias Jido.Agent

  def greet(conn, %{"name" => name}) do
    case Agent.act(MyApp.Agents.BasicGreetingAgent, :greet, %{name: name}) do
      {:ok, _new_state} ->
        text(conn, "Greeting sent to #{name}!")

      {:error, reason} ->
        text(conn, "Failed to send greeting: #{reason}")
    end
  end
end
Explanation:

Controller Action: Defines a greet action that takes a name parameter from the request.
Sending the Command: Uses Agent.act/3 to send the :greet command synchronously.
Handling the Response: Returns a success message if the command executes successfully or an error message otherwise.
Integrating with Phoenix Supervision Tree
Integrating your Jido agent into a Phoenix application ensures that it is properly supervised and can recover from unexpected failures. Additionally, using Phoenix's PubSub system allows you to send commands to the agent from different parts of your application.

Adding the Agent to the Supervision Tree
To add your agent to the Phoenix supervision tree, include it in the list of children in your application's start/2 function.

Example:

elixir
Copy code
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start the PubSub system
      {Phoenix.PubSub, name: MyApp.PubSub},
      
      # Start the Greeting Agent
      {MyApp.Agents.BasicGreetingAgent, []}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
Sending Commands via PubSub
You can send commands to the agent using Phoenix's PubSub system. This allows different parts of your application to communicate with the agent without direct process references.

Steps:

Broadcast a Command Message:

elixir
Copy code
Phoenix.PubSub.broadcast(MyApp.PubSub, "agent_commands", {:greet, %{name: "Diana"}})
Subscribe to the Command Topic in the Agent:

Modify your agent to listen to the agent_commands topic.

elixir
Copy code
defmodule MyApp.Agents.BasicGreetingAgent do
  @moduledoc """
  A basic agent that performs greeting workflows.
  """

  use Jido.Agent,
    name: "basic_greeting_agent",
    description: "Performs basic greeting workflows",
    category: "utility",
    tags: ["greeting", "basic"],
    vsn: "1.0.0",
    commands: [Jido.Commands.GreetCommand],
    schema: [
      last_greeted: [type: :string, default: nil]
    ]

  @impl true
  def on_before_validate_state(state), do: {:ok, state}

  @impl true
  def on_after_validate_state(state), do: {:ok, state}

  @impl true
  def on_before_plan(agent, command, params), do: {:ok, {command, params}}

  @impl true
  def on_before_run(agent, actions), do: {:ok, actions}

  @impl true
  def on_after_run(agent, result), do: {:ok, result}

  @impl true
  def on_error(agent, error, context), do: {:error, error}
end
Handle Incoming PubSub Messages:

Ensure that your agent is subscribed to the agent_commands topic. This is typically handled during the agent's initialization.

elixir
Copy code
defmodule MyApp.Agents.BasicGreetingAgent do
  # ... existing code ...

  @impl true
  def init(%{agent: agent, pubsub: pubsub, topic: topic, max_queue_size: max_queue_size}) do
    # ... existing initialization ...

    # Subscribe to the agent_commands topic
    Phoenix.PubSub.subscribe(pubsub, "agent_commands")

    # ... rest of the initialization ...
  end
end
Example: Supervising the Agent in Phoenix
Here's how you can integrate the BasicGreetingAgent into your Phoenix application's supervision tree and send it commands via PubSub.

Update application.ex:

elixir
Copy code
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start the PubSub system
      {Phoenix.PubSub, name: MyApp.PubSub},
      
      # Start the Greeting Agent
      {MyApp.Agents.BasicGreetingAgent, []}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
Send a Command via PubSub:

You can broadcast a command from anywhere in your Phoenix application, such as a controller or a LiveView.

elixir
Copy code
defmodule MyAppWeb.GreetingController do
  use MyAppWeb, :controller

  alias Phoenix.PubSub

  def send_greeting(conn, %{"name" => name}) do
    PubSub.broadcast(MyApp.PubSub, "agent_commands", {:greet, %{name: name}})
    text(conn, "Greeting command sent to #{name}!")
  end
end
Handle the Command in the Agent:

Ensure that your agent is listening to the agent_commands topic and handles incoming :greet commands.

elixir
Copy code
defmodule MyApp.Agents.BasicGreetingAgent do
  use Jido.Agent,
    name: "basic_greeting_agent",
    # ... other options ...
    commands: [Jido.Commands.GreetCommand],
    # ... schema ...

  @impl true
  def init(state) do
    # Subscribe to the agent_commands topic
    Phoenix.PubSub.subscribe(state.pubsub, "agent_commands")
    super(state)
  end

  @impl true
  def handle_info({:greet, params}, state) do
    Agent.act_async(self(), :greet, params)
    {:noreply, state}
  end
end
Explanation:

Supervision Tree: The agent is added as a child to the supervision tree in application.ex.
Broadcasting Commands: The GreetingController sends a greeting command by broadcasting to the agent_commands topic.
Agent Subscription: The agent subscribes to the agent_commands topic during initialization and handles incoming :greet commands by invoking act_async/3.
Conclusion
Congratulations! You've successfully set up Jido in your Elixir Phoenix application. By defining actions, combining them into commands, loading these commands into agents, and integrating agents into your supervision tree, you can build powerful, scalable, and maintainable workflows. Jido leverages Elixir's strengths in concurrency and fault-tolerance, providing a solid foundation for complex distributed systems.

Feel free to explore more advanced features of Jido, such as custom lifecycle hooks, dynamic command loading, and integrating with other Elixir libraries to further enhance your application's capabilities.

Happy coding!