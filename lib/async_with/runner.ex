defmodule AsyncWith.Runner do
  @moduledoc false

  import AsyncWith.Macro, only: [rename_ignored_vars: 1, var_map: 1]

  alias AsyncWith.Clauses

  @doc """
  """
  @spec format(Macro.t()) :: Macro.t()
  def format(clauses) do
    clauses
    |> Clauses.format_bare_expressions()
    |> rename_ignored_vars()
    |> Clauses.rename_local_vars()
    |> Clauses.get_defined_and_used_local_vars()
    |> Enum.map(fn {{operator, meta, [left, right]}, {defined_vars, used_vars}} ->
      function_ast =
        quote do
          fn vars ->
            try do
              with unquote(var_map(used_vars)) <- vars,
                   value <- unquote(right),
                   unquote({operator, meta, [left, Macro.var(:value, __MODULE__)]}) do
                {:ok, unquote(Macro.var(:value, __MODULE__)), unquote(var_map(defined_vars))}
              else
                error -> {:error, error}
              end
            rescue
              error in MatchError -> {:match_error, error}
            catch
              thrown_value -> {:nocatch, thrown_value}
            end
          end
        end

      {:%{}, [], [used_vars: used_vars, function: function_ast]}
    end)
  end

  def run(clauses, timeout) do
    task = Task.Supervisor.async_nolink(AsyncWith.TaskSupervisor, fn -> async_with(clauses) end)

    timeout_exit = {:exit, {:timeout, {AsyncWith, :async, [timeout]}}}

    case Task.yield(task, timeout) || Task.shutdown(task) || timeout_exit do
      {:ok, {:ok, value}} -> {:ok, value}
      {:ok, {:match_error, error}} -> {:match_error, error}
      {:ok, {:nocatch, thrown_value}} -> {:nocatch, thrown_value}
      {:ok, {:error, error}} -> {:error, error}
      error -> {:error, error}
    end
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
  @spec async_with([map], map) :: {:ok, map} | any
  def async_with(clauses, processed_vars \\ %{}) do
    case Enum.all?(clauses, &Map.get(&1, :processed, false)) do
      true ->
        {:ok, Enum.map(clauses, & &1.value)}

      false ->
        clauses = spawn_tasks(clauses, processed_vars)

        receive do
          {ref, {:ok, value, vars}} ->
            Process.demonitor(ref, [:flush])
            async_with(store_value(clauses, ref, value), Map.merge(processed_vars, vars))

          {_ref, reply} ->
            shutdown_tasks(clauses)
            reply

          {:DOWN, _ref, _, proc, reason} ->
            # TODO: test
            exit(reason(reason, proc))
        end
    end
  end

  defp store_value(clauses, ref, value) do
    Enum.map(clauses, fn
      %{task: %Task{ref: ^ref}} = clause -> Map.merge(clause, %{processed: true, value: value})
      clause -> clause
    end)
  end

  defp shutdown_tasks(clauses) do
    Enum.each(clauses, fn
      %{task: task} -> Task.shutdown(task)
      _ -> nil
    end)
  end

  # Spawns all the tasks whose dependencies have been processed.
  defp spawn_tasks(clauses, processed_vars) do
    Enum.map(clauses, fn clause ->
      if spawn_task?(clause, processed_vars) do
        task = Task.async(fn -> clause.function.(processed_vars) end)
        Map.merge(clause, %{task: task})
      else
        clause
      end
    end)
  end

  defp spawn_task?(%{task: _task}, _processed_vars), do: false

  defp spawn_task?(%{used_vars: used_vars}, processed_vars) do
    # All the dependencies are processed
    used_vars -- Map.keys(processed_vars) == []
  end

  # TODO: test
  defp reason(:noconnection, proc), do: {:nodedown, monitor_node(proc)}
  # TODO: test
  defp reason(reason, _), do: reason

  # TODO: test
  defp monitor_node(pid) when is_pid(pid), do: node(pid)
  # TODO: test
  defp monitor_node({_, node}), do: node
end
