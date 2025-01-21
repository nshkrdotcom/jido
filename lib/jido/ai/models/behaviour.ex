# defmodule Jido.AI.Models.ProviderBehaviour do
#   @moduledoc """
#   Defines the behavior that all model providers must implement.
#   """

#   alias Jido.AI.Models.Types

#   @callback get_model(model_class :: Types.model_class()) :: String.t()
#   @callback get_endpoint() :: String.t() | nil
#   @callback get_settings() :: Types.model_settings()
#   @callback get_image_settings() :: Types.image_settings() | nil
# end
