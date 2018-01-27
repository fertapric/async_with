defmodule AsyncWith.ClausesTest do
  use ExUnit.Case, async: true

  alias AsyncWith.Clauses

  test "from_ast/1 renames rebinded variables" do
    ast =
      quote do
        [
          {^ok, a} <- echo(b, c),
          {:ok, b} <- echo(m),
          {:ok, a} <- echo(a),
          {:ok, b, m} <- echo(b)
        ]
      end

    clauses = Clauses.from_ast(ast)
    async_with_a1 = Macro.var(:async_with_a@1, nil)
    async_with_b1 = Macro.var(:async_with_b@1, nil)

    assert_equal(clauses, [
      %{
        function:
          quote do
            fn results ->
              try do
                with %{} <- results,
                     {^ok, unquote(async_with_a1)} <- echo(b, c) do
                  {:ok, %{async_with_a@1: unquote(async_with_a1)}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:async_with_a@1],
        used_vars: [],
        guard_vars: []
      },
      %{
        function:
          quote do
            fn results ->
              try do
                with %{} <- results,
                     {:ok, unquote(async_with_b1)} <- echo(m) do
                  {:ok, %{async_with_b@1: unquote(async_with_b1)}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:async_with_b@1],
        used_vars: [],
        guard_vars: []
      },
      %{
        function:
          quote do
            fn results ->
              try do
                with %{async_with_a@1: unquote(async_with_a1)} <- results,
                     {:ok, a} <- echo(unquote(async_with_a1)) do
                  {:ok, %{a: a}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:a],
        used_vars: [:async_with_a@1],
        guard_vars: []
      },
      %{
        function:
          quote do
            fn results ->
              try do
                with %{async_with_b@1: unquote(async_with_b1)} <- results,
                     {:ok, b, m} <- echo(unquote(async_with_b1)) do
                  {:ok, %{b: b, m: m}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:b, :m],
        used_vars: [:async_with_b@1],
        guard_vars: []
      }
    ])
  end

  test "from_ast/1 works with guards" do
    ast =
      quote do
        [
          {^ok, a} when is_atom(a) <- echo(b, c),
          {:ok, b} <- echo(m),
          {:ok, a} <- echo(a),
          {:ok, b, m} <- echo(b)
        ]
      end

    clauses = Clauses.from_ast(ast)
    async_with_a1 = Macro.var(:async_with_a@1, nil)
    async_with_b1 = Macro.var(:async_with_b@1, nil)

    assert_equal(clauses, [
      %{
        function:
          quote do
            fn results ->
              try do
                with %{} <- results,
                     {^ok, unquote(async_with_a1)} when is_atom(unquote(async_with_a1)) <-
                       echo(b, c) do
                  {:ok, %{async_with_a@1: unquote(async_with_a1)}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:async_with_a@1],
        used_vars: [],
        guard_vars: [:async_with_a@1]
      },
      %{
        function:
          quote do
            fn results ->
              try do
                with %{} <- results,
                     {:ok, unquote(async_with_b1)} <- echo(m) do
                  {:ok, %{async_with_b@1: unquote(async_with_b1)}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:async_with_b@1],
        used_vars: [],
        guard_vars: []
      },
      %{
        function:
          quote do
            fn results ->
              try do
                with %{async_with_a@1: unquote(async_with_a1)} <- results,
                     {:ok, a} <- echo(unquote(async_with_a1)) do
                  {:ok, %{a: a}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:a],
        used_vars: [:async_with_a@1],
        guard_vars: []
      },
      %{
        function:
          quote do
            fn results ->
              try do
                with %{async_with_b@1: unquote(async_with_b1)} <- results,
                     {:ok, b, m} <- echo(unquote(async_with_b1)) do
                  {:ok, %{b: b, m: m}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:b, :m],
        used_vars: [:async_with_b@1],
        guard_vars: []
      }
    ])
  end

  test "from_ast/1 works with ignored and unbound variables" do
    ast =
      quote do
        [{_ok, _} <- echo(b, c)]
      end

    clauses = Clauses.from_ast(ast)
    async_with__ok = Macro.var(:async_with__ok@1, nil)

    assert_equal(clauses, [
      %{
        function:
          quote do
            fn results ->
              try do
                with %{} <- results,
                     {unquote(async_with__ok), _} <- echo(b, c) do
                  {:ok, %{async_with__ok@1: unquote(async_with__ok)}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:async_with__ok@1],
        used_vars: [],
        guard_vars: []
      }
    ])
  end

  test "from_ast/1 works with assignments" do
    ast =
      quote do
        [
          {:ok, a} <- echo(m),
          {:ok, a} = echo(a)
        ]
      end

    clauses = Clauses.from_ast(ast)
    async_with_a1 = Macro.var(:async_with_a@1, nil)

    assert_equal(clauses, [
      %{
        function:
          quote do
            fn results ->
              try do
                with %{} <- results,
                     {:ok, unquote(async_with_a1)} <- echo(m) do
                  {:ok, %{async_with_a@1: unquote(async_with_a1)}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:async_with_a@1],
        used_vars: [],
        guard_vars: []
      },
      %{
        function:
          quote do
            fn results ->
              try do
                with %{async_with_a@1: unquote(async_with_a1)} <- results,
                     {:ok, a} = echo(unquote(async_with_a1)) do
                  {:ok, %{a: a}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [:a],
        used_vars: [:async_with_a@1],
        guard_vars: []
      }
    ])
  end

  test "from_ast/1 converts bare expressions into assignments" do
    ast =
      quote do
        [{:ok, a}]
      end

    clauses = Clauses.from_ast(ast)

    assert_equal(clauses, [
      %{
        function:
          quote do
            fn results ->
              try do
                with %{} <- results, _ = {:ok, a} do
                  {:ok, %{}}
                else
                  error -> {:error, error}
                end
              rescue
                error in MatchError -> {:match_error, error}
              end
            end
          end,
        defined_vars: [],
        used_vars: [],
        guard_vars: []
      }
    ])
  end

  defp assert_equal(clauses, expected_clauses) do
    var_types = [:defined_vars, :used_vars, :guard_vars]
    vars = Enum.map(clauses, &Map.take(&1, var_types))
    expected_vars = Enum.map(expected_clauses, &Map.take(&1, var_types))

    assert vars == expected_vars

    functions = Enum.map(clauses, &Macro.to_string(&1.function))
    expected_functions = Enum.map(expected_clauses, &Macro.to_string(&1.function))

    assert functions == expected_functions
  end
end
