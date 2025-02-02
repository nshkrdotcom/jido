defmodule Jido.Scheduler do
  @moduledoc """
  Quantum-based Scheduler for Cron jobs within Jido.

  By default, we attach this to the application supervision tree under the name `:jido_quantum`.
  """

  use Quantum,
    otp_app: :jido
end
