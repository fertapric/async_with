defmodule AsyncWith.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Task.Supervisor, [[name: AsyncWith.TaskSupervisor]])
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AsyncWith.Supervisor)
  end
end
