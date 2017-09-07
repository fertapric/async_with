defmodule AsyncWith.Macro.OutNeighbours do
  @moduledoc """
  Conveniences to represent the out-neighbours of a vertex in the Abstract Syntax Tree.
  """

  alias AsyncWith.DependencyGraph
  alias AsyncWith.DependencyGraph.Vertex

  @doc """
  Generates an AST node representing the out-neighbours of the `vertex`.
  """
  @spec to_ast(DependencyGraph.t, Vertex.t) :: Macro.t
  def to_ast(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    vars = AsyncWith.Macro.Vertex.get_vars(dependency_graph, vertex, :defined_vars)
    do_block = quote(do: {:ok, unquote(AsyncWith.Macro.vars(vars, nil))})

    case DependencyGraph.out_neighbours(dependency_graph, vertex) do
      [] -> do_block
      _ ->
        longest_path = DependencyGraph.get_longest_path(dependency_graph, vertex)

        quote do
          functions = unquote(get_functions(dependency_graph, vertex))
          batch = Batch.async(functions)
          timeout = unquote(length(longest_path)) * @async_with_timeout

          with {:ok, results} <- Batch.yield(batch, timeout) || {:exit, :timeout},
               unquote_splicing(get_with_clauses(dependency_graph, vertex)) do
            unquote(do_block)
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
  end

  defp get_functions(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    dependency_graph
    |> DependencyGraph.out_neighbours(vertex)
    |> Enum.map(fn out_neighbour ->
      quote do
        fn -> unquote(AsyncWith.Macro.Vertex.to_ast(dependency_graph, out_neighbour)) end
      end
    end)
  end

  defp get_with_clauses(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    dependency_graph
    |> DependencyGraph.out_neighbours(vertex)
    |> Enum.flat_map(fn out_neighbour ->
      vars = AsyncWith.Macro.Vertex.get_vars(dependency_graph, out_neighbour, :defined_vars)

      quote do
        [
          {result, results} = List.pop_at(results, 0),
          {:ok, unquote(AsyncWith.Macro.vars(vars, nil))} <- result
        ]
      end
    end)
  end
end
