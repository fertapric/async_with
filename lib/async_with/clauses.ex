defmodule AsyncWith.Clauses do
  @moduledoc false

  @type clause :: %{
     function: Macro.t,
     defined_vars: [atom],
     used_vars: [atom],
     guard_vars: [atom]
   }

  @doc """
  Aggregates the list of variables of the same `type`.
  """
  @spec get_vars([clause], :defined_vars | :used_vars | :guard_vars) :: [atom]
  def get_vars(clauses, type) do
    Enum.reduce(clauses, [], fn clause, vars ->
      Enum.uniq(vars ++ Map.fetch!(clause, type))
    end)
  end

  @doc """
  Maps multiple and dependent Abstract Syntax Tree expressions into structs.

  There are three types of clauses:

    * Clauses with arrow (or send operator) - `a <- 1`
    * Clauses with match operator - `a = 1`
    * Bare expressions - `my_function(a)` - However, bare expressions are converted to
      clauses with match operator `_ = my_function(a)` to ensure both left and right sides
      are always present.

  Each clause is mapped into the following Elixir struct:

    * `function` - Either match `:=` or send `:<-` operators.
    * `defined_vars` - The list of variables binded/defined in the clause.
    * `used_vars` - The list of variables used in the clause (including pin matching).
    * `guard_vars` - The list of variables used in the guard clause.

  As example, the following clause `{:ok, {^a, b}} when is_binary(b) <- echo(c, d)` would
  be mapped to an struct with the following attributes:

    * `function` would be something similar to
      `with {:ok, {^a, b}} when is_binary(b) <- echo(c, d), do: {:ok, [b: b]}`.
    * `defined_vars` would be `[:b]`.
    * `used_vars` would be `[:a, :c, :d]`.
    * `guard_vars` would be `[:b]`.

  The main goal of this function is to process the clauses of the `async with` expression.

  This function is order dependent:

    * Variables that are used but not defined in previous clauses are considered external.
      External variables are removed from the list of `used_vars`, as they shouldn't be
      considered when building the dependency graph.
    * Variables that are rebinded in next clauses are renamed to avoid collisions when building
      the dependency graph.
    * Ignored variables are renamed to avoid compiler warnings. See
      `AsyncWith.Macro.DependencyGraph.to_ast/2` for more information.

  Variables are renamed using the following pattern:

      async_with_<var name>@<version>

  ## Examples

  As example, given the following `async with` expression:

      async with {^ok, a} when is_integer(a) <- echo(b, c, a),
                 {_ok, b} <- echo(m) ~> {d, a},
                 {:ok, a} <- echo(a),
                 {:ok, b, m} <- echo(b) do
      end

  the list of clauses returned by `from_ast/1` would be as if the `async with`
  expression were:

      async with {^ok, async_with_a@1} when is_integer(async_with_a@1) <- echo(b, c, a),
                 {async_with__ok@1, async_with_b@1} <- echo(m) ~> {d, async_with_a@1},
                 {:ok, a} <- echo(async_with_a@1),
                 {:ok, b, m} <- echo(async_with_b@1) do
      end

  """
  @spec from_ast(Macro.t) :: [clause]
  def from_ast(ast) do
    ast
    |> Enum.map(&one_from_ast/1)
    |> remove_external_vars()
    |> rename_rebinded_vars()
    |> Enum.map(&turn_operator_left_right_properties_into_functions/1)
  end

  defp one_from_ast({:=, _meta, [left, right]}), do: do_one_from_ast(:=, left, right)
  defp one_from_ast({:<-, _meta, [left, right]}), do: do_one_from_ast(:<-, left, right)
  # Bare expressions are converted to clauses following the pattern `_ = <bare expression>`
  defp one_from_ast(ast), do: do_one_from_ast(:=, Macro.var(:_, nil), ast)

  defp do_one_from_ast(operator, left, right) do
    pinned_vars = AsyncWith.Macro.get_pinned_vars(left)

    %{
      operator: operator,
      left: left,
      right: right,
      used_vars: Enum.uniq(AsyncWith.Macro.get_vars(right) ++ pinned_vars),
      defined_vars: AsyncWith.Macro.get_vars(left) -- pinned_vars,
      guard_vars: AsyncWith.Macro.get_guard_vars(left)
    }
  end

  defp remove_external_vars(clauses) do
    {clauses, _defined_vars} = Enum.map_reduce(clauses, [], fn clause, defined_vars ->
      clause = %{clause | used_vars: common_vars(clause.used_vars, defined_vars)}
      defined_vars = Enum.uniq(defined_vars ++ clause.defined_vars)

      {clause, defined_vars}
    end)

    clauses
  end

  defp common_vars(var_list_1, var_list_2), do: var_list_1 -- (var_list_1 -- var_list_2)

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
    %{
      operator: clause.operator,
      left: AsyncWith.Macro.rename_pinned_vars(clause.left, var_renamings),
      right: AsyncWith.Macro.rename_vars(clause.right, var_renamings),
      defined_vars: clause.defined_vars,
      used_vars: rename_vars(clause.used_vars, var_renamings),
      guard_vars: clause.guard_vars
    }
  end

  defp rename_defined_vars(clause, var_renamings) do
    %{
      operator: clause.operator,
      left: AsyncWith.Macro.rename_vars(clause.left, var_renamings),
      right: clause.right,
      defined_vars: rename_vars(clause.defined_vars, var_renamings),
      used_vars: clause.used_vars,
      guard_vars: rename_vars(clause.guard_vars, var_renamings)
    }
  end

  defp rename_vars(vars, var_renamings) do
    Enum.map(vars, &Map.get(var_renamings, &1, &1))
  end

  defp reverse_var_renamings(var_renamings) do
    for {k, v} <- var_renamings, do: {v, k}, into: %{}
  end

  defp remove_ignored_vars_from_var_renamings(var_renamings) do
    for {k, v} <- var_renamings, !String.starts_with?("#{k}", "_"), do: {k, v}, into: %{}
  end

  defp update_var_renamings(var_renamings, vars) do
    Enum.reduce(vars, var_renamings, fn var, var_renamings ->
      var_renaming = Map.get(var_renamings, var, var)
      Map.put(var_renamings, var, rename_var(var, get_version(var_renaming)))
    end)
  end

  defp rename_var(var_name, version) do
    :"async_with_#{var_name}@#{version}"
  end

  defp get_version(var) do
    case String.split(Atom.to_string(var), "@") do
      [_var_name] -> 1
      [_var_name, version] -> String.to_integer(version) + 1
    end
  end

  defp turn_operator_left_right_properties_into_functions(clause) do
    assignments =
      Enum.map(clause.used_vars, fn var ->
        quote do
          unquote(Macro.var(var, nil)) = Keyword.fetch!(results, unquote(var))
        end
      end)

    results =
      Enum.map(clause.defined_vars, fn var ->
        quote do
          {unquote(var), unquote(Macro.var(var, nil))}
        end
      end)

    function =
      case clause do
        %{operator: :<-} ->
          quote do
            fn results ->
              unquote(assignments)
              with unquote(clause.left) <- unquote(clause.right) do
                unquote({:ok, results})
              else
                error -> {:error, error}
              end
            end
          end
        %{operator: :=} ->
          quote do
            fn results ->
              try do
                unquote(assignments)
                unquote(clause.left) = unquote(clause.right)
                unquote({:ok, results})
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end
      end

    %{
      function: function,
      defined_vars: clause.defined_vars,
      used_vars: clause.used_vars,
      guard_vars: clause.guard_vars
    }
  end
end
