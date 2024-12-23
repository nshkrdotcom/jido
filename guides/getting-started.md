# Getting Started with Jido

Welcome to **Jido**, a powerful yet approachable Elixir framework for defining Agents that plan and execute _Actions_ organized by _Commands_ (collectively forming simple or complex workflows). If you’ve never built anything with Agents, Actions, or Commands before, this guide will help you get up and running step by step.

---

## Table of Contents

- [Getting Started with Jido](#getting-started-with-jido)
  - [Table of Contents](#table-of-contents)
  - [1. Overview of Jido Concepts](#1-overview-of-jido-concepts)
    - [Actions](#actions)
    - [Commands](#commands)
    - [Agents](#agents)
  - [2. Creating Your First Action](#2-creating-your-first-action)
    - [Action Explanation](#action-explanation)
      - [Schema](#schema)
      - [run/2 Function](#run2-function)
    - [Combining Actions into a Command](#combining-actions-into-a-command)
    - [Command Explanation](#command-explanation)
    - [Defining an Agent with Commands](#defining-an-agent-with-commands)
    - [Agent Explanation](#agent-explanation)
    - [Running the Agent](#running-the-agent)
- [Steps in detail:](#steps-in-detail)
- [We'll assume our runtime was started with name: "announcer\_1"](#well-assume-our-runtime-was-started-with-name-announcer_1)
- [... handle other events or unknown signals](#-handle-other-events-or-unknown-signals)

---

## 1. Overview of Jido Concepts

### Actions
An **Action** is a small, discrete piece of logic you can execute. 

Each Action:
- Implements the `Jido.Action` behavior.
- Defines a **schema** describing its parameters (which NimbleOptions validates).
- Has a `run/2` callback that does the work.

### Commands
A **Command** is essentially a _named_ group of Actions that the Agent can plan and then execute. 

Commands are:
- Implement the `Jido.Command` behavior.
- Define a list of possible **command specs** (like `:move`, `:greet`, etc.), each with its own parameter schema.
- Provide a `handle_command/3` function that returns a list of Actions (or a single Action) to be executed.

### Agents
An **Agent** in Jido is a data-driven entity that can hold state, register _Commands_, and run workflows composed of _Actions_. 

Agents:
- Have a **state schema** (defined via NimbleOptions) that validates state changes.
- Contain hooks (callbacks) for customizing behavior before/after validation, planning, execution, and error handling.
- Can be extended by registering more **Commands**.

The lifecycle looks something like this:
1. **Plan** a command with an Agent → validated and turned into pending Actions.
2. **Run** those pending Actions → applying changes to the Agent’s state.

There is a convenience function `act/4` that validates state, plans the command, and runs all pending Actions all in a single step.

---

## 2. Creating Your First Action

Let’s create a simple Action that logs a message. We’ll call it `LogMessage`.

```elixir
defmodule MyApp.Actions.LogMessage do
  @moduledoc """
  An Action that logs a message at a specified log level.
  """
  use Jido.Action,
    name: "log_message",
    description: "Logs a message",
    schema: [
      level: [type: {:in, [:debug, :info, :warning, :error]}, default: :info],
      message: [type: :string, required: true]
    ]

  require Logger

  @impl true
  def run(%{level: level, message: msg}, _context) do
    case level do
      :debug   -> Logger.debug(msg)
      :info    -> Logger.info(msg)
      :warning -> Logger.warning(msg, [])
      :error   -> Logger.error(msg)
    end

    # The return tuple of {:ok, new_params} indicates success
    {:ok, %{logged: true, message: msg}}
  end
end
```

### Action Explanation

The Action module above demonstrates two key concepts:

#### Schema
- Defines required parameters (`message`) and optional ones (`level`)
- Sets default values (`:info` for `level`)
- Validates parameter types and allowed values

#### run/2 Function
- Takes validated parameters and context as arguments
- Performs the actual logging operation
- Returns `{:ok, map()}` on success
  - The returned map can be passed to subsequent Actions in a workflow

### Combining Actions into a Command

Next, let's create a Command named `:announce` that logs two messages in sequence. We'll implement this in a new module `MyApp.Commands.Announcements` using the `Jido.Command` behavior:

```elixir
defmodule MyApp.Commands.Announcements do
  @moduledoc """
  A Command set for logging announcements.
  """
  use Jido.Command

  alias MyApp.Actions.LogMessage

  @impl true
  def commands do
    [
      # Command name is :announce
      announce: [
        description: "Logs two messages in sequence",
        schema: [
          msg1: [type: :string, required: true],
          msg2: [type: :string, required: true]
        ]
      ]
    ]
  end

  @impl true
  def handle_command(:announce, _agent, %{msg1: m1, msg2: m2}) do
    actions = [
      {LogMessage, message: m1, level: :info},
      {LogMessage, message: m2, level: :info}
    ]

    # Return an {:ok, actions_list} tuple
    {:ok, actions}
  end
end
```

### Command Explanation

The `commands/0` function declares what commands exist (in this case, `:announce`) and their parameter schemas.

The `handle_command/3` function converts the command call (`:announce`, agent, params) into a list of Actions that get executed.

### Defining an Agent with Commands

Now that we have a Command module (`MyApp.Commands.Announcements`), we want to define an Agent that can use it. Here's a minimal example:

```elixir
defmodule MyApp.Agents.AnnouncerAgent do
  @moduledoc """
  A simple Agent that can announce messages using commands from Announcements.
  """
  use Jido.Agent,
    name: "announcer_agent",
    description: "An agent that can log announcements",
    commands: [MyApp.Commands.Announcements],
    schema: [
      # optional schema fields for this Agent
      announcements_made: [type: :integer, default: 0]
    ]

  @impl true
  def on_before_plan(agent, :announce, params) do
    # Maybe we want to do some custom logic or transformations
    new_params = Map.put(params, :msg1, "[ANNOUNCE] " <> params.msg1)
    {:ok, {:announce, new_params}}
  end

  @impl true
  def on_after_run(agent, result) do
    # Suppose we track how many announcements we've done
    announcements_count = agent.state.announcements_made + 1
    new_state = %{agent.state | announcements_made: announcements_count}
    {:ok, %{result | state: new_state}}
  end
end
```

### Agent Explanation

The `use Jido.Agent` macro configures the agent with:
- A name and description for identification
- Command modules like `MyApp.Commands.Announcements` that define available commands
- A schema validated by NimbleOptions, with fields like `announcements_made` defaulting to 0

The agent provides lifecycle callbacks like `on_before_plan/3` that can be overridden to customize planning and execution.

### Running the Agent

Let's see how to plan and run a command:

```elixir
defmodule MyApp.Example do
  def run_demo do
    # 1. Create a new agent instance
    agent = MyApp.Agents.AnnouncerAgent.new()

    # 2. Plan the :announce command with the required params
    {:ok, planned_agent} =
      MyApp.Agents.AnnouncerAgent.plan(agent, :announce, %{msg1: "Hello", msg2: "World"})

    # 3. Execute all pending actions
    {:ok, final_agent} = MyApp.Agents.AnnouncerAgent.run(planned_agent)

    IO.inspect(final_agent.state, label: "Agent final state")
  end
end
```

# Steps in detail:

Create: MyApp.Agents.AnnouncerAgent.new().
Plan: plan(agent, :announce, %{msg1: "Hello", msg2: "World"}) → returns an updated agent with queued actions.
Run: run(agent) executes the queued actions (in this case, two LogMessage calls).
You’ll see the logs appear in your console, and the announcements_made field will be incremented to 1.

Shortcut: You can do everything in one shot with act/4:

elixir
Copy code
{:ok, final_agent} =
  MyApp.Agents.AnnouncerAgent.act(agent, :announce, %{msg1: "Hello", msg2: "World"})
This will validate state, plan the command, and run all pending actions, returning the updated agent.

6. Integrating an Agent in a Phoenix Application
Agents in Jido are often long-running processes so that external systems (HTTP requests, channels, etc.) can interact with them. A typical approach is:

Start a Runtime process (from Jido.Agent.Runtime) in your Phoenix application.ex.
Supervise that runtime so it stays alive, allowing commands to be dispatched to it via GenServer or PubSub.
For example, in your lib/my_app/application.ex:

```elixir
def start(_type, _args) do
  children = [
    # Start the Phoenix endpoint
    MyAppWeb.Endpoint,
    # Start the PubSub system
    {Phoenix.PubSub, name: MyApp.PubSub},
    # Start a Jido Runtime with our agent
    {
      Jido.Agent.Runtime,
      agent: MyApp.Agents.AnnouncerAgent.new("announcer_1"),
      pubsub: MyApp.PubSub
      # Optionally specify topic or max_queue_size, etc.
      # topic: "custom.topic"
    }
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

What happens here?

Jido.Agent.Runtime starts up with a specific agent instance. We give it a unique ID like "announcer_1".
We pass in pubsub: MyApp.PubSub so that it can broadcast/receive events on that named PubSub system.
Once it’s running, we can call Runtime.act/3, Runtime.manage/3, etc., on that PID or name.
7. Sending Commands via PubSub
Jido provides built-in support for PubSub signals. If you have the runtime started (as shown above), you can do something like:

elixir
Copy code
# We'll assume our runtime was started with name: "announcer_1"
alias Jido.Agent.Runtime

defmodule MyAppWeb.AnnounceController do
  use MyAppWeb, :controller

  @runtime_server {:via, Registry, {Jido.AgentRegistry, "announcer_1"}}

  def create(conn, %{"msg1" => msg1, "msg2" => msg2}) do
    # Asynchronously trigger announcement
    :ok = Runtime.act_async(@runtime_server, :announce, %{msg1: msg1, msg2: msg2})

    conn
    |> put_flash(:info, "Announcement queued!")
    |> redirect(to: "/announcements/new")
  end
end
Here’s what’s happening:

We define a @runtime_server referencing the Jido runtime process. Jido automatically registers it under Jido.AgentRegistry.
We call Runtime.act_async/3 to dispatch the :announce command. This enqueues and executes the command in our supervised agent process.
Phoenix.PubSub is used under the hood so that events, state transitions, or failures can be broadcast to subscribers.
If you wanted to subscribe to agent events (like :act_completed or :queue_overflow signals), you can do:

elixir
Copy code
defmodule MyAppWeb.AgentEventsLive do
  use Phoenix.LiveView
  alias Jido.Signal

  @topic "jido.agent.announcer_1"

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, @topic)
    end

    {:ok, socket}
  end

  def handle_info(%Signal{type: "jido.agent.cmd_completed"} = signal, socket) do
    # E.g. handle the completion event
    IO.puts("Action completed with data: #{inspect(signal.data)}")
    {:noreply, socket}
  end

  # ... handle other events or unknown signals
  def handle_info(_other, socket), do: {:noreply, socket}
end
That’s it! Your Jido Agent can now be driven by HTTP requests, WebSockets, or internal messages—making it easy to build robust, stateful workflows in your Phoenix app.

8. Next Steps
Add More Actions: Create new use Jido.Action modules for your domain (file manipulations, external APIs, arithmetic, etc.).
Organize Commands: Group them in modules using use Jido.Command—each command can orchestrate multiple actions.
Extend Agent: Overwrite lifecycle callbacks (on_before_plan/3, on_after_run/2, etc.) to handle advanced logic.
Distribute: Spin up multiple agents across nodes for parallel, fault-tolerant workflows.
Testing: Use ExUnit or property-based tests to ensure reliability. Jido is easy to test in isolation—just instantiate your Agent with new(), plan commands, and run them.
Jido opens up a flexible approach to building composable, functional workflows in Elixir. By leveraging Actions (reusable building blocks) and Commands (aggregated behavior), your Agent can handle anything from simple sequential tasks to complex asynchronous flows, with powerful PubSub-driven eventing for a real-time experience.

Happy hacking with Jido! If you have any questions or want to learn more about advanced features like compensation, parallel workflows, or advanced hooks, check out the rest of our documentation and examples.