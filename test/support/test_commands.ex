defmodule JidoTest.Commands do
  @moduledoc """
  Collection of test Command implementations for Jido.Agent testing.
  """

  defmodule Basic do
    @moduledoc "Basic command set for testing core functionality"
    use Jido.Command
    alias Jido.Actions.Basic.{Log, Sleep}

    @impl true
    def commands do
      [
        greet: [
          description: "Simple greeting command",
          schema: [
            name: [type: :string, default: "world"]
          ]
        ],
        wait: [
          description: "Waits for specified duration",
          schema: [
            duration: [
              type: :integer,
              required: true,
              doc: "Duration in milliseconds"
            ]
          ]
        ]
      ]
    end

    @impl true
    def handle_command(:greet, agent, params) when is_list(params) do
      handle_command(:greet, agent, Map.new(params))
    end

    @impl true
    def handle_command(:greet, _agent, %{name: name}) do
      {:ok,
       [
         {Log, message: "Hello, #{name}!"},
         {Sleep, duration: 50},
         {Log, message: "Goodbye, #{name}!"}
       ]}
    end

    def handle_command(:wait, agent, params) when is_list(params) do
      handle_command(:wait, agent, Map.new(params))
    end

    def handle_command(:wait, _agent, %{duration: duration}) do
      {:ok,
       [
         {Log, message: "Waiting for #{duration}ms..."},
         {Sleep, duration: duration},
         {Log, message: "Done waiting!"}
       ]}
    end
  end

  defmodule Movement do
    @moduledoc "Commands for agent movement and location management"
    use Jido.Command
    alias Jido.Actions.Basic.Log
    alias Jido.Actions.Simplebot.{Move, Recharge}

    @impl true
    def commands do
      [
        move: [
          description: "Moves agent to new location",
          schema: [
            destination: [
              type: :atom,
              required: true,
              doc: "Destination location"
            ]
          ]
        ],
        recharge: [
          description: "Recharges agent battery",
          schema: [
            target_level: [
              type: :integer,
              default: 100,
              doc: "Target battery level"
            ]
          ]
        ],
        patrol: [
          description: "Patrols between multiple locations",
          schema: [
            locations: [
              type: {:list, :atom},
              required: true,
              doc: "List of locations to patrol"
            ],
            rounds: [
              type: :integer,
              default: 1,
              doc: "Number of patrol rounds"
            ]
          ]
        ]
      ]
    end

    @impl true
    def handle_command(:move, agent, params) when is_list(params) do
      handle_command(:move, agent, Map.new(params))
    end

    def handle_command(:move, agent, %{destination: dest}) do
      {:ok,
       [
         {Log, message: "Moving from #{agent.location} to #{dest}..."},
         {Move, destination: dest},
         {Log, message: "Arrived at #{dest}!"}
       ]}
    end

    def handle_command(:recharge, agent, params) when is_list(params) do
      handle_command(:recharge, agent, Map.new(params))
    end

    def handle_command(:recharge, _agent, %{target_level: level}) do
      {:ok,
       [
         {Log, message: "Recharging to #{level}%..."},
         {Recharge, target_level: level},
         {Log, message: "Recharged to #{level}%!"}
       ]}
    end

    def handle_command(:patrol, _agent, %{locations: locs, rounds: rounds}) do
      moves =
        for _ <- 1..rounds, loc <- locs do
          [
            {Move, destination: loc},
            {Log, message: "Patrolling #{loc}"}
          ]
        end

      {:ok, List.flatten(moves)}
    end
  end

  defmodule Advanced do
    @moduledoc "Advanced commands with conditional behavior"
    use Jido.Command
    alias Jido.Actions.Basic.Log
    alias Jido.Actions.Simplebot.{Move, Recharge, DoWork, Report, Idle}

    @impl true
    def commands do
      [
        smart_work: [
          description: "Intelligent work sequence based on agent state",
          schema: [
            force_work: [
              type: :boolean,
              default: false,
              doc: "Force work even with low battery"
            ]
          ]
        ],
        status_report: [
          description: "Generates status report",
          schema: [
            include_location: [type: :boolean, default: true],
            include_battery: [type: :boolean, default: true]
          ]
        ]
      ]
    end

    @impl true
    def handle_command(:smart_work, agent, %{force_work: force}) do
      actions =
        cond do
          agent.battery_level <= 20 and not force ->
            [
              {Log, message: "Battery low, recharging first..."},
              {Move, destination: :charging_station},
              Recharge
            ]

          agent.location != :work_area ->
            [
              {Log, message: "Moving to work area..."},
              {Move, destination: :work_area},
              DoWork
            ]

          not agent.has_reported ->
            [DoWork, Report]

          true ->
            [Idle]
        end

      {:ok, actions}
    end

    def handle_command(:status_report, agent, params) do
      messages =
        []
        |> add_if(params.include_location, "Location: #{agent.location}")
        |> add_if(params.include_battery, "Battery: #{agent.battery_level}%")

      actions = Enum.map(messages, &{Log, message: &1})
      {:ok, actions}
    end

    defp add_if(list, true, item), do: [item | list]
    defp add_if(list, false, _item), do: list
  end
end
