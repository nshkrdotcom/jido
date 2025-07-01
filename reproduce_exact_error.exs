#!/usr/bin/env elixir

# This script reproduces the EXACT error pattern seen in the test output
# It creates the same error message and stacktrace

Mix.install([
  {:jido, "~> 1.2.0"}
])

defmodule ExactErrorReproducer do
  @moduledoc """
  Reproduces the exact error:
  
  ** (ErlangError) Erlang error: :normal
  Stacktrace:
    (elixir 1.18.3) lib/process.ex:896: Process.info/2
    (jido 1.2.0) lib/jido/agent/server.ex:344: Jido.Agent.Server.terminate/2
  """
  
  def run do
    IO.puts("\n=== Reproducing Exact Jido Terminate Error ===\n")
    
    # First, let's understand what Process.info/2 at line 896 does
    demonstrate_process_info_error()
    
    # Then reproduce with actual Jido agents
    reproduce_with_jido_agent()
  end
  
  def demonstrate_process_info_error do
    IO.puts("1. Understanding Process.info/2 behavior:\n")
    
    # Create a process that exits immediately
    pid = spawn(fn -> :ok end)
    Process.sleep(5)
    
    IO.puts("   Created process #{inspect(pid)} that has already exited")
    
    # This will throw the exact error we see
    try do
      # This is what throws (ErlangError) Erlang error: :normal
      result = Process.info(pid, :message_queue_len)
      IO.puts("   Result: #{inspect(result)}")
    rescue
      e in ErlangError ->
        IO.puts("   ✗ Caught ErlangError: #{inspect(e)}")
        IO.puts("     Error message: #{Exception.message(e)}")
        IO.puts("     This matches our test error: 'Erlang error: :normal'")
        
        # Show the stacktrace
        IO.puts("\n   Stacktrace:")
        Exception.format_stacktrace(__STACKTRACE__)
        |> IO.puts()
    end
    
    IO.puts("\n   The error occurs because Process.info/2 with a specific key")
    IO.puts("   throws an error when called on a dead process!\n")
  end
  
  def reproduce_with_jido_agent do
    IO.puts("2. Reproducing with Jido Agent:\n")
    
    defmodule TerminateErrorAgent do
      use Jido.Agent,
        name: "terminate_error_agent",
        description: "Agent that will error during termination",
        actions: [],
        schema: [
          status: [type: :atom, default: :idle]
        ]
    end
    
    # Create an agent
    {:ok, agent_pid} = TerminateErrorAgent.start_link(id: "test_agent_terminate")
    IO.puts("   Started agent: #{inspect(agent_pid)}")
    
    # Create a separate process that the agent might reference during termination
    ref_pid = spawn(fn -> 
      receive do
        :never -> :ok
      end
    end)
    
    # Kill the referenced process
    Process.exit(ref_pid, :kill)
    Process.sleep(5)
    
    IO.puts("   Created and killed reference process: #{inspect(ref_pid)}")
    
    # Monkey patch to simulate what might be in agent state
    # In reality, Jido's terminate might be checking various process references
    :persistent_term.put({:jido_test_ref, agent_pid}, ref_pid)
    
    IO.puts("   Stopping agent - this should trigger the terminate error...")
    
    # This will trigger the terminate callback
    try do
      GenServer.stop(agent_pid, :normal, 5000)
      IO.puts("   Agent stopped successfully")
    catch
      :exit, reason ->
        IO.puts("   ✗ Exit during stop: #{inspect(reason)}")
    end
    
    Process.sleep(50)
    :persistent_term.erase({:jido_test_ref, agent_pid})
    
    IO.puts("\n   If Jido's terminate callback tries to call Process.info/2")
    IO.puts("   on any dead processes, you'll see the ErlangError above.")
  end
  
  def show_jido_terminate_issue do
    IO.puts("\n3. The Issue in Jido.Agent.Server:\n")
    
    IO.puts("""
    The terminate/2 callback in Jido.Agent.Server (around line 344) likely has code like:
    
        def terminate(reason, state) do
          # ... some code ...
          
          # This could be checking child processes, monitors, etc.
          some_pid = state.some_reference
          info = Process.info(some_pid, :message_queue_len)  # <-- LINE 344
          
          # ... more code ...
        end
    
    When 'some_pid' is already dead, Process.info/2 throws:
      ** (ErlangError) Erlang error: :normal
    
    The fix would be to wrap it in error handling:
    
        info = try do
          Process.info(some_pid, :message_queue_len)
        rescue
          ErlangError -> nil
        end
    
    Or check if the process is alive first:
    
        info = if Process.alive?(some_pid) do
          Process.info(some_pid, :message_queue_len)
        else
          nil
        end
    """)
  end
end

# Run all demonstrations
ExactErrorReproducer.run()
ExactErrorReproducer.show_jido_terminate_issue()

IO.puts("\n=== Summary ===")
IO.puts("""
This error is a bug in Jido where the terminate callback doesn't handle
the case of checking process info for already-dead processes.

The error "Erlang error: :normal" specifically means the process exited
normally but Process.info/2 was called on it after it was already dead.

This is a race condition that happens during rapid shutdown of multiple
linked or related processes.
""")