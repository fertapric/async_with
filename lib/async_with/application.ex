defmodule AsyncWith.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: AsyncWith.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AsyncWith.Supervisor)
  end
end
