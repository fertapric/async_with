defmodule AsyncWith.Clause do
  @moduledoc """
  Defines a clause.

  There are three types of clauses:

    * Clauses with arrow (or send operator) - `a <- 1`
    * Clauses with match operator - `a = 1`
    * Bare expressions - `my_function(a)` - However, bare expressions are converted to
      clauses with match operator `_ = my_function(a)` to ensure both left and right sides
      are always present. This homogenization processs simplifies the building of the
      `AsyncWith.DependencyGraph` and the generation of the final Abstract Syntax Tree.

  Each clause is mapped into the following Elixir struct:

    * `operator` - Either match `:=` or send `:<-` operators.
    * `left` - The left-hand side of the clause.
    * `right` - The right-hand side of the clause.
    * `defined_vars` - The list of variables binded/defined in the clause.
    * `used_vars` - The list of variables used in the clause (including pin matching).
    * `guard_vars` - The list of variables used in the guard clause.

  As example, the following clause `{:ok, {^a, b}} when is_binary(b) <- echo(c, d)` would
  be mapped to an `AsyncWith.Clause` with the following attributes:

    * `operator` would be `:<-`.
    * `left` would be the AST representation of `{:ok, {^a, b}}`.
    * `right` would be the AST representation of `echo(c, d)`.
    * `defined_vars` would be `[:b]` (`MapSet`).
    * `used_vars` would be `[:a, :c, :d]` (`MapSet`).
    * `guard_vars` would be `[:b]` (`MapSet`).

  """

  alias __MODULE__

  @enforce_keys [
    :operator,
    :left,
    :right,
    :defined_vars,
    :used_vars,
    :guard_vars
  ]

  defstruct [
    :operator,
    :left,
    :right,
    :defined_vars,
    :used_vars,
    :guard_vars
  ]

  @type t :: %Clause{
    operator: :<- | :=,
    left: Macro.t,
    right: Macro.t,
    defined_vars: MapSet.t,
    used_vars: MapSet.t,
    guard_vars: MapSet.t
  }

  @doc """
  Aggregates the list of variables of the same `type`.
  """
  @spec get_vars(t | [t], :defined_vars | :used_vars | :guard_vars) :: MapSet.t
  def get_vars(clause_or_clauses, type)
  def get_vars(%Clause{} = clause, type), do: Map.get(clause, type)
  def get_vars(clauses, type) do
    Enum.reduce(clauses, MapSet.new(), fn clause, vars ->
      MapSet.union(vars, get_vars(clause, type))
    end)
  end

  @doc """
  Maps the Abstract Syntax Tree expression into an `AsyncWith.Clause` struct.

  ## Examples

      iex> ast = quote(do: {^ok, a} <- echo(b, c))
      iex> Clause.one_from_ast(ast)
      %Clause{
        operator: :<-,
        left: {{:^, [], [{:ok, [], __MODULE__}]}, {:a, [], __MODULE__}},
        right: {:echo, [], [{:b, [], __MODULE__}, {:c, [], __MODULE__}]},
        used_vars: MapSet.new([:ok, :b, :c]),
        defined_vars: MapSet.new([:a]),
        guard_vars: MapSet.new()
      }

  """
  @spec one_from_ast(Macro.t) :: t
  def one_from_ast(ast)
  def one_from_ast({:=, _meta, [left, right]}), do: do_one_from_ast(:=, left, right)
  def one_from_ast({:<-, _meta, [left, right]}), do: do_one_from_ast(:<-, left, right)
  # Bare expressions are converted to clauses following the pattern `_ = <bare expression>`
  def one_from_ast(ast), do: do_one_from_ast(:=, Macro.var(:_, nil), ast)

  defp do_one_from_ast(operator, left, right) do
    guard_vars = AsyncWith.Macro.get_guard_vars(left)
    pinned_vars = AsyncWith.Macro.get_pinned_vars(left)
    defined_vars = AsyncWith.Macro.get_vars(left) -- pinned_vars
    used_vars = AsyncWith.Macro.get_vars(right) ++ pinned_vars

    %Clause{
      operator: operator,
      left: left,
      right: right,
      used_vars: MapSet.new(used_vars),
      defined_vars: MapSet.new(defined_vars),
      guard_vars: MapSet.new(guard_vars)
    }
  end

  @doc """
  Maps multiple and dependent Abstract Syntax Tree expressions into `AsyncWith.Clause` structs.

  The main goal of this function is to process the clauses of the `async with` expression before
  building the `AsyncWith.DependencyGraph`.

  This function is order dependent:

    * Variables that are used but not defined in previous clauses are considered external.
      External variables are removed from the list of `used_vars`, as they shouldn't be
      considered when building the dependency graph.
    * Variables that are rebinded in next clauses are renamed to avoid collisions when building
      the dependency graph.
    * Ignored variables are renamed to avoid compiler warnings. See
      `AsyncWith.Macro.DependencyGraph.to_ast/2` for more information.

  Variables are renamed using the following pattern:

      async_with_<var name>_<timestamp in nanoseconds>

  ## Examples

  As example, given the following `async with` expression:

      async with {^ok, a} when is_integer(a) <- echo(b, c, a),
                 {_ok, b} <- echo(m) ~> {d, a},
                 {:ok, a} <- echo(a),
                 {:ok, b, m} <- echo(b) do
      end

  the list of clauses returned by `many_from_ast/1` would be as if the `async with`
  expression were:

      async with {^ok, async_with_a_xxx} when is_integer(async_with_a_xxx) <- echo(b, c, a),
                 {async_with__ok_xxx, async_with_b_xxx} <- echo(m) ~> {d, async_with_a_xxx},
                 {:ok, a} <- echo(async_with_a_xxx),
                 {:ok, b, m} <- echo(async_with_b_xxx) do
      end

  """
  @spec many_from_ast(Macro.t) :: [t]
  def many_from_ast(ast) do
    ast
    |> Enum.map(&one_from_ast/1)
    |> remove_external_vars()
    |> rename_rebinded_vars()
  end

  defp remove_external_vars(clauses) do
    {clauses, _defined_vars} = Enum.map_reduce(clauses, MapSet.new(), fn clause, defined_vars ->
      clause = %{clause | used_vars: MapSet.intersection(clause.used_vars, defined_vars)}
      defined_vars = MapSet.union(defined_vars, clause.defined_vars)

      {clause, defined_vars}
    end)

    clauses
  end

  defp rename_rebinded_vars(clauses) do
    {clauses, var_renamings} = Enum.map_reduce(clauses, %{}, fn clause, var_renamings ->
      clause = rename_used_vars(clause, var_renamings)
      var_renamings = update_var_renamings(var_renamings, clause.defined_vars)

      {rename_defined_vars(clause, var_renamings), var_renamings}
    end)

    # Rename exposed variables back to their original names so they can be used in
    # the `:do` block
    var_renamings_of_exposed_vars =
      var_renamings
      |> remove_ignored_vars_from_var_renamings()
      |> reverse_var_renamings()

    Enum.map(clauses, fn clause ->
      clause
      |> rename_used_vars(var_renamings_of_exposed_vars)
      |> rename_defined_vars(var_renamings_of_exposed_vars)
    end)
  end

  defp rename_used_vars(clause, var_renamings) do
    %Clause{
      operator: clause.operator,
      left: AsyncWith.Macro.rename_pinned_vars(clause.left, var_renamings),
      right: AsyncWith.Macro.rename_vars(clause.right, var_renamings),
      defined_vars: clause.defined_vars,
      used_vars: rename_vars(clause.used_vars, var_renamings),
      guard_vars: clause.guard_vars
    }
  end

  defp rename_defined_vars(clause, var_renamings) do
    %Clause{
      operator: clause.operator,
      left: AsyncWith.Macro.rename_vars(clause.left, var_renamings),
      right: clause.right,
      defined_vars: rename_vars(clause.defined_vars, var_renamings),
      used_vars: clause.used_vars,
      guard_vars: rename_vars(clause.guard_vars, var_renamings)
    }
  end

  defp rename_vars(vars, var_renamings) do
    vars
    |> Enum.map(&Map.get(var_renamings, &1, &1))
    |> MapSet.new()
  end

  defp rename_var(var) do
    :"async_with_#{var}_#{System.monotonic_time(:nanoseconds)}"
  end

  defp reverse_var_renamings(var_renamings) do
    for {k, v} <- var_renamings, do: {v, k}, into: %{}
  end

  defp remove_ignored_vars_from_var_renamings(var_renamings) do
    for {k, v} <- var_renamings, !String.starts_with?("#{k}", "_"), do: {k, v}, into: %{}
  end

  defp update_var_renamings(var_renamings, vars) do
    Enum.reduce(vars, var_renamings, fn var, var_renamings ->
      Map.put(var_renamings, var, rename_var(var))
    end)
  end
end
