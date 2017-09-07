defmodule AsyncWith.Macro.Vertex do
  @moduledoc """
  Conveniences to represent vertices in the Abstract Syntax Tree.
  """

  alias AsyncWith.DependencyGraph
  alias AsyncWith.DependencyGraph.Vertex

  @doc """
  Generates an AST node representing the `vertex`.
  """
  @spec to_ast(DependencyGraph.t, Vertex.t) :: Macro.t
  def to_ast(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    quote do
      functions = unquote(get_functions(vertex))
      batch = Batch.async(functions)
      timeout = @async_with_timeout

      with {:ok, results} <- Batch.yield(batch, timeout) || {:exit, :timeout},
           unquote_splicing(get_with_clauses(vertex)) do
        unquote(AsyncWith.Macro.OutNeighbours.to_ast(dependency_graph, vertex))
      else
        error ->
          Batch.shutdown(batch)

          case error do
            {:exit, reason} -> {:error, {:exit, reason}}
            {:error, error} -> error
          end
      end
    end
  end

  defp get_functions(%Vertex{clauses: clauses}) do
    Enum.map(clauses, fn clause ->
      case clause.operator do
        :<- ->
          quote do
            fn ->
              with unquote(clause.left) <- unquote(clause.right) do
                {:ok, unquote(AsyncWith.Macro.vars(clause.defined_vars, nil))}
              else
                error -> {:error, error}
              end
            end
          end
        := ->
          quote do
            fn ->
              try do
                unquote(clause.left) = unquote(clause.right)
                {:ok, unquote(AsyncWith.Macro.vars(clause.defined_vars, nil))}
              rescue
                error in MatchError -> {:error, error}
              end
            end
          end
      end
    end)
  end

  defp get_with_clauses(%Vertex{clauses: clauses}) do
    Enum.flat_map(clauses, fn clause ->
      quote do
        [
          {result, results} = List.pop_at(results, 0),
          {:ok, unquote(AsyncWith.Macro.vars(clause.defined_vars, nil))} <- result
        ]
      end
    end)
  end

  @doc """
  Aggregates the list of variables of the same `type` (`:defined_vars`, `:used_vars` or
  `:guard_vars`) that appear in the clauses of the `vertex` and its out-neighbours.
  """
  @spec get_vars(DependencyGraph.t, Vertex.t, :defined_vars | :used_vars | :guard_vars) :: MapSet.t
  def get_vars(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex, type) do
    case DependencyGraph.out_neighbours(dependency_graph, vertex) do
      [] -> do_get_vars(vertex, type)
      out_neighbours ->
        Enum.reduce(out_neighbours, do_get_vars(vertex, type), fn out_neighbour, vars ->
          MapSet.union(get_vars(dependency_graph, out_neighbour, type), vars)
        end)
    end
  end

  defp do_get_vars(%Vertex{clauses: clauses}, type) do
    Enum.reduce(clauses, MapSet.new(), fn clause, vars ->
      MapSet.union(Map.get(clause, type), vars)
    end)
  end
end
