defmodule AsyncWith do
  @moduledoc ~S"""
  A modifier for `with` to execute all its clauses in parallel.

  ## Example

      defmodule AcmeWeb.PostController do
        use AcmeWeb, :controller
        use AsyncWith

        def show(conn, %{"id" => id}) do
          async with {:ok, post} <- Blog.get_post(id),
                     {:ok, author} <- Users.get_user(post.author_id),
                     {:ok, posts_by_the_same_author} <- Blog.get_posts(author),
                     {:ok, similar_posts} <- Blog.get_similar_posts(post),
                     {:ok, comments} <- Blog.list_comments(post),
                     {:ok, comments} <- Blog.preload(comments, :author) do
            conn
            |> assign(:post, post)
            |> assign(:author, author)
            |> assign(:posts_by_the_same_author, posts_by_the_same_author)
            |> assign(:similar_posts, similar_posts)
            |> assign(:comments, comments)
            |> render("show.html")
          end
        end
      end

  ## Timeout attribute

  The attribute `@async_with_timeout` can be used to configure the maximum time allowed to
  execute all the clauses. It expects a timeout in milliseconds, with the default value of
  `5000`.

      defmodule Acme do
        use AsyncWith

        @async_with_timeout 1_000

        def get_user_info(user_id) do
          async with {:ok, user} <- HTTP.get("users/#{user_id}"),
                     {:ok, stats} <- HTTP.get("users/#{user_id}/stats")
            Map.merge(user, %{stats: stats})
          end
        end
      end

  """

  alias AsyncWith.Clauses
  alias AsyncWith.Macro, as: M

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__), only: [async: 2]

      @async_with_timeout 5_000
    end
  end

  @doc """
  Modifies the `with` macro to execute all its clauses in parallel.

  Let's start with an example:

      iex> opts = %{width: 10, height: 15}
      iex> async with {:ok, width} <- Map.fetch(opts, :width),
      ...>            {:ok, height} <- Map.fetch(opts, :height) do
      ...>   {:ok, width * height}
      ...> end
      {:ok, 150}

  As in `with/1`, if all clauses match, the `do` block is executed, returning its result.
  Otherwise the chain is aborted and the non-matched value is returned:

      iex> opts = %{width: 10}
      iex> async with {:ok, width} <- Map.fetch(opts, :width),
      ...>            {:ok, height} <- Map.fetch(opts, :height) do
      ...>  {:ok, width * height}
      ...> end
      :error

  However, using `async with`, the right side of `<-` is always executed inside a new task. As
  soon as any of the tasks finishes, the task that depends on the previous one will be resolved.
  In other words, `async with` will solve the dependency graph and write the asynchronous code
  in the most performant way as possible. It also ensures that, if a clause does not match, any
  running task is shut down.

  In addition, guards can be used in patterns as well:

      iex> users = %{"melany" => "guest", "bob" => :admin}
      iex> async with {:ok, role} when not is_binary(role) <- Map.fetch(users, "bob") do
      ...>   :ok
      ...> end
      :ok

  As in `with/1`, variables bound inside `async with` won't leak;
  "bare expressions" may also be inserted between the clauses:

      iex> width = nil
      iex> opts = %{width: 10, height: 15}
      iex> async with {:ok, width} <- Map.fetch(opts, :width),
      ...>            double_width = width * 2,
      ...>            {:ok, height} <- Map.fetch(opts, :height) do
      ...>   {:ok, double_width * height}
      ...> end
      {:ok, 300}
      iex> width
      nil

  An `else` option can be given to modify what is being returned from `async with` in the
  case of a failed match:

      iex> opts = %{width: 10}
      iex> async with {:ok, width} <- Map.fetch(opts, :width),
      ...>            {:ok, height} <- Map.fetch(opts, :height) do
      ...>   {:ok, width * height}
      ...> else
      ...>   :error ->
      ...>     {:error, :wrong_data}
      ...> end
      {:error, :wrong_data}

  If there is no matching `else` condition, then a `AsyncWith.ClauseError` exception is raised.

  Order-dependent clauses that do not express their dependency via their used or defined
  variables could lead to race conditions, as they are executed in separated tasks:

      async with Agent.update(agent, fn _ -> 1 end),
                 Agent.update(agent, fn _ -> 2 end) do
        Agent.get(agent, fn state -> state end) # 1 or 2
      end

  """
  defmacro async(with_expression, blocks)

  defmacro async({:with, _meta, nil}, blocks), do: quote(do: with(unquote(blocks)))

  defmacro async({:with, _meta, ast}, do: do_block, else: else_block) do
    emit_warning_if_clauses_always_match(ast, Macro.Env.stacktrace(__CALLER__))
    do_async(ast, do: do_block, else: prepare_else_block(else_block))
  end

  defmacro async({:with, _meta, ast}, do: do_block) do
    emit_warning_if_clauses_always_match(ast, Macro.Env.stacktrace(__CALLER__))
    do_async(ast, do: do_block, else: quote(do: (error -> error)))
  end

  defmacro async({:with, _meta, _ast}, _), do: raise(~s(missing :do option in "async with"))

  defmacro async(_, _), do: raise(ArgumentError, ~s("async" macro must be used with "with"))

  defp do_async(ast, do: do_block, else: else_block) do
    clauses = Clauses.from_ast(ast)
    success_block = get_success_block(clauses, do_block)

    quote do
      task =
        Task.Supervisor.async_nolink(AsyncWith.TaskSupervisor, fn ->
          clauses = Enum.map(unquote(Enum.map(clauses, &Map.to_list/1)), &Enum.into(&1, %{}))
          AsyncWith.async_with(clauses)
        end)

      timeout_exit = {:exit, {:timeout, {unquote(__MODULE__), :async, [@async_with_timeout]}}}

      case Task.yield(task, @async_with_timeout) || Task.shutdown(task) || timeout_exit do
        {:ok, {:ok, values}} -> unquote(success_block)
        {:ok, {:match_error, %MatchError{term: term}}} -> raise(MatchError, term: term)
        {:ok, {:error, error}} -> case error, do: unquote(else_block)
        error -> case error, do: unquote(else_block)
      end
    end
  end

  # Emits a warning if all patterns in `async with` will always match.
  #
  # This mimics `with/1` behavior.
  defp emit_warning_if_clauses_always_match(ast, stacktrace) do
    if clauses_always_match?(ast) do
      message =
        ~s("else" clauses will never match because all patterns in "async with" will always match)

      IO.warn(message, stacktrace)
    end
  end

  # Returns true if all patterns in `clauses` will always match.
  defp clauses_always_match?(clauses) when is_list(clauses) do
    Enum.all?(clauses, fn
      {:<-, _meta, [left, _right]} -> M.var?(left)
      _ -> true
    end)
  end

  defp clauses_always_match?(clause), do: clauses_always_match?([clause])

  # Prepares the `else` block to raise `AsyncWith.ClauseError` if none of its
  # clauses match.
  defp prepare_else_block(else_block) do
    if contains_always_match_else_clauses?(else_block) do
      else_block
    else
      else_block ++ quote(do: (term -> raise(AsyncWith.ClauseError, term: term)))
    end
  end

  # Returns true if the `else_block` contains a match-all else clause.
  #
  # This prevents messages like `warning: this clause cannot match because
  # a previous clause at line <line number> always matches`.
  defp contains_always_match_else_clauses?(else_block) do
    Enum.any?(else_block, fn {:->, _meta, [[left], _right]} -> M.var?(left) end)
  end

  defp get_success_block(clauses, do_block) do
    assignments =
      clauses
      |> Clauses.get_vars(:defined_vars)
      |> filter_renamed_vars()
      |> filter_internal_vars(clauses, do_block)
      |> Enum.map(fn var ->
        quote do
          unquote(Macro.var(var, nil)) = Keyword.fetch!(values, unquote(var))
        end
      end)

    quote do
      with unquote_splicing(assignments), do: unquote(do_block)
    end
  end

  # Filters variables that have been renamed because they are rebinded in other clauses.
  #
  # Prevents `warning: variable "<variable>" is unused`, since renamed variables are not used
  # in the `:do` block.
  #
  # See `AsyncWith.Clause` for more information.
  defp filter_renamed_vars(vars) do
    Enum.reject(vars, fn var ->
      case Atom.to_string(var) do
        "async_with_" <> _ -> true
        _ -> false
      end
    end)
  end

  # Prevents `warning: variable "<variable>" is unused` on internal variables, used in other
  # clauses or guards.
  #
  # As example, the compiler would report a warning on
  #
  #     async with {:ok, width} <- {:ok, 10},
  #                double_width = width * 2 do
  #       {:ok, double_width}
  #     end
  #
  # because the resulting AST
  #
  #     with width = Keyword.fetch!(state, :width),
  #          double_width = Keyword.fetch!(state, :double_width) do
  #       {:ok, double_width}
  #     end
  #
  # would not use the `width` variable to compute `double_width`.
  defp filter_internal_vars(vars, clauses, do_block) do
    do_block_vars = MapSet.new(AsyncWith.Macro.get_vars(do_block))
    used_vars = Clauses.get_vars(clauses, :used_vars)
    guard_vars = Clauses.get_vars(clauses, :guard_vars)

    Enum.reject(vars, fn var ->
      not var in do_block_vars and (var in used_vars or var in guard_vars)
    end)
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
