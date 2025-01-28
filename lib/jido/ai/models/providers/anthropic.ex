# defmodule Jido.AI.Models.Providers.Anthropic do
#   @moduledoc """
#   Anthropic Claude model provider implementation.
#   """

#   use Jido.AI.Models.BaseProvider,
#     config: %{
#       settings: %{
#         stop: [],
#         max_input_tokens: 200_000,
#         max_output_tokens: 4_096,
#         frequency_penalty: 0.4,
#         presence_penalty: 0.4,
#         temperature: 0.7
#       },
#       endpoint: "https://api.anthropic.com/v1",
#       model: %{
#         small: System.get_env("SMALL_ANTHROPIC_MODEL", "claude-3-haiku-20240307"),
#         medium: System.get_env("MEDIUM_ANTHROPIC_MODEL", "claude-3-5-sonnet-20241022"),
#         large: System.get_env("LARGE_ANTHROPIC_MODEL", "claude-3-5-sonnet-20241022")
#       }
#     }
# end
