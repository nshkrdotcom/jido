#!/usr/bin/env elixir

# Script to reproduce the race condition in Jido.Agent.Server.terminate/2
# 
# The issue: During agent termination, the terminate callback tries to call
# Process.info/2 on related processes that may have already died, causing
# an ErlangError with reason :normal
#
# Run with: elixir reproduce_server_race_condition.exs

Mix.install([
  {:jido, "~> 1.2.0"}
])

defmodule TestAction do
  use Jido.Action,
    name: "test_action",
    description: "Simple test action",
    schema: []
    
  def run(_context, _params) do
    {:ok, %{result: "test"}}
  end
end

defmodule RaceConditionAgent do
  use Jido.Agent,
    name: "race_condition_agent",
    description: "Agent to demonstrate terminate race condition",
    actions: [TestAction],
    schema: [
      status: [type: :atom, default: :idle],
      linked_process: [type: :pid, default: nil]
    ]
end

defmodule RaceConditionReproducer do
  def run do
    IO.puts("\n=== Jido Agent Server Race Condition Reproducer ===\n")
    
    # Test 1: Basic termination - should work fine
    IO.puts("Test 1: Normal agent termination")
    test_normal_termination()
    
    # Test 2: Termination with linked process - demonstrates the race condition
    IO.puts("\nTest 2: Agent termination with linked process (race condition)")
    test_linked_process_termination()
    
    # Test 3: Multiple agents terminating simultaneously
    IO.puts("\nTest 3: Multiple agents terminating simultaneously")
    test_simultaneous_termination()
    
    # Test 4: Rapid creation and termination
    IO.puts("\nTest 4: Rapid agent creation and termination")
    test_rapid_lifecycle()
    
    IO.puts("\n=== Tests Complete ===\n")
  end
  
  defp test_normal_termination do
    try do
      {:ok, agent_pid} = RaceConditionAgent.start_link(id: "normal_test")
      Process.sleep(10)
      
      IO.puts("  - Agent started: #{inspect(agent_pid)}")
      
      # Normal stop should work fine
      :ok = GenServer.stop(agent_pid, :normal, 5000)
      IO.puts("  ✓ Agent stopped normally without errors")
    rescue
      e ->
        IO.puts("  ✗ ERROR during normal termination: #{inspect(e)}")
        IO.puts("    #{Exception.format_stacktrace(__STACKTRACE__)}")
    end
  end
  
  defp test_linked_process_termination do
    try do
      # Create a helper process that the agent might reference
      helper_pid = spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)
      
      {:ok, agent_pid} = RaceConditionAgent.start_link(id: "linked_test")
      
      # Simulate the agent having a reference to another process
      # (In real Jido agents, this might be monitors, tasks, etc.)
      :sys.replace_state(agent_pid, fn state ->
        put_in(state.agent.state.linked_process, helper_pid)
      end)
      
      IO.puts("  - Agent started: #{inspect(agent_pid)}")
      IO.puts("  - Helper process: #{inspect(helper_pid)}")
      
      # Kill the helper process first
      Process.exit(helper_pid, :kill)
      Process.sleep(5)
      
      IO.puts("  - Helper process killed")
      
      # Now stop the agent - this should trigger the race condition
      # if the terminate callback tries to access info about the helper
      :ok = GenServer.stop(agent_pid, :normal, 5000)
      IO.puts("  ✓ Agent stopped (but check for errors in terminate callback)")
    rescue
      e ->
        IO.puts("  ✗ ERROR during linked termination: #{inspect(e)}")
        IO.puts("    #{Exception.format_stacktrace(__STACKTRACE__)}")
    catch
      :exit, reason ->
        IO.puts("  ✗ EXIT during linked termination: #{inspect(reason)}")
    end
  end
  
  defp test_simultaneous_termination do
    try do
      # Start multiple agents
      agents = for i <- 1..5 do
        {:ok, pid} = RaceConditionAgent.start_link(id: "simultaneous_#{i}")
        pid
      end
      
      IO.puts("  - Started #{length(agents)} agents")
      
      # Create some cross-references between agents
      # This simulates agents that might monitor or reference each other
      for {agent, idx} <- Enum.with_index(agents) do
        next_agent = Enum.at(agents, rem(idx + 1, length(agents)))
        :sys.replace_state(agent, fn state ->
          put_in(state.agent.state.linked_process, next_agent)
        end)
      end
      
      IO.puts("  - Created circular references between agents")
      
      # Now terminate them all at once
      tasks = for agent <- agents do
        Task.async(fn ->
          try do
            GenServer.stop(agent, :normal, 1000)
          catch
            :exit, _ -> :ok
          end
        end)
      end
      
      # Wait for all terminations
      Task.await_many(tasks, 2000)
      
      IO.puts("  ✓ All agents terminated (check for race condition errors)")
    rescue
      e ->
        IO.puts("  ✗ ERROR during simultaneous termination: #{inspect(e)}")
    end
  end
  
  defp test_rapid_lifecycle do
    try do
      # Rapidly create and destroy agents
      for i <- 1..10 do
        spawn(fn ->
          {:ok, pid} = RaceConditionAgent.start_link(id: "rapid_#{i}")
          Process.sleep(:rand.uniform(10))
          GenServer.stop(pid, :normal)
        end)
      end
      
      # Wait for all to complete
      Process.sleep(100)
      
      IO.puts("  ✓ Rapid lifecycle test completed")
    rescue
      e ->
        IO.puts("  ✗ ERROR during rapid lifecycle: #{inspect(e)}")
    end
  end
end

defmodule TerminateCallbackInspector do
  @moduledoc """
  This module attempts to hook into the Jido.Agent.Server to inspect
  what happens during termination.
  """
  
  def inspect_terminate_behavior do
    IO.puts("\n=== Inspecting Jido.Agent.Server terminate callback ===\n")
    
    # Start a simple agent
    {:ok, agent_pid} = RaceConditionAgent.start_link(id: "inspector_test")
    
    # Trace the terminate callback
    :dbg.tracer()
    :dbg.p(agent_pid, [:call])
    :dbg.tpl(Jido.Agent.Server, :terminate, :return)
    
    IO.puts("Tracing enabled on agent #{inspect(agent_pid)}")
    IO.puts("Stopping agent to trigger terminate callback...\n")
    
    # Stop the agent to see the terminate callback
    GenServer.stop(agent_pid, :normal)
    
    # Give trace some time to output
    Process.sleep(100)
    
    :dbg.stop()
    IO.puts("\nTracing complete")
  end
end

# Run the reproduction tests
RaceConditionReproducer.run()

# Optionally inspect the terminate callback behavior
IO.puts("\nPress Enter to inspect terminate callback behavior...")
IO.gets("")
TerminateCallbackInspector.inspect_terminate_behavior()

IO.puts("\n=== Analysis ===")
IO.puts("""
If you see errors like:
  ** (ErlangError) Erlang error: :normal
  at lib/process.ex:896: Process.info/2
  at lib/jido/agent/server.ex:344: Jido.Agent.Server.terminate/2

This confirms the race condition where the terminate callback tries to 
access process info for already-dead processes.

The issue is particularly likely when:
1. Agents have references to other processes
2. Multiple agents terminate simultaneously  
3. Rapid agent creation/destruction occurs
4. The referenced processes die before the agent's terminate callback runs

This is a bug in the Jido library that should handle the case where
Process.info/2 returns nil for dead processes.
""")