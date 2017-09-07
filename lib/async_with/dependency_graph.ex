defmodule AsyncWith.DependencyGraph do
  @moduledoc """
  Defines a directed acyclic graph expressing dependencies between clauses.

  A directed acyclic graph is a finite directed graph with no directed cycles.

  A directed graph (or just "digraph") is a pair `(V, E)` of a finite set `V` of vertices and
  a finite set `E` of directed edges (or just "edges"). The set of edges `E` is a subset of
  `V × V` (the Cartesian product of `V` with itself).

  An edge `E = (V, W)` is said to emanate from vertex `V` and to be incident on vertex `W`.

  The out-degree of a vertex is the number of edges emanating from that vertex.

  The in-degree of a vertex is the number of edges incident on that vertex.

  If an edge is emanating from `V` and incident on `W`, then `W` is said to be an
  out-neighbor of `V`, and `V` is said to be an in-neighbor of `W`.

  **Dependencies between clauses are based on the variables they define and the
  variables they use**, expressed via the attributes `defined_vars` and `used_vars`
  (see `AsyncWith.Clause` for more information).

  Here is an example:

      async with a <- 1,
                 b <- a + 1,
                 c <- b + 1,
                 d <- b + 2 do
        a + b + c + d
      end

  In which:

    * the clause `a <- 1` defines the variable `a`
    * the clause `b <- a + 1` defines the variable `b` and uses the variable `a`
    * the clause `c <- b + 1` defines the variable `c` and uses the variable `b`
    * the clause `d <- b + 2` defines the variable `d` and uses the variable `b`

  The dependency graph would be then:

                                                   +--------------+
                                             +---->|  d <- b + 2  |
      +----------+      +--------------+     |     +--------------+
      |  a <- 1  |----->|  b <- a + 1  |-----+
      +----------+      +--------------+     |     +--------------+
                                             +---->|  c <- b + 1  |
                                                   +--------------+

  _In the diagram above, a box represents a vertex (`AsyncWith.Vertex`) and an arrow
  represents an edge._
  """

  alias __MODULE__
  alias AsyncWith.Clause

  @enforce_keys [:digraph]

  defstruct [:digraph]

  @type t :: %DependencyGraph{
    digraph: tuple
  }

  defmodule Vertex do
    @moduledoc """
    Defines a vertex of the dependency graph.

    Every `AsyncWith.DependencyGraph.Vertex` contains a list of `clauses` that must be
    executed before executing the clauses of its out-neighbours.

    See `AsyncWith.DependencyGraph` for more information.
    """

    alias __MODULE__
    alias AsyncWith.Clause

    @enforce_keys [:clauses]

    defstruct [:clauses]

    @type t :: %Vertex {
      clauses: [Clause.t]
    }
  end

  @doc """
  Returns a directed acyclic graph expressing dependencies between the given `clauses`.
  """
  @spec new([Clause.t]) :: t
  def new(clauses) do
    dependency_graph = %DependencyGraph{digraph: :digraph.new([:acyclic])}

    Enum.each(clauses, fn clause ->
      vertex = %Vertex{clauses: [clause]}
      parent_clauses = Enum.reject(clauses, &MapSet.disjoint?(&1.defined_vars, clause.used_vars))

      add_vertex(dependency_graph, vertex)
      Enum.each(parent_clauses, &add_path(dependency_graph, %Vertex{clauses: [&1]}, vertex))
    end)

    dependency_graph
  end

  @doc """
  Returns a list of all the vertices of the dependency `graph`.

  ## Example

  In this dependency graph the vertices would be `A`, `B`, `C`, `D`, `E`, `F`, `G`:

           A   B
          ↙ ↘ ↙
         C   D
        ↙ ↘   ↘
       E   F   G

  In code:

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> vertex_d = %Vertex{clauses: ["D"]}
      iex> vertex_e = %Vertex{clauses: ["E"]}
      iex> vertex_f = %Vertex{clauses: ["F"]}
      iex> vertex_g = %Vertex{clauses: ["G"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_c)
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_e)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_f)
      ...>   |> DependencyGraph.add_path(vertex_d, vertex_g)
      iex> DependencyGraph.vertices(dependency_graph)
      [
        %Vertex{clauses: ["A"]},
        %Vertex{clauses: ["B"]},
        %Vertex{clauses: ["C"]},
        %Vertex{clauses: ["D"]},
        %Vertex{clauses: ["E"]},
        %Vertex{clauses: ["F"]},
        %Vertex{clauses: ["G"]}
      ]

  """
  @spec vertices(t) :: [Vertex.t]
  def vertices(%DependencyGraph{} = dependency_graph) do
    dependency_graph.digraph
    |> :digraph.vertices()
    |> Enum.sort()
  end

  @doc """
  Returns a list of all vertices of the dependency `graph` without in-neighbours.

  ## Example

  In this dependency graph the root vertices would be `A` and `B`:

           A   B
          ↙ ↘ ↙
         C   D
        ↙ ↘   ↘
       E   F   G

  In code:

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> vertex_d = %Vertex{clauses: ["D"]}
      iex> vertex_e = %Vertex{clauses: ["E"]}
      iex> vertex_f = %Vertex{clauses: ["F"]}
      iex> vertex_g = %Vertex{clauses: ["G"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_c)
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_e)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_f)
      ...>   |> DependencyGraph.add_path(vertex_d, vertex_g)
      iex> DependencyGraph.root_vertices(dependency_graph)
      [
        %Vertex{clauses: ["A"]},
        %Vertex{clauses: ["B"]}
      ]

  """
  @spec root_vertices(t) :: [Vertex.t]
  def root_vertices(%DependencyGraph{} = dependency_graph) do
    dependency_graph
    |> vertices()
    |> Enum.filter(&in_degree(dependency_graph, &1) == 0)
  end

  @doc """
  Adds (or modifies) a list of `vertices` to the dependency `graph`.

  ## Example

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_vertices([vertex_a, vertex_b])
      iex> DependencyGraph.vertices(dependency_graph)
      [%Vertex{clauses: ["A"]}, %Vertex{clauses: ["B"]}]

  """
  @spec add_vertices(t, [Vertex.t]) :: t
  def add_vertices(%DependencyGraph{} = dependency_graph, vertices) do
    Enum.reduce(vertices, dependency_graph, fn vertex, dependency_graph ->
      add_vertex(dependency_graph, vertex)
    end)
  end

  @doc """
  Adds (or modifies) a `vertex` to the dependency `graph`.

  ## Example

      iex> vertex = %Vertex{clauses: ["A"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_vertex(vertex)
      iex> DependencyGraph.vertices(dependency_graph)
      [%Vertex{clauses: ["A"]}]

  """
  @spec add_vertex(t, Vertex.t) :: t
  def add_vertex(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    :digraph.add_vertex(dependency_graph.digraph, vertex)
    dependency_graph
  end

  @doc """
  Deletes a list of `vertices` from the dependency `graph`.

  ## Example

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_vertices([vertex_a, vertex_b, vertex_c])
      ...>   |> DependencyGraph.del_vertices([vertex_c, vertex_b])
      iex> DependencyGraph.vertices(dependency_graph)
      [%Vertex{clauses: ["A"]}]

  """
  @spec del_vertices(t, [Vertex.t]) :: t
  def del_vertices(%DependencyGraph{} = dependency_graph, vertices) do
    :digraph.del_vertices(dependency_graph.digraph, vertices)
    dependency_graph
  end

  @doc """
  Deletes a `vertex` from the dependency `graph`.

  ## Example

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_vertices([vertex_a, vertex_b, vertex_c])
      ...>   |> DependencyGraph.del_vertex(vertex_b)
      iex> DependencyGraph.vertices(dependency_graph)
      [%Vertex{clauses: ["A"]}, %Vertex{clauses: ["C"]}]

  """
  @spec del_vertex(t, Vertex.t) :: t
  def del_vertex(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    :digraph.del_vertex(dependency_graph.digraph, vertex)
    dependency_graph
  end

  @doc """
  Adds (or modifies) an edge from `vertex_1` to `vertex_2`.

  ## Example

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_vertices([vertex_a, vertex_b])
      ...>   |> DependencyGraph.add_edge(vertex_b, vertex_a)
      iex> DependencyGraph.out_degree(dependency_graph, vertex_b)
      1

  """
  @spec add_edge(t, Vertex.t, Vertex.t) :: t
  def add_edge(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex_1, %Vertex{} = vertex_2) do
    [:"$e" | _] = :digraph.add_edge(dependency_graph.digraph, vertex_1, vertex_2)
    dependency_graph
  rescue
    _ -> raise("There are cycles in the dependency graph")
  end

  @doc """
  Adds (or modifies) vertices and edges to create a path from `vertex_1` to `vertex_2`.

  ## Example

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_a)
      iex> DependencyGraph.out_degree(dependency_graph, vertex_b)
      1
      iex> DependencyGraph.vertices(dependency_graph)
      [%Vertex{clauses: ["A"]}, %Vertex{clauses: ["B"]}]

  """
  @spec add_path(t, Vertex.t, Vertex.t) :: t
  def add_path(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex_1, %Vertex{} = vertex_2) do
    add_vertices(dependency_graph, [vertex_1, vertex_2])
    add_edge(dependency_graph, vertex_1, vertex_2)
  end

  @doc """
  Returns the vertices of path of the maximum length in the `dependency_graph`, starting
  from the given `vertex`.

  ## Example

  In this dependency graph the the longest path starting from the vertex `A` would be
  `A`, `C` and `E`:

           A   B
          ↙ ↘ ↙
         C   D
        ↙
       E

  In code:

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> vertex_d = %Vertex{clauses: ["D"]}
      iex> vertex_e = %Vertex{clauses: ["E"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_c)
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_e)
      iex> DependencyGraph.get_longest_path(dependency_graph, vertex_a)
      [
        %Vertex{clauses: ["A"]},
        %Vertex{clauses: ["C"]},
        %Vertex{clauses: ["E"]},
      ]

  """
  @spec get_longest_path(t, Vertex.t) :: [Vertex.t]
  def get_longest_path(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    case DependencyGraph.out_neighbours(dependency_graph, vertex) do
      [] -> [vertex]
      out_neighbours ->
        longest_path =
          out_neighbours
          |> Enum.map(&get_longest_path(dependency_graph, &1))
          |> Enum.max_by(&length/1)

        [vertex | longest_path]
    end
  end

  @doc """
  Returns the list of all in-neighbours of the `vertex` in the dependency `graph`.

  If an edge is emanating from `V` and incident on `W`, then `V` is said to be an in-neighbor
  of `W`.

  ## Example

  In this dependency graph the in-neighbours of the vertex `D` would be `A` and `B`:

           A   B
          ↙ ↘ ↙
         C   D
        ↙ ↘   ↘
       E   F   G

  In code:

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> vertex_d = %Vertex{clauses: ["D"]}
      iex> vertex_e = %Vertex{clauses: ["E"]}
      iex> vertex_f = %Vertex{clauses: ["F"]}
      iex> vertex_g = %Vertex{clauses: ["G"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_c)
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_e)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_f)
      ...>   |> DependencyGraph.add_path(vertex_d, vertex_g)
      iex> DependencyGraph.in_neighbours(dependency_graph, vertex_d)
      [
        %Vertex{clauses: ["A"]},
        %Vertex{clauses: ["B"]}
      ]
      iex> DependencyGraph.in_neighbours(dependency_graph, vertex_a)
      []

  """
  @spec in_neighbours(t, Vertex.t) :: [Vertex.t]
  def in_neighbours(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    dependency_graph.digraph |> :digraph.in_neighbours(vertex) |> Enum.sort()
  end

  @doc """
  Returns the in-degree of the `vertex` of the dependency `graph`.

  The in-degree of a vertex is the number of edges incident on that vertex.

  ## Example

  In this dependency graph the in-degree of `D` would be `2`:

           A   B
          ↙ ↘ ↙
         C   D
        ↙ ↘   ↘
       E   F   G

  In code:

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> vertex_d = %Vertex{clauses: ["D"]}
      iex> vertex_e = %Vertex{clauses: ["E"]}
      iex> vertex_f = %Vertex{clauses: ["F"]}
      iex> vertex_g = %Vertex{clauses: ["G"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_c)
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_e)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_f)
      ...>   |> DependencyGraph.add_path(vertex_d, vertex_g)
      iex> DependencyGraph.in_degree(dependency_graph, vertex_d)
      2
      iex> DependencyGraph.in_degree(dependency_graph, vertex_a)
      0

  """
  @spec in_degree(t, Vertex.t) :: non_neg_integer
  def in_degree(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    :digraph.in_degree(dependency_graph.digraph, vertex)
  end

  @doc """
  Returns the list of all out-neighbours of the `vertex` in the dependency `graph`.

  If an edge is emanating from `V` and incident on `W`, then `W` is said to be an
  out-neighbor of `V`.

  ## Example

  In this dependency graph the out-neighbours of the vertex `C` would be `E` and `F`:

           A   B
          ↙ ↘ ↙
         C   D
        ↙ ↘   ↘
       E   F   G

  In code:

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> vertex_d = %Vertex{clauses: ["D"]}
      iex> vertex_e = %Vertex{clauses: ["E"]}
      iex> vertex_f = %Vertex{clauses: ["F"]}
      iex> vertex_g = %Vertex{clauses: ["G"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_c)
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_e)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_f)
      ...>   |> DependencyGraph.add_path(vertex_d, vertex_g)
      iex> DependencyGraph.out_neighbours(dependency_graph, vertex_c)
      [
        %Vertex{clauses: ["E"]},
        %Vertex{clauses: ["F"]}
      ]
      iex> DependencyGraph.out_neighbours(dependency_graph, vertex_e)
      []

  """
  @spec out_neighbours(t, Vertex.t) :: [Vertex.t]
  def out_neighbours(%DependencyGraph{} = dependency_graph, %Vertex{} = vertex) do
    dependency_graph.digraph |> :digraph.out_neighbours(vertex) |> Enum.sort()
  end

  @doc """
  Returns the out-degree of the `vertex` of the dependency `graph`.

  The out-degree of a vertex is the number of edges emanating from that vertex.

  ## Example

  In this dependency graph the out-degree of `C` would be `2`:

           A   B
          ↙ ↘ ↙
         C   D
        ↙ ↘   ↘
       E   F   G

  In code:

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> vertex_d = %Vertex{clauses: ["D"]}
      iex> vertex_e = %Vertex{clauses: ["E"]}
      iex> vertex_f = %Vertex{clauses: ["F"]}
      iex> vertex_g = %Vertex{clauses: ["G"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_c)
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_e)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_f)
      ...>   |> DependencyGraph.add_path(vertex_d, vertex_g)
      iex> DependencyGraph.out_degree(dependency_graph, vertex_c)
      2
      iex> DependencyGraph.out_degree(dependency_graph, vertex_e)
      0

  """
  @spec out_degree(t, Vertex.t) :: non_neg_integer
  def out_degree(%DependencyGraph{} = dependency_graph, vertex) do
    :digraph.out_degree(dependency_graph.digraph, vertex)
  end

  @doc """
  Merges a list of `vertices` into a single vertex. The list of out-neighbours and in-neighbours
  of all the `vertices` is inherited by the new vertex.

  ## Example

  Using this dependency graph:

           A   B
          ↙ ↘ ↙
         C   D
        ↙ ↘   ↘
       E   F   G

  applying `merge_vertices(graph, [C, D])` the graph would be:

       A     B
        ↘   ↙
         C-D
        ↙ ↓ ↘
       E  F  G

  In code:

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> vertex_d = %Vertex{clauses: ["D"]}
      iex> vertex_e = %Vertex{clauses: ["E"]}
      iex> vertex_f = %Vertex{clauses: ["F"]}
      iex> vertex_g = %Vertex{clauses: ["G"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_c)
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_e)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_f)
      ...>   |> DependencyGraph.add_path(vertex_d, vertex_g)
      ...>   |> DependencyGraph.merge_vertices([vertex_c, vertex_d])
      iex> DependencyGraph.vertices(dependency_graph)
      [
        %Vertex{clauses: ["A"]},
        %Vertex{clauses: ["B"]},
        %Vertex{clauses: ["C", "D"]},
        %Vertex{clauses: ["E"]},
        %Vertex{clauses: ["F"]},
        %Vertex{clauses: ["G"]}
      ]
      iex> DependencyGraph.out_neighbours(dependency_graph, vertex_a)
      [%Vertex{clauses: ["C", "D"]}]
      iex> DependencyGraph.in_neighbours(dependency_graph, vertex_e)
      [%Vertex{clauses: ["C", "D"]}]

  """
  @spec merge_vertices(t, [Vertex.t]) :: t
  def merge_vertices(dependency_graph, vertices)
  def merge_vertices(%DependencyGraph{} = dependency_graph, []), do: dependency_graph
  def merge_vertices(%DependencyGraph{} = dependency_graph, [_vertex]), do: dependency_graph
  def merge_vertices(%DependencyGraph{} = dependency_graph, vertices) do
    vertex = %Vertex{clauses: Enum.flat_map(vertices, &(&1.clauses))}
    in_neighbours = vertices |> Enum.map(&in_neighbours(dependency_graph, &1)) |> Enum.concat()
    out_neighbours = vertices |> Enum.map(&out_neighbours(dependency_graph, &1)) |> Enum.concat()
    paths = Enum.map(in_neighbours, &{&1, vertex}) ++ Enum.map(out_neighbours, &{vertex, &1})

    del_vertices(dependency_graph, vertices)
    add_vertex(dependency_graph, vertex)

    paths
    |> Enum.uniq()
    |> Enum.reduce(dependency_graph, fn {vertex_1, vertex_2}, dependency_graph ->
      add_path(dependency_graph, vertex_1, vertex_2)
    end)
  end

  @doc """
  Merges all the vertices with common out-neighbours.

  This operation is useful to turn the dependency graph into an arborescence.

  See `to_arborescence/1` for more information.

  ## Example

  Using this dependency graph:

           A   B   C
          ↙   ↙ ↘ ↙
         D   E   F
        ↙ ↘ ↙
       G   H

  applying `merge_vertices_with_common_out_neighbours(graph)` the graph would be:

           A-B-C
           ↙  ↘
         D-E   F
         ↙ ↘
        G   H

  In code:

      iex> vertex_a = %Vertex{clauses: ["A"]}
      iex> vertex_b = %Vertex{clauses: ["B"]}
      iex> vertex_c = %Vertex{clauses: ["C"]}
      iex> vertex_d = %Vertex{clauses: ["D"]}
      iex> vertex_e = %Vertex{clauses: ["E"]}
      iex> vertex_f = %Vertex{clauses: ["F"]}
      iex> vertex_g = %Vertex{clauses: ["G"]}
      iex> vertex_h = %Vertex{clauses: ["H"]}
      iex> dependency_graph =
      ...>   DependencyGraph.new([])
      ...>   |> DependencyGraph.add_path(vertex_a, vertex_d)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_e)
      ...>   |> DependencyGraph.add_path(vertex_b, vertex_f)
      ...>   |> DependencyGraph.add_path(vertex_c, vertex_f)
      ...>   |> DependencyGraph.add_path(vertex_d, vertex_g)
      ...>   |> DependencyGraph.add_path(vertex_d, vertex_h)
      ...>   |> DependencyGraph.add_path(vertex_e, vertex_h)
      ...>   |> DependencyGraph.merge_vertices_with_common_out_neighbours()
      iex> DependencyGraph.vertices(dependency_graph)
      [
        %Vertex{clauses: ["A", "B", "C"]},
        %Vertex{clauses: ["D", "E"]},
        %Vertex{clauses: ["F"]},
        %Vertex{clauses: ["G"]},
        %Vertex{clauses: ["H"]}
      ]
      iex> DependencyGraph.in_neighbours(dependency_graph, %Vertex{clauses: ["D", "E"]})
      [%Vertex{clauses: ["A", "B", "C"]}]
      iex> DependencyGraph.in_neighbours(dependency_graph, vertex_h)
      [%Vertex{clauses: ["D", "E"]}]

  """
  @spec merge_vertices_with_common_out_neighbours(t) :: t
  def merge_vertices_with_common_out_neighbours(%DependencyGraph{} = dependency_graph) do
    vertices_with_more_than_one_in_neighbour =
      dependency_graph
      |> vertices()
      |> Enum.filter(fn vertex -> in_degree(dependency_graph, vertex) > 1 end)

    case vertices_with_more_than_one_in_neighbour do
      [] -> dependency_graph
      vertices ->
        vertices
        |> Enum.reduce(dependency_graph, fn vertex, dependency_graph ->
          merge_vertices(dependency_graph, in_neighbours(dependency_graph, vertex))
        end)
        |> merge_vertices_with_common_out_neighbours()
    end
  end
end
