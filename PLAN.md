<Plan>
1. **Goal**  
   We want to modify the Sensor behavior so it can emit its signals onto a configurable bus (e.g., Jido.Bus) rather than directly calling Phoenix PubSub.  

2. **Key Architectural Shifts**  
   - Eliminate direct `Phoenix.PubSub.broadcast/3` usage in Sensors.  
   - Introduce a required `bus_name` + `stream_id` in sensor configuration.  
   - The sensor uses the bus to publish signals (via `Jido.Bus.publish(bus_name, stream_id, expected_version, signals)`), rather than broadcasting them to PubSub.  
   - Remove the sensor’s `pubsub` dependency depending on backward compatibility.  

3. **Step-by-Step Implementation Plan**  

   ### A. Interface & Configuration Changes
   1. **Add or Update Sensor Schema**  
      - In your `schema` definition for each sensor, add or replace fields like:
        - `bus_name: [type: :atom, required: true]`
        - `stream_id: [type: :string, required: true]`
        - (Optional) a switch to override the old `pubsub` approach if backward compatibility is needed.  
      - For example, your sensor might allow both `pubsub` or `bus_name` usage, or require `bus_name` only.

   2. **Remove or Deprecate `pubsub`**  
      - If the system no longer needs direct PubSub, remove references to `pubsub`, `topic`, etc.  
      - If you need transitional backwards compatibility, keep the `pubsub` references but mark them as deprecated.  

   ### B. Sensor Logic for Emitting Signals
   1. **Adjust `generate_signal/1` or the point at which you create signals**  
      - (Likely unchanged except that it no longer sets up a PubSub broadcast. The output remains a `Jido.Signal` struct as before.)

   2. **Replace `publish_signal/2`**  
      - Where you currently do:
        ```elixir
        Phoenix.PubSub.broadcast(state.pubsub, state.topic, {:sensor_signal, signal})
        ```
        create a function that uses the bus, e.g.:
        ```elixir
        # Pseudocode
        Jido.Bus.publish(state.bus_name, state.stream_id, :any_version, [signal], [])
        ```
      - The sensor will only track a single logical `stream_id` (or multiple if your design so requires).  
      - Decide whether to set `expected_version` to `:any_version`, `:no_stream`, or some integer.  
      - Keep or remove the returned status (`:ok` | `{:error, reason}`) and handle it as needed.

   3. **Eliminate or Modify the `{:sensor_signal, signal}` Flow**  
      - If your code was previously capturing the broadcast messages in the same or another process, remove that code or adapt it to handle bus-based receipt.  
      - Optionally, you can still store the “last values” logic locally in the sensor, but it would come from a separate callback (like a subscription) if you want the sensor to also receive signals from the bus.  

   ### C. Testing Under TDD
   1. **Update Tests for New Bus Emission**  
      - Where your sensor tests previously asserted that the sensor broadcast to a topic, update them to:
        - Start an in-memory bus, or a test bus with `adapter: :in_memory`  
        - Possibly subscribe to the stream (or use `Bus.replay/2`)  
        - Trigger the sensor logic that calls `generate_signal/1`  
        - Confirm the signals now appear in the bus’s replay or ephemeral subscription.  
      - Example approach:  
        - Start the sensor with `[bus_name: test_bus, stream_id: "sensor_stream", ...]`  
        - Start bus: `Jido.Bus.start_link(name: test_bus, adapter: :in_memory)`  
        - Wait for or trigger a sensor emission event.  
        - Use `Jido.Bus.replay(test_bus, "sensor_stream")` to gather signals.  
        - Assert that the newly emitted signal is present.  

   2. **Retain or Remove Legacy PubSub Tests**  
      - If removing PubSub entirely, remove related tests.  
      - If supporting both, add separate test contexts verifying each path.  

   3. **Test Edge Cases**  
      - Repeated emissions (does the sensor handle version conflicts?).  
      - Missing bus configurations.  
      - Handling `{:error, :wrong_expected_version}` if you use an exact version or `:no_stream`.  

   ### D. Recommended Refactors & Simplifications
   1. **Sensor GenServer**  
      - If you no longer store “last values” by intercepting your own PubSub messages, consider a simpler approach to local state updates.  
      - Consider removing the “heartbeat” concept if it’s not needed, or keep it for periodic signals.

   2. **Refactor**  
      - If many sensors share the same pattern, unify them by hooking into a small “emit to bus” helper function to reduce duplication.  
      - If the system’s logic for concurrency or partitioning is needed, rely on Jido.Bus’s concurrency.  
      - Possibly rename or unify your “BusSensor” with the general `Sensor` so they do not conflict.  

   3. **Ensure Clear Separation**  
      - The sensor’s domain logic (`generate_signal`) should remain decoupled from the bus logic.  
      - The bus logic is only in the last “publish step” so that you can easily replace it with other adapters later.  

4. **Potential Side Effects & Additional Considerations**  
   - By switching from PubSub to the bus, you might lose immediate broadcast-based behavior. If you still need to “listen” for sensor emissions from other processes, you can rely on `subscribe/2` with the bus.  
   - If your system previously expected ephemeral real-time updates via PubSub, you might need bridging logic that automatically subscribes to the bus and re-broadcasts on a PubSub channel. This can be done with a small worker process.  
   - The sensor no longer receives `{:sensor_signal, signal}` messages by default. If you have “self-consuming” patterns (like storing last values in the sensor state), you can achieve that by also calling `subscribe/2` from the sensor to the same bus stream. Then in `handle_info({:signals, signals}, state)` you can store them.  

5. **Summary**  
   - Convert sensor’s main emission from direct PubSub broadcast to “publish to Jido.Bus.”  
   - Update sensor config to require `bus_name` + `stream_id`.  
   - Adapt or remove references to `pubsub` in tests and code.  
   - Use TDD with an in-memory bus for verifying signals.  
   - Refactor or simplify any leftover “PubSub-based” state management to the bus paradigm.  
</Plan>