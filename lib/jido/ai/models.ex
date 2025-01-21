# defmodule JidoAi.Models do
#   @moduledoc """
#   Defines core types and structures for model configurations.
#   """

#   @type model_class :: :small | :medium | :large | :embedding | :image

#   @type model_settings :: %{
#           stop: list(String.t()),
#           max_input_tokens: pos_integer(),
#           max_output_tokens: pos_integer(),
#           frequency_penalty: float(),
#           presence_penalty: float(),
#           temperature: float()
#         }

#   @type image_settings :: %{
#           steps: pos_integer()
#         }

#   @type model_config :: %{
#           endpoint: String.t() | nil,
#           settings: model_settings(),
#           image_settings: image_settings() | nil,
#           model: %{atom() => String.t()}
#         }
# end
