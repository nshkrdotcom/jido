# Do You Need an Agent?

_Part of the "About Jido" section in the documentation._

This guide helps developers evaluate whether their use case is appropriate for an agent-based solution using Jido. It covers common scenarios where agents excel, potential alternatives, and factors to consider when making architectural decisions.

Agents are a hot topic right now, but they aren't a silver bullet. In particular, Large Language Models (LLMs) are powerful yet slow and costly—if your application doesn't require dynamic decision-making or complex planning, consider whether you really need an Agent at all.

- **LLMs aren't required for all tasks** — Avoid building them into your core logic unless necessary
- **Agents as Dynamic ETL** — Agents dynamically direct data ingestion, transformation, and output based on:
  - LLMs (e.g., GPT)
  - Classical planning algorithms (A\*, Behavior Trees, etc.)
- **Simplicity often wins** — If you don't need these dynamic behaviors, you probably don't need an Agent. This library is likely overkill compared to straightforward code.

### Our Definition of an Agent

An Agent is a system where LLMs _or_ classical planning algorithms dynamically direct their own processes. Some great definitions from the community:

- "Agents are Dynamic ETL processes directed by LLMs" — [YouTube](https://youtu.be/KY8n96Erp5Q?si=5Itt7QR11jgfWDTY&t=22)
- "Agents are systems where LLMs dynamically direct their own processes" — [Anthropic Research](https://www.anthropic.com/research/building-effective-agents)
- "AI Agents are programs where LLM outputs control the workflow" — [Hugging Face Blog](https://huggingface.co/blog/smolagents)

If your application doesn't involve dynamic workflows or data pipelines that change based on AI or planning algorithms, you can likely do more with less.

> 💡 **NOTE**: This library intends to support both LLM planning and Classical AI planning (ie. [Behavior Trees](https://github.com/jschomay/elixir-behavior-tree) as a design principle via Actions. See [`jido_ai`](https://github.com/agentjido/jido_ai) for example LLM actions.

_This space is evolving rapidly. Last updated 2025-01-01_?
