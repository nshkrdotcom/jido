# defmodule JidoAi.Models.BaseProvider do
#   @moduledoc """
#   Provides base functionality for model providers.
#   """

#   alias JidoAi.Models.Types

#   defmacro __using__(opts) do
#     quote do
#       @behaviour JidoAi.Models.ProviderBehaviour

#       @config unquote(Macro.escape(opts[:config]))

#       @impl true
#       def get_model(model_class), do: @config.model[model_class]

#       @impl true
#       def get_endpoint, do: @config.endpoint

#       @impl true
#       def get_settings, do: @config.settings

#       @impl true
#       def get_image_settings, do: Map.get(@config, :image_settings)

#       defoverridable get_model: 1, get_endpoint: 0, get_settings: 0, get_image_settings: 0
#     end
#   end
# end
