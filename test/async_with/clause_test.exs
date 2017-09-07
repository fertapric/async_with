defmodule AsyncWith.ClauseTest do
  use ExUnit.Case, async: true

  alias AsyncWith.Clause

  doctest Clause

  test "one_from_ast/1 converts bare expressions into assignments" do
    ast = quote(do: {:ok, a})
    expected_clause = %Clause{
      ast: ast,
      operator: :=,
      left: Macro.var(:_, nil),
      right: ast,
      defined_vars: MapSet.new(),
      used_vars: MapSet.new([:a]),
      guard_vars: MapSet.new()
    }

    assert Clause.one_from_ast(ast) == expected_clause
  end

  test "one_from_ast/1 with assignments" do
    ast = quote(do: {^ok, a} = {:ok, b})
    expected_clause = %Clause{
      ast: ast,
      operator: :=,
      left: quote(do: {^ok, a}),
      right: quote(do: {:ok, b}),
      defined_vars: MapSet.new([:a]),
      used_vars: MapSet.new([:ok, :b]),
      guard_vars: MapSet.new()
    }

    assert Clause.one_from_ast(ast) == expected_clause
  end

  test "one_from_ast/1 with guards" do
    ast = quote(do: {:ok, a} when is_integer(a) <- {:ok, b})
    expected_clause = %Clause{
      ast: ast,
      operator: :<-,
      left: quote(do: {:ok, a} when is_integer(a)),
      right: quote(do: {:ok, b}),
      defined_vars: MapSet.new([:a]),
      used_vars: MapSet.new([:b]),
      guard_vars: MapSet.new([:a])
    }

    assert Clause.one_from_ast(ast) == expected_clause
  end

  test "one_from_ast/1 with ignored and unbound variables" do
    ast = quote(do: {_ok, _} <- {:ok, b})
    expected_clause = %Clause{
      ast: ast,
      operator: :<-,
      left: quote(do: {_ok, _}),
      right: quote(do: {:ok, b}),
      defined_vars: MapSet.new([:_ok]),
      used_vars: MapSet.new([:b]),
      guard_vars: MapSet.new()
    }

    assert Clause.one_from_ast(ast) == expected_clause
  end

  test "many_from_ast/1 renames rebinded variables" do
    ast = quote do
      [
        {^ok, a} <- echo(b, c),
        {:ok, b} <- echo(m),
        {:ok, a} <- echo(a),
        {:ok, b, m} <- echo(b)
      ]
    end

    clauses = Clause.many_from_ast(ast)

    renamed_a = get_renamed_var(clauses, :a)
    renamed_b = get_renamed_var(clauses, :b)
    renamed_var_a = {renamed_a, [], __MODULE__}
    renamed_var_b = {renamed_b, [], __MODULE__}

    expected_clauses = [
      %Clause{
        ast: quote(do: {^ok, a} <- echo(b, c)),
        operator: :<-,
        left: quote(do: {^ok, unquote(renamed_var_a)}),
        right: quote(do: echo(b, c)),
        defined_vars: MapSet.new([renamed_a]),
        used_vars: MapSet.new(),
        guard_vars: MapSet.new()
      },
      %Clause{
        ast: quote(do: {:ok, b} <- echo(m)),
        operator: :<-,
        left: quote(do: {:ok, unquote(renamed_var_b)}),
        right: quote(do: echo(m)),
        defined_vars: MapSet.new([renamed_b]),
        used_vars: MapSet.new(),
        guard_vars: MapSet.new()
      },
      %Clause{
        ast: quote(do: {:ok, a} <- echo(a)),
        operator: :<-,
        left: quote(do: {:ok, a}),
        right: quote(do: echo(unquote(renamed_var_a))),
        defined_vars: MapSet.new([:a]),
        used_vars: MapSet.new([renamed_a]),
        guard_vars: MapSet.new()
      },
      %Clause{
        ast: quote(do: {:ok, b, m} <- echo(b)),
        operator: :<-,
        left: quote(do: {:ok, b, m}),
        right: quote(do: echo(unquote(renamed_var_b))),
        defined_vars: MapSet.new([:b, :m]),
        used_vars: MapSet.new([renamed_b]),
        guard_vars: MapSet.new()
      }
    ]

    assert clauses == expected_clauses
  end

  test "many_from_ast/1 with guards" do
    ast = quote do
      [
        {^ok, a} when is_atom(a) <- echo(b, c),
        {:ok, b} <- echo(m),
        {:ok, a} <- echo(a),
        {:ok, b, m} <- echo(b)
      ]
    end

    clauses = Clause.many_from_ast(ast)

    renamed_a = get_renamed_var(clauses, :a)
    renamed_b = get_renamed_var(clauses, :b)
    renamed_var_a = {renamed_a, [], __MODULE__}
    renamed_var_b = {renamed_b, [], __MODULE__}

    expected_clauses = [
      %Clause{
        ast: quote(do: {^ok, a} when is_atom(a) <- echo(b, c)),
        operator: :<-,
        left: quote(do: {^ok, unquote(renamed_var_a)} when is_atom(unquote(renamed_var_a))),
        right: quote(do: echo(b, c)),
        defined_vars: MapSet.new([renamed_a]),
        used_vars: MapSet.new(),
        guard_vars: MapSet.new([renamed_a])
      },
      %Clause{
        ast: quote(do: {:ok, b} <- echo(m)),
        operator: :<-,
        left: quote(do: {:ok, unquote(renamed_var_b)}),
        right: quote(do: echo(m)),
        defined_vars: MapSet.new([renamed_b]),
        used_vars: MapSet.new(),
        guard_vars: MapSet.new()
      },
      %Clause{
        ast: quote(do: {:ok, a} <- echo(a)),
        operator: :<-,
        left: quote(do: {:ok, a}),
        right: quote(do: echo(unquote(renamed_var_a))),
        defined_vars: MapSet.new([:a]),
        used_vars: MapSet.new([renamed_a]),
        guard_vars: MapSet.new()
      },
      %Clause{
        ast: quote(do: {:ok, b, m} <- echo(b)),
        operator: :<-,
        left: quote(do: {:ok, b, m}),
        right: quote(do: echo(unquote(renamed_var_b))),
        defined_vars: MapSet.new([:b, :m]),
        used_vars: MapSet.new([renamed_b]),
        guard_vars: MapSet.new()
      }
    ]

    assert clauses == expected_clauses
  end

  test "many_from_ast/1 with ignored and unbound variables" do
    ast = quote(do: [{_ok, _} <- echo(b, c)])

    clauses = Clause.many_from_ast(ast)

    renamed__ok = get_renamed_var(clauses, :_ok)
    renamed_var__ok = {renamed__ok, [], __MODULE__}

    expected_clauses = [
      %Clause{
        ast: quote(do: {_ok, _} <- echo(b, c)),
        operator: :<-,
        left: quote(do: {unquote(renamed_var__ok), _}),
        right: quote(do: echo(b, c)),
        defined_vars: MapSet.new([renamed__ok]),
        used_vars: MapSet.new(),
        guard_vars: MapSet.new()
      }
    ]

    assert clauses == expected_clauses
  end

  defp get_renamed_var(clauses, var) do
    clauses
    |> get_defined_vars()
    |> Enum.find(&renamed_var?(&1, var))
  end

  defp get_defined_vars(clauses) do
    Enum.reduce(clauses, MapSet.new(), fn clause, defined_vars ->
      MapSet.union(clause.defined_vars, defined_vars)
    end)
  end

  defp renamed_var?(renamed_var, var) do
    String.contains?("#{renamed_var}", "async_with_#{var}_")
  end
end
