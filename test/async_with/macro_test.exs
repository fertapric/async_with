defmodule AsyncWith.MacroTest do
  use ExUnit.Case, async: true

  doctest AsyncWith.Macro

  test "get_vars/1 ignores the AST for string interpolations" do
    ast = quote(do: {^ok, {^ok, a}, ^b} <- echo("#{c} #{d}"))

    assert AsyncWith.Macro.get_vars(ast) == [:ok, :a, :b, :c, :d]
  end

  test "get_pinned_vars/1 returns a list of variables without duplicates" do
    ast = quote(do: {^ok, {^ok, a}, ^b} <- echo(c, d))

    assert AsyncWith.Macro.get_pinned_vars(ast) == [:ok, :b]
  end

  test "get_guard_vars/1 returns a list of variables without duplicates" do
    ast = quote(do: {:ok, a} when not is_atom(a) and not is_list(a) <- echo(b))

    assert AsyncWith.Macro.get_guard_vars(ast) == [:a]
  end

  test "var?/1 returns false with the special _ variable" do
    refute AsyncWith.Macro.var?({:_, [], nil})
  end

  test "var?/1 returns false with the AST for string interpolations" do
    refute AsyncWith.Macro.var?({:binary, [], nil})
  end

  test "map_vars/2 ignores the AST for string interpolations" do
    ast = quote(do: [^a, {1, %{b: "#{c} #{d}"}, [e: ^f]}, _])
    fun = fn {var, meta, context} -> {:"var_#{var}", meta, context} end

    string = ast |> AsyncWith.Macro.map_vars(fun) |> Macro.to_string()

    assert string == ~S([^var_a, {1, %{b: "#{var_c} #{var_d}"}, [e: ^var_f]}, _])
  end
end
