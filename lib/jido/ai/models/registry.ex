defmodule Jido.AI.Models.Registry do
  @moduledoc """
  Central registry for model providers and associated configurations.

  This module stores a map of provider configurations, which are used throughout
  the Jido AI ecosystem to interact with various Large Language Model (LLM) or
  generative providers. Each provider typically has:

    * A unique name (e.g. `:openai`, `:anthropic`).
    * A configuration map with endpoint and model settings.
    * Possible structures for embeddings, images, or other specialized tasks.

  ## Key Functions

    * `list_providers/0` - Lists all supported providers.
    * `get_provider/1` - Retrieves the full provider configuration by name.
    * `get_model_settings/2` - Fetches the model settings by provider and size.
    * `get_embedding_settings/1` - Returns embedding configuration if available.
    * `get_image_settings/1` - Returns image generation configuration if available.

  ## Examples

      iex> providers = Jido.AI.Models.Registry.list_providers()
      iex> :openai in providers
      true

      iex> config = Jido.AI.Models.Registry.get_provider(:openai)
      iex> is_map(config)
      true

      iex> model_settings = Jido.AI.Models.Registry.get_model_settings(:anthropic, :small)
      iex> model_settings.name
      "claude-3-haiku-20240307"

  """

  @type provider :: atom()
  @type size :: :small | :medium | :large
  @type model_settings :: %{
          name: String.t(),
          stop: list(String.t()),
          max_input_tokens: pos_integer(),
          max_output_tokens: pos_integer(),
          frequency_penalty: float(),
          presence_penalty: float(),
          temperature: float()
        }
  @type embedding_settings :: %{
          name: String.t(),
          dimensions: pos_integer() | nil
        }
  @type image_settings :: %{
          name: String.t(),
          steps: pos_integer() | nil
        }
  @type provider_config :: %{
          endpoint: String.t() | nil,
          model: %{
            optional(:small) => model_settings(),
            optional(:medium) => model_settings(),
            optional(:large) => model_settings(),
            optional(:embedding) => embedding_settings(),
            optional(:image) => image_settings()
          }
        }

  # Helper to get environment variables with defaults
  defp get_env(key, default) do
    System.get_env(key) || default
  end

  # Helper to create common model settings
  defp base_model_settings(name, opts \\ []) do
    env_name = opts[:env_name]
    actual_name = if env_name, do: get_env(env_name, name), else: name

    %{
      name: actual_name,
      stop: Keyword.get(opts, :stop, []),
      max_input_tokens: Keyword.get(opts, :max_input_tokens, 128_000),
      max_output_tokens: Keyword.get(opts, :max_output_tokens, 8_192),
      frequency_penalty: Keyword.get(opts, :frequency_penalty, 0.4),
      presence_penalty: Keyword.get(opts, :presence_penalty, 0.4),
      temperature: Keyword.get(opts, :temperature, 0.7)
    }
  end

  @doc """
  Returns a map of all known provider configurations at runtime.
  This function is used internally by other registry functions.

  ## Examples

      iex> map = Jido.AI.Models.Registry.providers()
      iex> is_map(map)
      true
      iex> :openai in Map.keys(map)
      true
  """
  def providers do
    %{
      openai: %{
        endpoint: get_env("OPENAI_API_URL", "https://api.openai.com/v1"),
        model: %{
          small:
            base_model_settings("gpt-4o-mini",
              env_name: "SMALL_OPENAI_MODEL",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          medium:
            base_model_settings("gpt-4o",
              env_name: "MEDIUM_OPENAI_MODEL",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          large:
            base_model_settings("gpt-4o",
              env_name: "LARGE_OPENAI_MODEL",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          embedding: %{
            name: get_env("EMBEDDING_OPENAI_MODEL", "text-embedding-3-small"),
            dimensions: 1536
          },
          image: %{name: get_env("IMAGE_OPENAI_MODEL", "dall-e-3")}
        }
      },
      anthropic: %{
        endpoint: get_env("ANTHROPIC_API_URL", "https://api.anthropic.com/v1"),
        model: %{
          small:
            base_model_settings("claude-3-haiku-20240307",
              env_name: "SMALL_ANTHROPIC_MODEL",
              max_input_tokens: 200_000,
              max_output_tokens: 4_096
            ),
          medium:
            base_model_settings("claude-3-5-sonnet-20241022",
              env_name: "MEDIUM_ANTHROPIC_MODEL",
              max_input_tokens: 200_000,
              max_output_tokens: 4_096
            ),
          large:
            base_model_settings("claude-3-5-sonnet-20241022",
              env_name: "LARGE_ANTHROPIC_MODEL",
              max_input_tokens: 200_000,
              max_output_tokens: 4_096
            )
        }
      },
      google: %{
        endpoint: "https://generativelanguage.googleapis.com",
        model: %{
          small: base_model_settings("gemini-2.0-flash-exp"),
          medium: base_model_settings("gemini-2.0-flash-exp"),
          large: base_model_settings("gemini-2.0-flash-exp"),
          embedding: %{name: "text-embedding-004"}
        }
      },
      mistral: %{
        model: %{
          small: base_model_settings("mistral-small-latest"),
          medium: base_model_settings("mistral-large-latest"),
          large: base_model_settings("mistral-large-latest")
        }
      },
      groq: %{
        endpoint: "https://api.groq.com/openai/v1",
        model: %{
          small: base_model_settings("llama-3.1-8b-instant"),
          medium: base_model_settings("llama-3.3-70b-versatile"),
          large: base_model_settings("llama-3.2-90b-vision-preview"),
          embedding: %{name: "llama-3.1-8b-instant"}
        }
      },
      grok: %{
        endpoint: "https://api.x.ai/v1",
        model: %{
          small: base_model_settings("grok-2-1212"),
          medium: base_model_settings("grok-2-1212"),
          large: base_model_settings("grok-2-1212"),
          embedding: %{name: "grok-2-1212"}
        }
      },
      together: %{
        endpoint: "https://api.together.ai/v1",
        model: %{
          small:
            base_model_settings("meta-llama/Llama-3.2-3B-Instruct-Turbo", repetition_penalty: 0.4),
          medium:
            base_model_settings("meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo-128K",
              repetition_penalty: 0.4
            ),
          large:
            base_model_settings("meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo",
              repetition_penalty: 0.4
            ),
          embedding: %{name: "togethercomputer/m2-bert-80M-32k-retrieval"},
          image: %{name: "black-forest-labs/FLUX.1-schnell", steps: 4}
        }
      },
      llamacloud: %{
        endpoint: "https://api.llamacloud.com/v1",
        model: %{
          small:
            base_model_settings("meta-llama/Llama-3.2-3B-Instruct-Turbo", repetition_penalty: 0.4),
          medium: base_model_settings("meta-llama-3.1-8b-instruct", repetition_penalty: 0.4),
          large:
            base_model_settings("meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo",
              repetition_penalty: 0.4
            ),
          embedding: %{name: "togethercomputer/m2-bert-80M-32k-retrieval"},
          image: %{name: "black-forest-labs/FLUX.1-schnell", steps: 4}
        }
      },
      ollama: %{
        endpoint: get_env("OLLAMA_SERVER_URL", "http://localhost:11434"),
        model: %{
          small: base_model_settings("llama3.2", env_name: "SMALL_OLLAMA_MODEL"),
          medium: base_model_settings("hermes3", env_name: "MEDIUM_OLLAMA_MODEL"),
          large: base_model_settings("hermes3:70b", env_name: "LARGE_OLLAMA_MODEL"),
          embedding: %{
            name: get_env("OLLAMA_EMBEDDING_MODEL", "mxbai-embed-large"),
            dimensions: 1024
          }
        }
      },
      deepseek: %{
        endpoint: "https://api.deepseek.com",
        model: %{
          small:
            base_model_settings("deepseek-chat", frequency_penalty: 0.0, presence_penalty: 0.0),
          medium:
            base_model_settings("deepseek-chat", frequency_penalty: 0.0, presence_penalty: 0.0),
          large:
            base_model_settings("deepseek-chat", frequency_penalty: 0.0, presence_penalty: 0.0)
        }
      },
      eternalai: %{
        model: %{
          small: base_model_settings("neuralmagic/Meta-Llama-3.1-405B-Instruct-quantized.w4a16"),
          medium: base_model_settings("neuralmagic/Meta-Llama-3.1-405B-Instruct-quantized.w4a16"),
          large: base_model_settings("neuralmagic/Meta-Llama-3.1-405B-Instruct-quantized.w4a16")
        }
      },
      claude_vertex: %{
        endpoint: "https://api.anthropic.com/v1",
        model: %{
          small: base_model_settings("claude-3-5-sonnet-20241022", max_input_tokens: 200_000),
          medium: base_model_settings("claude-3-5-sonnet-20241022", max_input_tokens: 200_000),
          large: base_model_settings("claude-3-opus-20240229", max_input_tokens: 200_000)
        }
      },
      redpill: %{
        endpoint: "https://api.red-pill.ai/v1",
        model: %{
          small:
            base_model_settings("gpt-4o-mini",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          medium:
            base_model_settings("gpt-4o",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          large:
            base_model_settings("gpt-4o",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          embedding: %{name: "text-embedding-3-small"}
        }
      },
      openrouter: %{
        endpoint: "https://openrouter.ai/api/v1",
        model: %{
          small: base_model_settings("nousresearch/hermes-3-llama-3.1-405b"),
          medium: base_model_settings("nousresearch/hermes-3-llama-3.1-405b"),
          large: base_model_settings("nousresearch/hermes-3-llama-3.1-405b"),
          embedding: %{name: "text-embedding-3-small"}
        }
      },
      galadriel: %{
        endpoint: "https://api.galadriel.com/v1/verified",
        model: %{
          small:
            base_model_settings("gpt-4o-mini",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          medium:
            base_model_settings("gpt-4o",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          large:
            base_model_settings("gpt-4o",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            )
        }
      },
      fal: %{
        endpoint: "https://api.fal.ai/v1",
        model: %{
          image: %{name: "fal-ai/flux-lora", steps: 28}
        }
      },
      gaianet: %{
        model: %{
          small: base_model_settings("llama3b", repetition_penalty: 0.4),
          medium: base_model_settings("llama", repetition_penalty: 0.4),
          large: base_model_settings("qwen72b", repetition_penalty: 0.4),
          embedding: %{name: "nomic-embed", dimensions: 768}
        }
      },
      ali_bailian: %{
        endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        model: %{
          small: base_model_settings("qwen-turbo", temperature: 0.6),
          medium: base_model_settings("qwen-plus", temperature: 0.6),
          large: base_model_settings("qwen-max", temperature: 0.6),
          image: %{name: "wanx-v1"}
        }
      },
      volengine: %{
        endpoint: "https://open.volcengineapi.com/api/v3/",
        model: %{
          small: base_model_settings("doubao-lite-128k", temperature: 0.6),
          medium: base_model_settings("doubao-pro-128k", temperature: 0.6),
          large: base_model_settings("doubao-pro-256k", temperature: 0.6),
          embedding: %{name: "doubao-embedding"}
        }
      },
      nanogpt: %{
        endpoint: "https://nano-gpt.com/api/v1",
        model: %{
          small:
            base_model_settings("gpt-4o-mini",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          medium:
            base_model_settings("gpt-4o",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            ),
          large:
            base_model_settings("gpt-4o",
              temperature: 0.6,
              frequency_penalty: 0.0,
              presence_penalty: 0.0
            )
        }
      },
      hyperbolic: %{
        endpoint: "https://api.hyperbolic.xyz/v1",
        model: %{
          small: base_model_settings("meta-llama/Llama-3.2-3B-Instruct", temperature: 0.6),
          medium: base_model_settings("meta-llama/Meta-Llama-3.1-70B-Instruct", temperature: 0.6),
          large: base_model_settings("meta-llama/Meta-Llama-3.1-405-Instruct", temperature: 0.6),
          image: %{name: "FLUX.1-dev"}
        }
      },
      venice: %{
        endpoint: "https://api.venice.ai/api/v1",
        model: %{
          small: base_model_settings("llama-3.3-70b", temperature: 0.6),
          medium: base_model_settings("llama-3.3-70b", temperature: 0.6),
          large: base_model_settings("llama-3.1-405b", temperature: 0.6),
          image: %{name: "fluently-xl"}
        }
      },
      nineteen_ai: %{
        endpoint: "https://api.nineteen.ai/v1",
        model: %{
          small: base_model_settings("unsloth/Llama-3.2-3B-Instruct", temperature: 0.6),
          medium: base_model_settings("unsloth/Meta-Llama-3.1-8B-Instruct", temperature: 0.6),
          large:
            base_model_settings("hugging-quants/Meta-Llama-3.1-70B-Instruct-AWQ-INT4",
              temperature: 0.6
            ),
          image: %{name: "dataautogpt3/ProteusV0.4-Lightning"}
        }
      },
      akash_chat_api: %{
        endpoint: "https://chatapi.akash.network/api/v1",
        model: %{
          small: base_model_settings("Meta-Llama-3-2-3B-Instruct", temperature: 0.6),
          medium: base_model_settings("Meta-Llama-3-3-70B-Instruct", temperature: 0.6),
          large: base_model_settings("Meta-Llama-3-1-405B-Instruct-FP8", temperature: 0.6)
        }
      },
      livepeer: %{
        model: %{
          image: %{name: "ByteDance/SDXL-Lightning"}
        }
      },
      infera: %{
        endpoint: "https://api.infera.org",
        model: %{
          small: base_model_settings("llama3.2:3b", temperature: 0.6),
          medium: base_model_settings("mistral-nemo:latest", temperature: 0.6),
          large: base_model_settings("mistral-small:latest", temperature: 0.6)
        }
      }
    }
  end

  @doc """
  Lists all supported providers by returning the keys in `providers/0`.

  ## Examples

      iex> providers = Jido.AI.Models.Registry.list_providers()
      iex> :openai in providers
      true
  """
  @spec list_providers() :: [provider()]
  def list_providers do
    Map.keys(providers())
  end

  @doc """
  Fetches the configuration for the given `provider_name`.

  Returns `nil` if the provider is not found.

  ## Examples

      iex> Jido.AI.Models.Registry.get_provider(:openai)
      %{
        endpoint: "https://api.openai.com/v1",
        model: ...
      }

      iex> Jido.AI.Models.Registry.get_provider(:unknown_provider)
      nil
  """
  @spec get_provider(provider()) :: provider_config() | nil
  def get_provider(provider_name) do
    Map.get(providers(), provider_name)
  end

  @doc """
  Retrieves model settings for a given provider and size, e.g. `:small`, `:medium`, or `:large`.

  Returns `nil` if not found.

  ## Examples

      iex> Jido.AI.Models.Registry.get_model_settings(:anthropic, :small)
      %{
        name: "claude-3-haiku-20240307",
        ...
      }

      iex> Jido.AI.Models.Registry.get_model_settings(:unknown, :small)
      nil
  """
  @spec get_model_settings(provider(), size()) :: model_settings() | nil
  def get_model_settings(provider_name, size) do
    with %{model: models} <- get_provider(provider_name),
         settings when not is_nil(settings) <- Map.get(models, size) do
      settings
    else
      _ -> nil
    end
  end

  @doc """
  Returns the embedding settings for the given provider, if available.

  ## Examples

      iex> Jido.AI.Models.Registry.get_embedding_settings(:openai)
      %{name: "text-embedding-3-small", dimensions: 1536}
  """
  @spec get_embedding_settings(provider()) :: embedding_settings() | nil
  def get_embedding_settings(provider_name) do
    with %{model: %{embedding: settings}} <- get_provider(provider_name) do
      settings
    else
      _ -> nil
    end
  end

  @doc """
  Returns the image generation settings for the given provider, if available.

  ## Examples

      iex> Jido.AI.Models.Registry.get_image_settings(:openai)
      %{name: "dall-e-3"}
  """
  @spec get_image_settings(provider()) :: image_settings() | nil
  def get_image_settings(provider_name) do
    with %{model: %{image: settings}} <- get_provider(provider_name) do
      settings
    else
      _ -> nil
    end
  end
end
