defmodule AsyncWith.DOT do
  @moduledoc """
  Utilities for rendering `AsyncWith.DependencyGraph` using DOT language.
  """

  alias AsyncWith.DependencyGraph
  alias AsyncWith.DependencyGraph.Vertex

  @doc """
  Exports the graph in DOT (`filename`.dot) and PNG (`filename`.png) formats.
  """
  @spec export(DependencyGraph.t, String.t) :: no_return
  def export(%DependencyGraph{} = graph, filename \\ "async_with") do
    File.write!("#{filename}.dot", to_dot(graph))
    System.cmd("dot", ["-T", "png", "-o", "#{filename}.png", "#{filename}.dot"])
  end

  @doc """
  Returns a `String` that represents the graph in the DOT language.
  """
  @spec to_dot(DependencyGraph.t) :: String.t
  def to_dot(%DependencyGraph{} = graph) do
    """
    digraph async_with {
    #{do_to_dot(graph)}
    }
    """
  end

  defp do_to_dot(graph) do
    graph
    |> DependencyGraph.vertices()
    |> Enum.flat_map(fn vertex ->
      out_neighbours = DependencyGraph.out_neighbours(graph, vertex)
      [vertex_to_dot(vertex) | Enum.map(out_neighbours, &edge_to_dot(vertex, &1))]
    end)
    |> Enum.join("\n")
  end

  defp edge_to_dot(%Vertex{} = vertex_1, %Vertex{} = vertex_2) do
    vertex_id(vertex_1) <> " -> " <> vertex_id(vertex_2) <> ";"
  end

  defp vertex_to_dot(%Vertex{} = vertex) do
    ~s(#{vertex_id(vertex)} [label="#{vertex_label(vertex)}"];)
  end

  defp vertex_label(%Vertex{clauses: clauses}) do
    clauses
    |> Enum.map(&Macro.to_string(&1.ast))
    |> Enum.join("\n")
    |> escape_double_quotes()
  end

  defp vertex_id(%Vertex{clauses: clauses}) do
    clauses
    |> Enum.flat_map(&Enum.map(&1.defined_vars, fn {var, version} -> "#{var}_#{version}" end))
    |> Enum.join("__")
  end

  defp escape_double_quotes(string), do: String.replace(string, ~s("), ~s(\\"))
end
