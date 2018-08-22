defmodule AsyncWith do
  @moduledoc ~S"""
  The asynchronous version of Elixir's `with`.

  `async with` always executes the right side of each clause inside a new task.
  Tasks are spawned as soon as all the tasks that it depends on are resolved.
  In other words, `async with` resolves the dependency graph and executes all
  the clauses in the most performant way possible. It also ensures that, if a
  clause does not match, any running task is shut down.

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

  The attribute `@async_with_timeout` can be used to configure the maximum time
  allowed to execute all the clauses. It expects a timeout in milliseconds, with
  the default value of `5000`.

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
  alias AsyncWith.Runner

  @default_timeout 5_000

  defmacro __using__(_) do
    # Module attributes can only be defined inside a module.
    # This allows to `use AsyncWith` inside an interactive IEx session.
    timeout =
      if __CALLER__.module do
        quote do
          @async_with_timeout unquote(@default_timeout)
        end
      end

    quote do
      import unquote(__MODULE__), only: [async: 1, async: 2]

      unquote(timeout)
    end
  end

  @doc """
  Used to combine matching clauses, executing them asynchronously.

  `async with` always executes the right side of each clause inside a new task.
  Tasks are spawned as soon as all the tasks that it depends on are resolved.
  In other words, `async with` resolves the dependency graph and executes all
  the clauses in the most performant way possible. It also ensures that, if a
  clause does not match, any running task is shut down.

  Let's start with an example:

      iex> opts = %{width: 10, height: 15}
      iex> async with {:ok, width} <- Map.fetch(opts, :width),
      ...>            {:ok, height} <- Map.fetch(opts, :height) do
      ...>   {:ok, width * height}
      ...> end
      {:ok, 150}

  As in `with/1`, if all clauses match, the `do` block is executed, returning its
  result. Otherwise the chain is aborted and the non-matched value is returned:

      iex> opts = %{width: 10}
      iex> async with {:ok, width} <- Map.fetch(opts, :width),
      ...>            {:ok, height} <- Map.fetch(opts, :height) do
      ...>  {:ok, width * height}
      ...> end
      :error

  In addition, guards can be used in patterns as well:

      iex> users = %{"melany" => "guest", "ed" => :admin}
      iex> async with {:ok, role} when is_atom(role) <- Map.fetch(users, "ed") do
      ...>   :ok
      ...> end
      :ok

  Variables bound inside `async with` won't leak; "bare expressions" may also
  be inserted between the clauses:

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

  An `else` option can be given to modify what is being returned from
  `async with` in the case of a failed match:

      iex> opts = %{width: 10}
      iex> async with {:ok, width} <- Map.fetch(opts, :width),
      ...>            {:ok, height} <- Map.fetch(opts, :height) do
      ...>   {:ok, width * height}
      ...> else
      ...>   :error ->
      ...>     {:error, :wrong_data}
      ...> end
      {:error, :wrong_data}

  If an `else` block is used and there are no matching clauses, an
  `AsyncWith.ClauseError` exception is raised.

  Order-dependent clauses that do not express their dependency via their used or
  defined variables could lead to race conditions, as they are executed in
  separated tasks:

      async with Agent.update(agent, fn _ -> 1 end),
                 Agent.update(agent, fn _ -> 2 end) do
        Agent.get(agent, fn state -> state end) # 1 or 2
      end

  """
  defmacro async(with_expression, blocks \\ [])

  # `async with` with no arguments.
  #
  # Example:
  #
  #     async with do
  #       1
  #     end
  #
  defmacro async({:with, _meta, args}, do: do_block, else: _else_block) when not is_list(args) do
    warn_else_clauses_will_never_match(__CALLER__)
    quote(do: with(do: unquote(do_block)))
  end

  defmacro async({:with, _meta, args}, do: do_block) when not is_list(args) do
    quote(do: with(do: unquote(do_block)))
  end

  # `async with` with :do and :else blocks.
  #
  # Example:
  #
  #     async with a <- function(),
  #                b <- function(a) do
  #       {a, b}
  #     else
  #       error -> error
  #     end
  #
  defmacro async({:with, _meta, clauses}, do: do_block, else: else_block) do
    if Clauses.always_match?(clauses), do: warn_else_clauses_will_never_match(__CALLER__)
    do_async(__CALLER__.module, clauses, do: do_block, else: else_block)
  end

  defmacro async({:with, _meta, clauses}, do: do_block) do
    do_async(__CALLER__.module, clauses, do: do_block, else: quote(do: (error -> error)))
  end

  # `async with` with :do and :else options (single line).
  #
  # Example:
  #
  #     async with a <- function(),
  #                b <- function(a),
  #                do: {a, b}
  #
  defmacro async({:with, _meta, args}, _) when is_list(args) do
    case List.last(args) do
      [do: do_block, else: else_block] ->
        clauses = List.delete_at(args, -1)
        if Clauses.always_match?(clauses), do: warn_else_clauses_will_never_match(__CALLER__)
        do_async(__CALLER__.module, clauses, do: do_block, else: else_block)

      [do: do_block] ->
        clauses = List.delete_at(args, -1)
        do_async(__CALLER__.module, clauses, do: do_block, else: quote(do: (error -> error)))

      _ ->
        message = ~s(missing :do option in "async with")
        raise(CompileError, file: __CALLER__.file, line: __CALLER__.line, description: message)
    end
  end

  defmacro async({:with, _meta, _args}, _) do
    message = ~s(missing :do option in "async with")
    raise(CompileError, file: __CALLER__.file, line: __CALLER__.line, description: message)
  end

  defmacro async(_, _) do
    message = ~s("async" macro must be used with "with")
    raise(CompileError, file: __CALLER__.file, line: __CALLER__.line, description: message)
  end

  defp do_async(module, clauses, do: do_block, else: else_block) do
    # Module attributes can only be defined inside a module.
    # This allows to `use AsyncWith` inside an interactive IEx session.
    timeout = if module, do: quote(do: @async_with_timeout), else: @default_timeout

    quote do
      case Runner.run_nolink(unquote(Runner.format_clauses(clauses)), unquote(timeout)) do
        {:ok, values} ->
          with unquote_splicing(change_right_hand_side_of_clauses_to_read_from_values(clauses)) do
            unquote(do_block)
          end

        {:nomatch, %MatchError{term: term}} ->
          raise(MatchError, term: term)

        {:norescue, error} ->
          raise(error)

        {:nocatch, thrown_value} ->
          throw(thrown_value)

        {:error, error} ->
          case error, do: unquote(maybe_change_else_block_to_raise_clause_error(else_block))
      end
    end
  end

  # Prints a warning message saying that "else" clauses will never match
  # because all patterns in "async with" will always match.
  #
  # This mimics `with/1` behavior.
  defp warn_else_clauses_will_never_match(caller) do
    message =
      ~s("else" clauses will never match because all patterns in "async with" will always match)

    IO.warn(message, Macro.Env.stacktrace(caller))
  end

  # Changes the `else_block` to raise `AsyncWith.ClauseError` if none of the
  # "else" clauses match.
  defp maybe_change_else_block_to_raise_clause_error(else_block) do
    if Clauses.contains_match_all_clause?(else_block) do
      else_block
    else
      else_block ++ quote(do: (term -> raise(AsyncWith.ClauseError, term: term)))
    end
  end

  # Changes the right hand side of each clause to read from the `values`
  # variable.
  #
  # Keeping the left hand side prevents warning messages with variables only
  # used in guards: `warning: variable "<variable>" is unused`.
  #
  #     async with {:ok, level} when level > 4 <- get_security_level(user_id),
  #                {:ok, data} <- read_secret_data() do
  #       {:ok, data}
  #     end
  #
  defp change_right_hand_side_of_clauses_to_read_from_values(clauses) do
    {clauses, _index} =
      clauses
      |> Clauses.format_bare_expressions()
      |> Clauses.get_defined_and_used_local_vars()
      |> Enum.map_reduce(0, fn {{operator, meta, [left, _]}, {_defined_vars, used_vars}}, index ->
        # Used variables are passed as the third argument to prevent warning messages
        # with temporary variables: `warning: variable "<variable>" is unused`.
        #
        # The variable `width` is an example of a temporary variable:
        #
        #     async with {:ok, width} <- {:ok, 10},
        #                double_width = width * 2 do
        #       {:ok, double_width}
        #     end
        #
        right =
          quote do
            Enum.at(values, unquote(index), unquote(AsyncWith.Macro.var_list(used_vars)))
          end

        {{operator, meta, [left, right]}, index + 1}
      end)

    clauses
  end
end
