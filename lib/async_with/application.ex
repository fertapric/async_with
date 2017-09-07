defmodule AsyncWith.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Batch.Supervisor, [[name: AsyncWith.BatchSupervisor]])
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AsyncWith.Supervisor)
  end
end
