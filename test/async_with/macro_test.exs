defmodule AsyncWith.MacroTest do
  use ExUnit.Case, async: true

  doctest AsyncWith.Macro

  test "get_pinned_vars/1 returns a list of variables without duplicates" do
    ast = quote(do: {^ok, {^ok, a}, ^b} <- echo(c, d))

    assert AsyncWith.Macro.get_pinned_vars(ast) == [:ok, :b]
  end

  test "get_guard_vars/1 returns a list of variables without duplicates" do
    ast = quote(do: {:ok, a} when not is_atom(a) and not is_list(a) <- echo(b))

    assert AsyncWith.Macro.get_guard_vars(ast) == [:a]
  end
end
