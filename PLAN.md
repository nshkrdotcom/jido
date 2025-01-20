- Implement Jido.Agent.Server
  - Start the GenServer with ServerState
	  - No pubsub
	  - No topic
		- No Subscription list
	- Optionally start a Bus Sensor

  - Single `cmd` function that accepts Signals
  - Enqueue and Execute Signals
	- Refresh the Instruction, Action, Result relationship - SIMPLIFY
	- Clean up Directives


	- Add Skills