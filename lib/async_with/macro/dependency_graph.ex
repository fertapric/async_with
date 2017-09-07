defmodule AsyncWith.Macro.DependencyGraph do
  @moduledoc """
  Conveniences to represent dependency graphs in the Abstract Syntax Tree.
  """

  alias AsyncWith.DependencyGraph
  alias AsyncWith.DependencyGraph.Vertex

  @doc """
  Generates an AST node representing the `dependency_graph`.
  """
  @spec to_ast(DependencyGraph.t, keyword) :: Macro.t
  def to_ast(dependency_graph, blocks)

  def to_ast(%DependencyGraph{} = dependency_graph, do: do_block, else: else_block) do
    longest_path = get_longest_path(dependency_graph)

    quote do
      functions = unquote(get_functions(dependency_graph))
      batch = Batch.Supervisor.async_nolink(AsyncWith.BatchSupervisor, functions)
      timeout = unquote(length(longest_path)) * @async_with_timeout

      with {:ok, results} <- Batch.yield(batch, timeout) || {:exit, :timeout},
           unquote_splicing(get_with_clauses(dependency_graph, do_block)) do
        unquote(do_block)
      else
        error ->
          Batch.shutdown(batch)

          error =
            case error do
              {:error, {:error, error}} -> error
              {:error, error} -> error
              {:exit, reason} -> {:exit, reason}
            end

          case error do
            unquote(build_else_block(else_block))
          end
      end
    end
  end

  def to_ast(%DependencyGraph{} = dependency_graph, do: do_block) do
    to_ast(dependency_graph, do: do_block, else: quote(do: (error -> error)))
  end

  defp get_functions(%DependencyGraph{} = dependency_graph) do
    dependency_graph
    |> DependencyGraph.root_vertices()
    |> Enum.map(fn root_vertex ->
      quote do
        fn -> unquote(AsyncWith.Macro.Vertex.to_ast(dependency_graph, root_vertex)) end
      end
    end)
  end

  def get_longest_path(%DependencyGraph{} = dependency_graph) do
    dependency_graph
    |> DependencyGraph.root_vertices()
    |> Enum.map(&DependencyGraph.get_longest_path(dependency_graph, &1))
    |> Enum.max_by(&length/1)
  end

  defp get_with_clauses(%DependencyGraph{} = dependency_graph, do_block) do
    dependency_graph
    |> DependencyGraph.root_vertices()
    |> Enum.flat_map(fn root_vertex ->
      vars = get_vars(dependency_graph, root_vertex, do_block)

      quote do
        [
          {result, results} = List.pop_at(results, 0),
          {:ok, unquote(AsyncWith.Macro.vars(vars, nil))} <- result
        ]
      end
    end)
  end

  # Ignore unused variables to prevent warnings with the message `warning: variable "var" is
  # unused`.
  defp get_vars(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex, do_block) do
    do_block_vars = MapSet.new(AsyncWith.Macro.get_vars(do_block))
    used_vars = AsyncWith.Macro.Vertex.get_vars(dependency_graph, vertex, :used_vars)
    guard_vars = AsyncWith.Macro.Vertex.get_vars(dependency_graph, vertex, :guard_vars)

    dependency_graph
    |> AsyncWith.Macro.Vertex.get_vars(vertex, :defined_vars)
    |> ignore_renamed_vars()
    |> ignore_internal_vars(used_vars, guard_vars, do_block_vars)
  end

  # Ignore variables that have been renamed because they will be rebinded in other clauses.
  #
  # ## Example
  #
  # The variables in the following expression:
  #
  #     async with {:ok, a} <- echo("a"),
  #                {:ok, b} <- echo("b"),
  #                {:ok, a} <- echo("#{a}, #{b}") do
  #     end
  #
  # are renamed to:
  #
  #     async with {:ok, async_with_a_xxx} <- echo("a"),
  #                {:ok, b} <- echo("b"),
  #                {:ok, a} <- echo("#{async_with_a_xxx}, #{b}") do
  #     end
  #
  # to avoid collisions with the variable `a`. The temporary variable `async_with_a_xxx`
  # must be renamed to avoid `warning: variable "async_with_a_xxx" is unused`.
  #
  # See `AsyncWith.Clauses` for more information.
  defp ignore_renamed_vars(vars) do
    Enum.map(vars, fn var ->
      case Atom.to_string(var) do
        "async_with_" <> _ -> :"_#{var}"
        _ -> var
      end
    end)
  end

  # Prevent warnings with variables that were used only in the `async with` clauses.
  #
  # ## Example
  #
  #     async with {:ok, width} <- {:ok, 10},
  #                double_width = width * 2 do
  #       {:ok, double_width}
  #     end
  #
  # Without this logic, the compiler would report the variable `width` as unused
  # because the resulting AST of the dependency graph would be something like:
  #
  #     with {result, results} = List.pop_at(results, 0),
  #          [width, double_width] <- result do
  #       {:ok, double_width}
  #     end
  #
  # See `to_ast/2` for more information.
  defp ignore_internal_vars(vars, used_vars, guard_vars, do_block_vars) do
    Enum.map(vars, fn var ->
      if ! var in do_block_vars and (var in used_vars or var in guard_vars) do
        :"_#{var}"
      else
        var
      end
    end)
  end

  defp build_else_block(else_block) do
    quote(do: (%MatchError{term: term} -> raise(MatchError, term: term))) ++
    else_block ++
    case contains_always_match_condition?(else_block) do
      true -> []
      false -> quote(do: (term -> raise(AsyncWith.ClauseError, term: term)))
    end
  end

  # Checks else conditions to prevent warnings with the message `warning: this clause cannot
  # match because a previous clause at line <line number> always matches`.
  defp contains_always_match_condition?(else_block) do
    Enum.any?(else_block, fn {:->, _meta, [[left_clause], _right_clause]} ->
      case left_clause do
        {var, _meta, args} when is_atom(var) and not is_list(args) -> true
        _ -> false
      end
    end)
  end
end
