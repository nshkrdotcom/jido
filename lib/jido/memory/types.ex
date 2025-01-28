defmodule Jido.Memory.Types do
  @moduledoc """
  Common data structures used by Jido.Memory.
  """

  defmodule Memory do
    @enforce_keys [:id, :user_id, :agent_id, :room_id, :content, :created_at]
    defstruct [
      :id,
      :user_id,
      :agent_id,
      :room_id,
      :content,
      :created_at,
      :embedding,
      unique: false,
      similarity: nil
    ]
  end

  defmodule KnowledgeItem do
    @enforce_keys [:id, :agent_id, :content, :created_at]
    defstruct [
      :id,
      :agent_id,
      :content,
      :created_at,
      :embedding,
      :metadata,
      :similarity
    ]
  end
end
