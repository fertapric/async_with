defmodule AsyncWith.Runner do
  @moduledoc false

  alias AsyncWith.Clauses

  def run(clauses, timeout) do
    task = Task.Supervisor.async_nolink(AsyncWith.TaskSupervisor, fn ->
      clauses = Enum.map(clauses, &Enum.into(&1, %{}))
      AsyncWith.Runner.async_with(clauses)
    end)

    timeout_exit = {:exit, {:timeout, {AsyncWith, :async, [timeout]}}}

    Task.yield(task, timeout) || Task.shutdown(task) || timeout_exit
  end

  # Returns the values of all the variables binded in `clauses`.
  #
  # Performs the following steps:
  #
  #   1. Spawns a process per each clause whose dependencies are processed.
  #   2. Waits for replies.
  #   3. Processes the reply:
  #       3.1. Removes the clause from the list of clauses to be processed.
  #       3.2. Updates the current state
  #   4. Repeats step 1 until all the clauses are processed.
  #
  # In case of failure, the error is returned immediately and all the processes are killed.
  #
  # ## Examples
  #
  #     async with a <- 1,
  #                b <- a + 2,
  #                c <- {a, b} do
  #     end
  #
  # In the example above, there are three clauses:
  #
  #   * `a <- 1` with no dependencies
  #   * `b <- a + 2` with a dependency on the variable `a`
  #   * `c <- {a, b}` with a dependency in both variables `a` and `b`
  #
  # The final sequence would be then:
  #
  #    1. Initial state:
  #         - Clauses: [`a <- 1`, `b <- a + 2`, `c <- {a, b}`]
  #         - Values: []
  #    2. Spawn `a <- 1` as it does not have dependencies.
  #    3. Wait for `a <- 1` reply.
  #    4. Process `a <- 1` reply:
  #         - Clauses: [`b <- a + 2`, `c <- {a, b}`]
  #         - Values: [a: 1]
  #    5. Spawn `b <- a + 2` now that `a` is processed.
  #    6. Wait for `b <- a + 2` reply.
  #    7. Process `b <- a + 2` reply:
  #         - Clauses: [`c <- {a, b}`]
  #         - Values: [a: 1, b: 3]
  #    8. Spawn `c <- {a, b}` now that `a` and `b` are processed.
  #    9. Wait for `c <- {a, b}` reply.
  #   10. Process `c <- {a, b}` reply:
  #         - Clauses: []
  #         - Values: [a: 1, b: 3, c: {1, 3}]
  #   11. Return [a: 1, b: 3, c: {1, 3}]
  #
  @doc false
  @spec async_with([Clauses.clause()], keyword) :: {:ok, keyword} | any
  def async_with(clauses, results \\ [])
  def async_with([], results), do: {:ok, results}

  def async_with(clauses, results) do
    clauses = spawn_tasks(clauses, results)

    receive do
      {ref, {:ok, reply}} ->
        Process.demonitor(ref, [:flush])
        async_with(remove_clause(clauses, ref), Keyword.merge(results, reply))

      {_ref, reply} ->
        shutdown_tasks(clauses)
        reply

      {:DOWN, _ref, _, proc, reason} ->
        exit(reason(reason, proc))
    end
  end

  defp remove_clause(clauses, ref) do
    clause =
      Enum.find(clauses, fn
        %{task: %Task{ref: ^ref}} -> true
        _ -> false
      end)

    clauses -- [clause]
  end

  defp shutdown_tasks(clauses) do
    Enum.each(clauses, fn
      %{task: task} -> Task.shutdown(task)
      _ -> nil
    end)
  end

  # Spawns all the tasks whose dependencies have been processed.
  defp spawn_tasks(clauses, results) do
    processed_vars = Keyword.keys(results)

    Enum.map(clauses, fn clause ->
      if spawn_task?(clause, processed_vars) do
        task = Task.async(fn -> clause.function.(results) end)
        Map.merge(clause, %{task: task})
      else
        clause
      end
    end)
  end

  defp spawn_task?(%{task: _task}, _processed_vars), do: false

  defp spawn_task?(%{used_vars: used_vars}, processed_vars) do
    # All the dependencies are processed
    used_vars -- processed_vars == []
  end

  defp reason(:noconnection, proc), do: {:nodedown, monitor_node(proc)}
  defp reason(reason, _), do: reason

  defp monitor_node(pid) when is_pid(pid), do: node(pid)
  defp monitor_node({_, node}), do: node
end
