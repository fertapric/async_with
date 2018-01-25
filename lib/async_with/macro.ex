defmodule AsyncWith.Macro do
  @moduledoc false

  @doc """
  Returns the list of variables of the `ast`.

  ## Examples

      iex> ast =
      ...>   quote do
      ...>     {^ok, a, b, _, _c} when is_integer(a) and is_list(b) <- echo(d, e)
      ...>   end
      iex> AsyncWith.Macro.get_vars(ast)
      [:ok, :a, :b, :_c, :d, :e]

  """
  @spec get_vars(Macro.t()) :: [atom]
  def get_vars(ast) do
    ast
    |> do_get_vars()
    |> Enum.uniq()
  end

  defp do_get_vars({:_, _meta, _args}), do: []
  defp do_get_vars({var, _meta, args}) when is_atom(var) and not is_list(args), do: [var]
  defp do_get_vars(ast) when is_list(ast), do: Enum.flat_map(ast, &do_get_vars/1)
  defp do_get_vars(ast) when is_tuple(ast), do: do_get_vars(Tuple.to_list(ast))
  defp do_get_vars(_ast), do: []

  @doc """
  Returns the list of pinned variables (`^var`) of the `ast`.

  ## Examples

      iex> ast =
      ...>   quote do
      ...>     {^ok, a, b, _} when is_integer(a) and is_list(b) <- echo(c, d)
      ...>   end
      iex> AsyncWith.Macro.get_pinned_vars(ast)
      [:ok]

  """
  @spec get_pinned_vars(Macro.t()) :: [atom]
  def get_pinned_vars(ast) do
    ast
    |> do_get_pinned_vars()
    |> Enum.uniq()
  end

  defp do_get_pinned_vars({:^, _meta, args}), do: get_vars(args)
  defp do_get_pinned_vars(ast) when is_list(ast), do: Enum.flat_map(ast, &do_get_pinned_vars/1)
  defp do_get_pinned_vars(ast) when is_tuple(ast), do: do_get_pinned_vars(Tuple.to_list(ast))
  defp do_get_pinned_vars(_ast), do: []

  @doc """
  Returns the list of variables used in the guard clauses of the `ast`.

  ## Examples

      iex> ast =
      ...>   quote do
      ...>     {^ok, a, b, _} when is_integer(a) and is_list(b) <- echo(c, d)
      ...>   end
      iex> AsyncWith.Macro.get_guard_vars(ast)
      [:a, :b]

  """
  @spec get_guard_vars(Macro.t()) :: [atom]
  def get_guard_vars(ast) do
    ast
    |> do_get_guard_vars()
    |> Enum.uniq()
  end

  defp do_get_guard_vars({:when, _meta, [_left, right]}), do: get_vars(right)
  defp do_get_guard_vars(ast) when is_list(ast), do: Enum.flat_map(ast, &do_get_guard_vars/1)
  defp do_get_guard_vars(ast) when is_tuple(ast), do: do_get_guard_vars(Tuple.to_list(ast))
  defp do_get_guard_vars(_ast), do: []

  @doc """
  Returns true if the `ast` represents a variable.

  ## Examples

      iex> ast = quote(do: a)
      iex> AsyncWith.Macro.var?(ast)
      true

      iex> ast = quote(do: {:ok, 1})
      iex> AsyncWith.Macro.var?(ast)
      false

  """
  @spec var?(Macro.t()) :: boolean
  def var?(ast) do
    case ast do
      {var, _meta, args} when is_atom(var) and not is_list(args) -> true
      _ -> false
    end
  end

  @doc ~S"""
  Returns an AST node where each variable is replaced by the result of invoking
  `function` on that variable.

  ## Examples

      iex> ast = quote(do: [^a, {1, %{b: c}, [2, d], [e: ^f]}, _])
      iex> fun = fn {var, meta, context} -> {:"var_#{var}", meta, context} end
      iex> AsyncWith.Macro.map_vars(ast, fun) |> Macro.to_string()
      "[^var_a, {1, %{b: var_c}, [2, var_d], [e: ^var_f]}, _]"

  """
  @spec map_vars(Macro.t(), function) :: Macro.t()
  def map_vars(ast, function)
  def map_vars({:_, _meta, _args} = ast, _fun), do: ast
  def map_vars({var, _, args} = ast, fun) when is_atom(var) and not is_list(args), do: fun.(ast)
  def map_vars(ast, fun) when is_list(ast), do: Enum.map(ast, &map_vars(&1, fun))
  def map_vars(ast, fun) when is_tuple(ast), do: tuple_map(ast, &map_vars(&1, fun))
  def map_vars(ast, _fun), do: ast

  @doc ~S"""
  Returns an AST node where each pinned variable (`^var`) is replaced by the
  result of invoking `function` on that variable.

  ## Examples

      iex> ast = quote(do: [^a, {1, %{b: c}, [2, d], [e: ^f]}, _])
      iex> fun = fn {var, meta, context} -> {:"var_#{var}", meta, context} end
      iex> AsyncWith.Macro.map_pinned_vars(ast, fun) |> Macro.to_string()
      "[^var_a, {1, %{b: c}, [2, d], [e: ^var_f]}, _]"

  """
  @spec map_pinned_vars(Macro.t(), function) :: Macro.t()
  def map_pinned_vars(ast, function)
  def map_pinned_vars({:^, meta, args}, fun), do: {:^, meta, map_vars(args, fun)}
  def map_pinned_vars(ast, fun) when is_list(ast), do: Enum.map(ast, &map_pinned_vars(&1, fun))
  def map_pinned_vars(ast, fun) when is_tuple(ast), do: tuple_map(ast, &map_pinned_vars(&1, fun))
  def map_pinned_vars(ast, _fun), do: ast

  @doc """
  Renames the variables in `ast`.

  ## Examples

      iex> ast = quote(do: [^a, {1, %{b: c}, [2, d], [e: f]}])
      iex> var_renamings = %{a: :foo, b: :wadus, c: :bar, f: :qux}
      iex> AsyncWith.Macro.rename_vars(ast, var_renamings) |> Macro.to_string()
      "[^foo, {1, %{b: bar}, [2, d], [e: qux]}]"

  """
  @spec rename_vars(Macro.t(), map) :: Macro.t()
  def rename_vars(ast, var_renamings) do
    map_vars(ast, fn {var, meta, context} ->
      {Map.get(var_renamings, var, var), meta, context}
    end)
  end

  @doc """
  Renames the pinned variables (`^var`) in `ast`.

  ## Examples

      iex> ast = quote(do: [^a, {1, %{b: c}, [2, d], [e: ^f]}])
      iex> var_renamings = %{a: :foo, c: :bar, f: :qux}
      iex> AsyncWith.Macro.rename_pinned_vars(ast, var_renamings)
      ...> |> Macro.to_string()
      "[^foo, {1, %{b: c}, [2, d], [e: ^qux]}]"

  """
  @spec rename_pinned_vars(Macro.t(), map) :: Macro.t()
  def rename_pinned_vars(ast, var_renamings) do
    map_pinned_vars(ast, fn {var, meta, context} ->
      {Map.get(var_renamings, var, var), meta, context}
    end)
  end

  @doc """
  Renames the ignored variables (`_var`) in `ast`.

  Variables are renamed by appending `@`.

  ## Examples

      iex> ast = quote(do: [^a, {1, %{b: c}, [2, _d], [e: ^f], _}])
      iex> AsyncWith.Macro.rename_ignored_vars(ast) |> Macro.to_string()
      "[^a, {1, %{b: c}, [2, @_d], [e: ^f], _}]"

  """
  @spec rename_ignored_vars(Macro.t()) :: Macro.t()
  def rename_ignored_vars(ast) do
    map_vars(ast, fn {var, meta, context} ->
      case to_string(var) do
        "_" <> _ -> {:"@#{var}", meta, context}
        _ -> {var, meta, context}
      end
    end)
  end

  @doc """
  Generates an AST node representing the list of variables given by the atoms
  `vars` and `context`.

  ## Examples

      iex> vars = [:a, :b, :c]
      iex> AsyncWith.Macro.var_list(vars) |> Macro.to_string()
      "[a, b, c]"

  """
  @spec var_list([atom], atom) :: Macro.t()
  def var_list(vars, context \\ nil) when is_list(vars) and is_atom(context) do
    Enum.map(vars, &Macro.var(&1, context))
  end

  @doc """
  Generates an AST node representing a map of variables given by the atoms
  `vars` and `context`.

  ## Examples

      iex> vars = [:a, :b, :c]
      iex> AsyncWith.Macro.var_map(vars) |> Macro.to_string()
      "%{a: a, b: b, c: c}"

  """
  @spec var_map([atom], atom) :: Macro.t()
  def var_map(vars, context \\ nil) when is_list(vars) and is_atom(context) do
    {:%{}, [], Enum.map(vars, fn var -> {var, Macro.var(var, context)} end)}
  end

  defp tuple_map(tuple, fun) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&fun.(&1))
    |> List.to_tuple()
  end
end
