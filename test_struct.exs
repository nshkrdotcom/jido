alias JidoTest.TestAgents.CallbackTrackingAgent

# Test if the agent can be created properly
agent = CallbackTrackingAgent.new("test", %{})
IO.puts("Agent creation successful!")
IO.puts("Agent ID: #{agent.id}")
IO.puts("Agent struct: #{inspect(agent.__struct__)}")

# Test the set function works
{:ok, updated_agent} = CallbackTrackingAgent.set(agent, %{callback_log: ["test_entry"]})
IO.puts("Agent update successful!")
IO.puts("Updated state: #{inspect(updated_agent.state)}")