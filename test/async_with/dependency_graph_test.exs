defmodule AsyncWith.DependencyGraphTest do
  use ExUnit.Case, async: true

  alias AsyncWith.Clause
  alias AsyncWith.DependencyGraph
  alias AsyncWith.DependencyGraph.Vertex

  doctest DependencyGraph

  test "new/1 returns a graph expressing dependencies between clauses" do
    clauses = [
      create_clause("A", defined_vars: [:a, :h]),
      create_clause("B", defined_vars: [:b]),
      create_clause("C", defined_vars: [:c, :m], used_vars: [:a, :l]),
      create_clause("D", defined_vars: [:d], used_vars: [:a, :b]),
      create_clause("E", defined_vars: [:e], used_vars: [:c, :_k]),
      create_clause("F", defined_vars: [:f], used_vars: [:c]),
      create_clause("G", defined_vars: [:g], used_vars: [:d, :n, :o])
    ]

    dependency_graph = DependencyGraph.new(clauses)

    # The dependency graph should be:
    #
    #            A   B
    #          ↙ ↘ ↙
    #         C   D
    #        ↙ ↘   ↘
    #       E   F   G
    #

    vertices = DependencyGraph.vertices(dependency_graph)
    assert get_vertex_ids(vertices) == ["A", "B", "C", "D", "E", "F", "G"]

    vertex_a = Enum.at(vertices, 0)
    vertex_b = Enum.at(vertices, 1)
    vertex_c = Enum.at(vertices, 2)
    vertex_d = Enum.at(vertices, 3)
    vertex_e = Enum.at(vertices, 4)
    vertex_f = Enum.at(vertices, 5)
    vertex_g = Enum.at(vertices, 6)

    assert DependencyGraph.in_neighbours(dependency_graph, vertex_a) == []
    out_neighbours_of_a = DependencyGraph.out_neighbours(dependency_graph, vertex_a)
    assert get_vertex_ids(out_neighbours_of_a) == ["C", "D"]

    assert DependencyGraph.in_neighbours(dependency_graph, vertex_b) == []
    out_neighbours_of_b = DependencyGraph.out_neighbours(dependency_graph, vertex_b)
    assert get_vertex_ids(out_neighbours_of_b) == ["D"]

    in_neighbours_of_c = DependencyGraph.in_neighbours(dependency_graph, vertex_c)
    assert get_vertex_ids(in_neighbours_of_c) == ["A"]
    out_neighbours_of_c = DependencyGraph.out_neighbours(dependency_graph, vertex_c)
    assert get_vertex_ids(out_neighbours_of_c) == ["E", "F"]

    in_neighbours_of_d = DependencyGraph.in_neighbours(dependency_graph, vertex_d)
    assert get_vertex_ids(in_neighbours_of_d) == ["A", "B"]
    out_neighbours_of_d = DependencyGraph.out_neighbours(dependency_graph, vertex_d)
    assert get_vertex_ids(out_neighbours_of_d) == ["G"]

    in_neighbours_of_e = DependencyGraph.in_neighbours(dependency_graph, vertex_e)
    assert get_vertex_ids(in_neighbours_of_e) == ["C"]
    assert DependencyGraph.out_neighbours(dependency_graph, vertex_e) == []

    in_neighbours_of_f = DependencyGraph.in_neighbours(dependency_graph, vertex_f)
    assert get_vertex_ids(in_neighbours_of_f) == ["C"]
    assert DependencyGraph.out_neighbours(dependency_graph, vertex_f) == []

    in_neighbours_of_g = DependencyGraph.in_neighbours(dependency_graph, vertex_g)
    assert get_vertex_ids(in_neighbours_of_g) == ["D"]
    assert DependencyGraph.out_neighbours(dependency_graph, vertex_g) == []
  end

  test "vertices/1 returns an empty list when the dependency graph has no vertices" do
    dependency_graph = DependencyGraph.new([])

    assert DependencyGraph.vertices(dependency_graph) == []
  end

  test "root_vertices/1 returns an empty list when the dependency graph has no vertices" do
    dependency_graph = DependencyGraph.new([])

    assert DependencyGraph.root_vertices(dependency_graph) == []
  end

  test "add_edge/3 raises an exception if the edge would create a cycle in the dependency graph" do
    vertex_a = %Vertex{clauses: ["A"]}
    vertex_b = %Vertex{clauses: ["B"]}
    vertex_c = %Vertex{clauses: ["C"]}

    dependency_graph =
      []
      |> DependencyGraph.new()
      |> DependencyGraph.add_path(vertex_a, vertex_b)
      |> DependencyGraph.add_path(vertex_b, vertex_c)

    assert_raise(RuntimeError, "There are cycles in the dependency graph", fn ->
      DependencyGraph.add_edge(dependency_graph, vertex_c, vertex_a)
    end)
  end

  test "merge_vertices/2 returns the same dependency graph if no vertices are provided" do
    vertex_a = %Vertex{clauses: ["A"]}
    vertex_b = %Vertex{clauses: ["B"]}
    vertex_c = %Vertex{clauses: ["C"]}
    vertex_d = %Vertex{clauses: ["D"]}
    vertex_e = %Vertex{clauses: ["E"]}
    vertex_f = %Vertex{clauses: ["F"]}
    vertex_g = %Vertex{clauses: ["G"]}

    dependency_graph =
      []
      |> DependencyGraph.new()
      |> DependencyGraph.add_path(vertex_a, vertex_c)
      |> DependencyGraph.add_path(vertex_a, vertex_d)
      |> DependencyGraph.add_path(vertex_b, vertex_d)
      |> DependencyGraph.add_path(vertex_c, vertex_e)
      |> DependencyGraph.add_path(vertex_c, vertex_f)
      |> DependencyGraph.add_path(vertex_d, vertex_g)
      |> DependencyGraph.merge_vertices([])

    assert DependencyGraph.vertices(dependency_graph) == [
      %Vertex{clauses: ["A"]},
      %Vertex{clauses: ["B"]},
      %Vertex{clauses: ["C"]},
      %Vertex{clauses: ["D"]},
      %Vertex{clauses: ["E"]},
      %Vertex{clauses: ["F"]},
      %Vertex{clauses: ["G"]}
    ]

    assert DependencyGraph.out_neighbours(dependency_graph, vertex_a) == [
      %Vertex{clauses: ["C"]},
      %Vertex{clauses: ["D"]}
    ]

    assert DependencyGraph.in_neighbours(dependency_graph, vertex_e) == [%Vertex{clauses: ["C"]}]
  end

  test "merge_vertices/2 returns the same dependency graph if only one vertex is provided" do
    vertex_a = %Vertex{clauses: ["A"]}
    vertex_b = %Vertex{clauses: ["B"]}
    vertex_c = %Vertex{clauses: ["C"]}
    vertex_d = %Vertex{clauses: ["D"]}
    vertex_e = %Vertex{clauses: ["E"]}
    vertex_f = %Vertex{clauses: ["F"]}
    vertex_g = %Vertex{clauses: ["G"]}

    dependency_graph =
      []
      |> DependencyGraph.new()
      |> DependencyGraph.add_path(vertex_a, vertex_c)
      |> DependencyGraph.add_path(vertex_a, vertex_d)
      |> DependencyGraph.add_path(vertex_b, vertex_d)
      |> DependencyGraph.add_path(vertex_c, vertex_e)
      |> DependencyGraph.add_path(vertex_c, vertex_f)
      |> DependencyGraph.add_path(vertex_d, vertex_g)
      |> DependencyGraph.merge_vertices([vertex_c])

    assert DependencyGraph.vertices(dependency_graph) == [
      %Vertex{clauses: ["A"]},
      %Vertex{clauses: ["B"]},
      %Vertex{clauses: ["C"]},
      %Vertex{clauses: ["D"]},
      %Vertex{clauses: ["E"]},
      %Vertex{clauses: ["F"]},
      %Vertex{clauses: ["G"]}
    ]

    assert DependencyGraph.out_neighbours(dependency_graph, vertex_a) == [
      %Vertex{clauses: ["C"]},
      %Vertex{clauses: ["D"]}
    ]

    assert DependencyGraph.in_neighbours(dependency_graph, vertex_e) == [%Vertex{clauses: ["C"]}]
  end

  defp get_vertex_ids(vertices) do
    Enum.map(vertices, &get_vertex_id/1)
  end

  defp get_vertex_id(%Vertex{clauses: clauses}) do
    clauses
    |> Enum.map(fn %Clause{ast: vertex_id} -> vertex_id end)
    |> Enum.join("-")
  end

  # Returns a clause with the `used_vars` and `defined_vars` attributes specified in `opts` and
  # a `vertex_id` stored in the `ast` attribute. The `vertex_id` is quite useful to identify
  # the vertices in the test cases.
  defp create_clause(vertex_id, opts) do
    %Clause{
      ast: vertex_id,
      operator: :<-,
      left: nil,
      right: nil,
      used_vars: opts |> Keyword.get(:used_vars, []) |> MapSet.new(),
      defined_vars: opts |> Keyword.get(:defined_vars, []) |> MapSet.new(),
      guard_vars: MapSet.new()
    }
  end
end
