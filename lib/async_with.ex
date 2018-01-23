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

  @default_timeout 5_000

  defmacro __using__(_) do
    # Module attributes can only be defined inside a module.
    # This allows to `use AsyncWith` inside an interactive IEx session.
    timeout = if __CALLER__.module, do: quote(do: @async_with_timeout unquote(@default_timeout))

    quote do
      import unquote(__MODULE__), only: [async: 1, async: 2]

      unquote(timeout)
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
  defmacro async(with_expression, blocks \\ [])

  defmacro async({:with, _meta, args}, do: do_block, else: _else_block) when not is_list(args) do
    print_warning_message_if_clauses_always_match([], Macro.Env.stacktrace(__CALLER__))
    quote(do: with(do: unquote(do_block)))
  end

  defmacro async({:with, _meta, args}, do: do_block) when not is_list(args) do
    quote(do: with(do: unquote(do_block)))
  end

  defmacro async({:with, _meta, clauses}, do: do_block, else: else_block) do
    print_warning_message_if_clauses_always_match(clauses, Macro.Env.stacktrace(__CALLER__))
    do_async(__CALLER__.module, clauses, do: do_block, else: else_block)
  end

  defmacro async({:with, _meta, clauses}, do: do_block) do
    do_async(__CALLER__.module, clauses, do: do_block, else: quote(do: (error -> error)))
  end

  defmacro async({:with, _meta, _args}, _) do
    message = ~s(missing :do option in "async with")
    raise(CompileError, file: __CALLER__.file, line: __CALLER__.line, description: message)
  end

  defmacro async(_, _), do: raise(ArgumentError, ~s("async" macro must be used with "with"))

  # TODO: warning: the result of the expression is ignored (suppress the warning by
  # assigning the expression to the _ variable)
  defp do_async(module, ast, do: do_block, else: else_block) do
    clauses = Clauses.from_ast(ast)
    error_block = change_else_block_to_raise_clause_error(else_block)
    success_block = get_success_block(clauses, do_block)
    clauses = Enum.map(clauses, &Map.to_list/1)

    # Module attributes can only be defined inside a module.
    # This allows to `use AsyncWith` inside an interactive IEx session.
    timeout = if module, do: quote(do: @async_with_timeout), else: @default_timeout

    quote do
      case AsyncWith.Runner.run(unquote(clauses), unquote(timeout)) do
        {:ok, {:ok, values}} -> unquote(success_block)
        {:ok, {:match_error, %MatchError{term: term}}} -> raise(MatchError, term: term)
        {:ok, {:error, error}} -> case error, do: unquote(error_block)
        error -> case error, do: unquote(error_block)
      end
    end
  end

  # Prints a warning message if all patterns in `async with` will always match.
  #
  # This mimics `with/1` behavior.
  defp print_warning_message_if_clauses_always_match(clauses, stacktrace) do
    if clauses_always_match?(clauses) do
      message =
        ~s("else" clauses will never match because all patterns in "async with" will always match)

      IO.warn(message, stacktrace)
    end
  end

  # Returns true if all patterns in `clauses` will always match.
  defp clauses_always_match?(clauses) do
    Enum.all?(clauses, fn
      {:<-, _meta, [left, _right]} -> AsyncWith.Macro.var?(left)
      _ -> true
    end)
  end

  # Changes the `else_block` to raise `AsyncWith.ClauseError` if none of its
  # clauses match.
  defp change_else_block_to_raise_clause_error(else_block) do
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
    Enum.any?(else_block, fn {:->, _meta, [[left], _right]} -> AsyncWith.Macro.var?(left) end)
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
      var not in do_block_vars and (var in used_vars or var in guard_vars)
    end)
  end
end
