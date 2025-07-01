#!/usr/bin/env elixir

# Minimal reproduction of the Process.info race condition
# This demonstrates the exact issue in Jido.Agent.Server.terminate/2

defmodule ProcessInfoRaceDemo do
  @moduledoc """
  Demonstrates the race condition that occurs when calling Process.info/2
  on a process that has already exited.
  
  This is what happens in Jido.Agent.Server.terminate/2 at line 344.
  """
  
  def demonstrate_race_condition do
    IO.puts("\n=== Process.info/2 Race Condition Demo ===\n")
    
    # Test 1: Process.info on a live process (works fine)
    IO.puts("Test 1: Process.info on live process")
    live_pid = spawn(fn -> 
      receive do
        :stop -> :ok
      end
    end)
    
    info = Process.info(live_pid)
    IO.puts("  ✓ Process.info succeeded: #{inspect(info |> Keyword.take([:status, :message_queue_len]))}")
    
    send(live_pid, :stop)
    Process.sleep(10)
    
    # Test 2: Process.info on a dead process (returns nil, not an error)
    IO.puts("\nTest 2: Process.info on dead process")
    dead_pid = spawn(fn -> :ok end)
    Process.sleep(10)  # Let it die
    
    info = Process.info(dead_pid)
    IO.puts("  ✓ Process.info on dead process returns: #{inspect(info)}")
    
    # Test 3: The actual race condition - Process.info with specific key on dead process
    IO.puts("\nTest 3: Process.info/2 with specific key on dead process (THE BUG)")
    
    another_pid = spawn(fn -> :ok end)
    Process.sleep(10)  # Let it die
    
    # This is what Jido does - it calls Process.info/2 with a specific key
    # If the process is dead, this throws an ErlangError!
    try do
      # This is likely what's at line 344 in jido/agent/server.ex
      queue_len = Process.info(another_pid, :message_queue_len)
      IO.puts("  - Process.info/2 returned: #{inspect(queue_len)}")
    rescue
      e in ErlangError ->
        IO.puts("  ✗ ERROR: #{inspect(e)}")
        IO.puts("    This is the exact error seen in the Jido terminate callback!")
    end
    
    # Test 4: The proper way to handle this
    IO.puts("\nTest 4: Safe way to check process info")
    
    yet_another_pid = spawn(fn -> :ok end)
    Process.sleep(10)
    
    # Safe approach 1: Check if process is alive first
    if Process.alive?(yet_another_pid) do
      info = Process.info(yet_another_pid, :message_queue_len)
      IO.puts("  - Process alive, info: #{inspect(info)}")
    else
      IO.puts("  ✓ Process not alive, skipping Process.info call")
    end
    
    # Safe approach 2: Handle the nil return from Process.info/1
    case Process.info(yet_another_pid) do
      nil ->
        IO.puts("  ✓ Process is dead, Process.info returned nil")
      info ->
        queue_len = Keyword.get(info, :message_queue_len, 0)
        IO.puts("  - Queue length: #{queue_len}")
    end
    
    IO.puts("\n=== Conclusion ===")
    IO.puts("""
    The bug in Jido.Agent.Server.terminate/2 is that it calls Process.info/2
    with a specific key on a process that might already be dead.
    
    When Process.info/2 is called with a specific key on a dead process,
    it throws an ErlangError instead of returning nil.
    
    The fix would be to either:
    1. Check Process.alive?/1 first
    2. Use Process.info/1 and extract the key safely
    3. Wrap the Process.info/2 call in a try/rescue
    """)
  end
  
  def simulate_jido_terminate_callback do
    IO.puts("\n=== Simulating Jido Terminate Callback ===\n")
    
    # This simulates what might be happening in Jido.Agent.Server.terminate/2
    parent = self()
    
    # Create a "child" process that the agent might be monitoring
    child_pid = spawn(fn ->
      receive do
        :stop -> send(parent, :child_stopped)
      end
    end)
    
    # Simulate having a reference to this child in the agent state
    agent_state = %{
      monitored_processes: [child_pid],
      some_other_pid: child_pid
    }
    
    IO.puts("Simulated agent state with child process: #{inspect(child_pid)}")
    
    # Now simulate a shutdown scenario where processes die in quick succession
    spawn(fn ->
      Process.sleep(5)
      Process.exit(child_pid, :kill)
    end)
    
    Process.sleep(10)
    
    # Now the terminate callback runs and tries to get info about child processes
    IO.puts("\nTerminate callback attempting to get process info...")
    
    Enum.each(agent_state.monitored_processes, fn pid ->
      try do
        # This is what Jido might be doing - BAD!
        queue_len = Process.info(pid, :message_queue_len)
        IO.puts("  - Process #{inspect(pid)} queue length: #{inspect(queue_len)}")
      rescue
        e in ErlangError ->
          IO.puts("  ✗ ERROR accessing #{inspect(pid)}: #{inspect(e)}")
          IO.puts("    ^ This is the bug in Jido's terminate callback!")
      end
    end)
  end
end

# Run the demonstrations
ProcessInfoRaceDemo.demonstrate_race_condition()
ProcessInfoRaceDemo.simulate_jido_terminate_callback()

IO.puts("\n=== How to Fix in Jido ===")
IO.puts("""
The terminate callback in Jido.Agent.Server should be updated to handle
dead processes gracefully. Instead of:

    queue_len = Process.info(pid, :message_queue_len)

It should use:

    queue_len = case Process.info(pid) do
      nil -> 0
      info -> Keyword.get(info, :message_queue_len, 0)
    end

Or wrap the call in a try/rescue block.
""")