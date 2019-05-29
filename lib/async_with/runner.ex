defmodule AsyncWith.Runner do
  @moduledoc false

  import AsyncWith.Clauses
  import AsyncWith.Macro, only: [rename_ignored_vars: 1, var_map: 1]

  @doc """
  Transforms the list of `clauses` into a format that the runner can work with.

  The runner expects each clause to be represented by a map with these fields:

    * `:function` - an anonymous function that wraps the clause so it can be
      executed inside a task.

      It must accept only one argument, a map with the values of the variables
      used inside the clause. For example, `%{opts: %{width: 10 }}` could be
      a valid argument for the clause `{:ok, width} <- Map.fetch(opts, :width)`.

      In case of success, it must return a triplet with `:ok`, the value
      returned by the execution of the right hand side of the clause and a map
      with the values defined in the left hand side of the clause. For example,
      the clause `{:ok, width} <- Map.fetch(opts, :width)` with the argument
      `%{opts: %{width: 10 }}` would return `{:ok, {:ok, 10}, %{width: 10}}`.

      In case of error, it must return `{:error, right_value}` if the sides of
      the clause do not match using the arrow operator `<-`; `{:nomatch, error}`
      if the sides of the clause do not match using the match operator `=`;
      `{:norescue, exception}` if the clause raises any exception; and
      `{:nocatch, value}` if the clause throws any value.

    * `:deps` - the list of variables that the clause depends on.

  This operation is order dependent.

  It's important to keep in mind that this function is executed at compile time,
  and that it must return a quoted expression that represents the first argument
  that will be passed to `run_nolink/2` at runtime.
  """
  @spec format_clauses(Macro.t()) :: Macro.t()
  def format_clauses(clauses) do
    clauses
    |> format_bare_expressions()
    |> rename_ignored_vars()
    |> rename_local_vars()
    |> get_defined_and_used_local_vars()
    |> Enum.map(&format_clause/1)
  end

  defp format_clause({clause, {defined_vars, used_vars}}) do
    function = clause_to_function({clause, {defined_vars, used_vars}})
    {:%{}, [], [function: function, deps: used_vars]}
  end

  defp clause_to_function({{operator, meta, [left, right]}, {defined_vars, used_vars}}) do
    quote do
      fn vars ->
        try do
          with unquote(var_map(used_vars)) <- vars,
               value <- unquote(right),
               unquote({operator, meta, [left, Macro.var(:value, __MODULE__)]}) do
            {:ok, value, unquote(var_map(defined_vars))}
          else
            error -> {:error, error}
          end
        rescue
          error in MatchError -> {:nomatch, error}
          error -> {:norescue, error}
        catch
          thrown_value -> {:nocatch, thrown_value}
        end
      end
    end
  end

  @doc """
  Executes `run/1` in a supervised task (under `AsyncWith.TaskSupervisor`) and
  returns the results of the operation.

  The task won’t be linked to the caller, see `Task.async/3` for more
  information.

  A `timeout`, in milliseconds, must be provided to specify the maximum time
  allowed for this operation to complete.
  """
  @spec run_nolink([map], non_neg_integer) ::
          {:ok, any} | {:error | :nomatch | :norescue | :nocatch, any}
  def run_nolink(clauses, timeout) do
    task = Task.Supervisor.async_nolink(AsyncWith.TaskSupervisor, fn -> run(clauses) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      nil -> {:error, {:exit, {:timeout, {AsyncWith, :async, [timeout]}}}}
      {:ok, value} -> value
      error -> {:error, error}
    end
  end

  @doc """
  Executes all the `clauses` and collects their results.

  Each clause is executed inside a new task. Tasks are spawned as soon as all
  the variables that it depends on `:deps` are resolved. It also ensures that,
  if a clause fails, all the running tasks are shut down.
  """
  @spec run([map]) :: {:ok, [any]} | {:error | :nomatch | :norescue | :nocatch, any}
  def run(clauses) do
    if all_completed?(clauses) do
      {:ok, Enum.map(clauses, & &1.value)}
    else
      clauses
      |> maybe_spawn_tasks()
      |> await()
    end
  end

  defp all_completed?(clauses), do: Enum.all?(clauses, &Map.get(&1, :completed, false))

  defp await(clauses) do
    receive do
      {ref, {:ok, value, vars}} ->
        Process.demonitor(ref, [:flush])

        clauses
        |> assign_results_and_mark_as_completed(ref, value, vars)
        |> run()

      {_ref, error} ->
        shutdown_tasks(clauses)
        error

      {:DOWN, _ref, _, _, reason} ->
        exit(reason)
    end
  end

  defp maybe_spawn_tasks(clauses) do
    vars = Enum.reduce(clauses, %{}, &Map.merge(&2, Map.get(&1, :vars, %{})))

    Enum.map(clauses, fn clause ->
      if spawn_task?(clause, vars) do
        Map.merge(clause, %{task: Task.async(fn -> clause.function.(vars) end)})
      else
        clause
      end
    end)
  end

  defp spawn_task?(%{task: _task}, _vars), do: false
  defp spawn_task?(%{deps: deps}, vars), do: Enum.empty?(deps -- Map.keys(vars))

  defp assign_results_and_mark_as_completed(clauses, ref, value, vars) do
    Enum.map(clauses, fn
      %{task: %Task{ref: ^ref}} = clause ->
        Map.merge(clause, %{value: value, vars: vars, completed: true})

      clause ->
        clause
    end)
  end

  defp shutdown_tasks(clauses) do
    Enum.each(clauses, fn
      %{task: task} -> Task.shutdown(task)
      _ -> nil
    end)
  end
end
