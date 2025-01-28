# defmodule Jido.AI.Models.Providers.OpenAI do
#   @moduledoc """
#   OpenAI model provider implementation.
#   """

#   use Jido.AI.Models.BaseProvider,
#     config: %{
#       endpoint: "https://api.openai.com/v1",
#       settings: %{
#         stop: [],
#         max_input_tokens: 128_000,
#         max_output_tokens: 8_192,
#         frequency_penalty: 0.0,
#         presence_penalty: 0.0,
#         temperature: 0.6
#       },
#       model: %{
#         small: System.get_env("SMALL_OPENAI_MODEL", "gpt-4o-mini"),
#         medium: System.get_env("MEDIUM_OPENAI_MODEL", "gpt-4o"),
#         large: System.get_env("LARGE_OPENAI_MODEL", "gpt-4o"),
#         embedding: System.get_env("EMBEDDING_OPENAI_MODEL", "text-embedding-3-small"),
#         image: System.get_env("IMAGE_OPENAI_MODEL", "dall-e-3")
#       }
#     }
# end
