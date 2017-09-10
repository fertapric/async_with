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

  The attribute `@async_with_timeout` can be used to configure the maximum time allowed per
  clause. It expects a timeout in milliseconds, with the default value of `5000`.

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

  alias AsyncWith.Clause

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
  defmacro async(with_expression, do_else_blocks)
  defmacro async({:with, _meta, ast}, blocks), do: do_async(ast, blocks)
  defmacro async(_, _), do: raise(ArgumentError, ~s("async" macro must be used with "with"))

  defp do_async(nil, blocks), do: quote(do: with(unquote(blocks)))
  defp do_async(ast, blocks) do
    Keyword.get(blocks, :do) || raise(~s(missing :do option in "async with"))

    clauses = Clause.many_from_ast(ast)
    dependency_graph =
      clauses
      |> DependencyGraph.new()
      |> DependencyGraph.merge_vertices_with_common_out_neighbours()

    AsyncWith.Macro.DependencyGraph.to_ast(dependency_graph, blocks)
  end
end
