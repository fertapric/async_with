defmodule AsyncWith.Clauses do
  @moduledoc false

  defmodule Clause do
    @moduledoc false

    import AsyncWith.Macro,
      only: [get_pinned_vars: 1, get_vars: 1, rename_pinned_vars: 2, rename_vars: 2, var?: 1]

    @doc """
    Returns true if the clause will always match.

    ## Examples

        iex> ast = quote(do: a <- 1)
        iex> Clause.always_match?(ast)
        true

        iex> [ast] = quote(do: (a -> 1))
        iex> Clause.always_match?(ast)
        true

        iex> ast = quote(do: _ <- 1)
        iex> Clause.always_match?(ast)
        true

        iex> [ast] = quote(do: (_ -> 1))
        iex> Clause.always_match?(ast)
        true

        iex> ast = quote(do: a = 1)
        iex> Clause.always_match?(ast)
        true

        iex> ast = quote(do: a + b)
        iex> Clause.always_match?(ast)
        true

        iex> ast = quote(do: {:ok, a} <- b + 1)
        iex> Clause.always_match?(ast)
        false

        iex> [ast] = quote(do: ({:ok, b} -> b + 1))
        iex> Clause.always_match?(ast)
        false

    """
    @spec always_match?(Macro.t()) :: boolean
    def always_match?({:<-, _meta, [{:_, _, _context}, _right]}), do: true
    def always_match?({:<-, _meta, [left, _right]}), do: var?(left)
    def always_match?({:->, _meta, [[{:_, _, _context}], _right]}), do: true
    def always_match?({:->, _meta, [[left], _right]}), do: var?(left)
    def always_match?(_), do: true

    @doc """
    Returns the list of used variables in the clause.

    Used variables are the ones at the right hand side of the clause or pinned
    variables at the left hand side of the clause.

    ## Examples

        iex> ast =
        ...>   quote do
        ...>     {^ok, a, b, _, _c} when is_integer(a) and b > 0 <- echo(d, e)
        ...>   end
        iex> Clause.get_used_vars(ast)
        [:ok, :d, :e]

    """
    @spec get_used_vars(Macro.t()) :: Macro.t()
    def get_used_vars({_operator, _meta, [left, right]}) do
      Enum.uniq(get_pinned_vars(left) ++ get_vars(right))
    end

    @doc """
    Returns the list of defined variables in the clause.

    Defined variables are the ones binded at the left hand side of the clause.

    ## Examples

        iex> ast =
        ...>   quote do
        ...>     {^ok, a, b, _, _c} when is_integer(a) and b > 0 <- echo(d, e)
        ...>   end
        iex> Clause.get_defined_vars(ast)
        [:a, :b, :_c]

    """
    @spec get_defined_vars(Macro.t()) :: Macro.t()
    def get_defined_vars({_operator, _meta, [left, _right]}) do
      get_vars(left) -- get_pinned_vars(left)
    end

    @doc """
    Renames the used variables in the clause.

    Used variables are the ones at the right hand side of the clause or pinned
    variables at the left hand side of the clause.

    ## Examples

        iex> ast = quote(do: {^ok, a} when is_integer(a) <- b + c)
        iex> var_renamings = %{ok: :new_ok, b: :new_b, a: :new_a}
        iex> Clause.rename_used_vars(ast, var_renamings) |> Macro.to_string()
        "{^new_ok, a} when is_integer(a) <- new_b + c"

    """
    @spec rename_used_vars(Macro.t(), map) :: Macro.t()
    def rename_used_vars({operator, meta, [left, right]}, var_renamings) do
      renamed_left = rename_pinned_vars(left, var_renamings)
      renamed_right = rename_vars(right, var_renamings)

      {operator, meta, [renamed_left, renamed_right]}
    end

    @doc """
    Renames the defined (or binded) variables in the clause.

    Defined variables are the ones binded at the left hand side of the clause.

    ## Examples

        iex> ast = quote(do: {^ok, a, b}  when is_integer(a)<- c + d)
        iex> var_renamings = %{ok: :new_ok, a: :new_a, c: :new_c}
        iex> Clause.rename_defined_vars(ast, var_renamings) |> Macro.to_string()
        "{^ok, new_a, b} when is_integer(new_a) <- c + d"

    """
    @spec rename_defined_vars(Macro.t(), map) :: Macro.t()
    def rename_defined_vars({operator, meta, [left, right]} = clause, var_renamings) do
      defined_vars = get_defined_vars(clause)
      renamed_left = rename_vars(left, Map.take(var_renamings, defined_vars))

      {operator, meta, [renamed_left, right]}
    end
  end

  @doc """
  Returns true if all patterns in `clauses` will always match.

  ## Examples

      iex> ast = quote(do: [a <- 1, b <- 2, _ <- c, {:ok, d} = echo(c)])
      iex> Clauses.always_match?(ast)
      true

      iex> ast = quote(do: [a <- 1, {:ok, b} <- echo(a), {:ok, c} = echo(b)])
      iex> Clauses.always_match?(ast)
      false

  """
  @spec always_match?(Macro.t()) :: boolean
  def always_match?(clauses) do
    Enum.all?(clauses, &Clause.always_match?/1)
  end

  @doc """
  Returns true if `clauses` contain a match-all clause.

  This operation can be used to prevent messages like `warning: this clause
  cannot match because a previous clause at line <line number> always matches`.

  ## Examples

      iex> ast =
      ...>   quote do
      ...>     :error -> :error
      ...>     error -> error
      ...>   end
      iex> Clauses.contains_match_all_clause?(ast)
      true

      iex> ast =
      ...>   quote do
      ...>     :error -> :error
      ...>     _ -> nil
      ...>   end
      iex> Clauses.contains_match_all_clause?(ast)
      true

      iex> ast =
      ...>   quote do
      ...>     :error -> :error
      ...>     :ok -> :ok
      ...>   end
      iex> Clauses.contains_match_all_clause?(ast)
      false

  """
  @spec contains_match_all_clause?(Macro.t()) :: boolean
  def contains_match_all_clause?(clauses) do
    Enum.any?(clauses, &Clause.always_match?/1)
  end

  @doc """
  Formats the list of clauses, converting any "bare expression"
  into an assignment (`_ = expression`).

  This operation can be used to normalize clauses, so they are always composed
  of three parts: `left <- right` or `left = right`.

  ## Examples

      iex> ast = quote(do: [a <- 1, b = 2, a + b])
      iex> Clauses.format_bare_expressions(ast) |> Macro.to_string()
      "[a <- 1, b = 2, _ = a + b]"

  """
  @spec format_bare_expressions(Macro.t()) :: Macro.t()
  def format_bare_expressions(clauses) do
    Enum.map(clauses, fn
      {:<-, _meta, _args} = clause -> clause
      {:=, _meta, _args} = clause -> clause
      clause -> {:=, [], [Macro.var(:_, __MODULE__), clause]}
    end)
  end

  @doc """
  Returns the list of local variables that are used and defined per clause.

  Used variables are the ones at the right hand side of the clause or pinned
  variables at the left hand side of the clause.

  Defined variables are the ones binded at the left hand side of the clause.

  Local variables are the ones defined in previous clauses, any other variables
  are considered external.

  It returns `{clause, {defined_vars, used_vars}}` per clause.

  This operation is order dependent.

  ## Examples

      iex> ast =
      ...>   quote do
      ...>     [
      ...>       {:ok, a} when is_integer(a) <- echo(b, c),
      ...>       {^ok, c, d} <- a + e,
      ...>       {^d, f, g} <- a + b + c
      ...>     ]
      ...>   end
      iex> Clauses.get_defined_and_used_local_vars(ast)
      quote do
        [
          {
            {:ok, a} when is_integer(a) <- echo(b, c),
            {[:a], []}
          },
          {
            {^ok, c, d} <- a + e,
            {[:c, :d], [:a]}
          },
          {
            {^d, f, g} <- a + b + c,
            {[:f, :g], [:d, :a, :c]}
          }
        ]
      end

  """
  @spec get_defined_and_used_local_vars(Macro.t()) :: Macro.t()
  def get_defined_and_used_local_vars(clauses) do
    {clauses, _local_vars} =
      Enum.map_reduce(clauses, [], fn clause, local_vars ->
        defined_vars = Clause.get_defined_vars(clause)
        used_vars = Clause.get_used_vars(clause)
        external_vars = used_vars -- local_vars
        used_local_vars = used_vars -- external_vars
        local_vars = Enum.uniq(local_vars ++ defined_vars)

        {{clause, {defined_vars, used_local_vars}}, local_vars}
      end)

    clauses
  end

  @doc """
  Renames all the variables that are defined locally.

  Local variables are the ones defined in previous clauses, any other variables
  are considered external.

  Variables are renamed by appending `@` and the variable "version" to its name
  (i.e. `var@1`).

  This operation can be used to obtain unique variable names, which can be helpful
  in cases of variable rebinding.

  This operation is order dependent.

  ## Examples

      iex> ast =
      ...>   quote do
      ...>     [
      ...>       {:ok, a} <- echo(b, c),
      ...>       {^ok, b, a} when is_integer(a) <- foo(a, b),
      ...>       {^b, c, d} <- bar(a, b, c),
      ...>       {:ok, d, b, a} when is_integer(a) <- baz(a, b, c, d)
      ...>     ]
      ...>   end
      iex> Clauses.rename_local_vars(ast) |> Enum.map(&Macro.to_string/1)
      [
        "{:ok, a@1} <- echo(b, c)",
        "{^ok, b@1, a@2} when is_integer(a@2) <- foo(a@1, b)",
        "{^b@1, c@1, d@1} <- bar(a@2, b@1, c)",
        "{:ok, d@2, b@2, a@3} when is_integer(a@3) <- baz(a@2, b@1, c@1, d@1)"
      ]

  """
  @spec rename_local_vars(Macro.t()) :: Macro.t()
  def rename_local_vars(clauses) do
    {clauses, _var_versions} =
      Enum.map_reduce(clauses, %{}, fn clause, var_versions ->
        clause = Clause.rename_used_vars(clause, var_versions_to_var_renamings(var_versions))

        var_versions = increase_var_versions(var_versions, Clause.get_defined_vars(clause))
        clause = Clause.rename_defined_vars(clause, var_versions_to_var_renamings(var_versions))

        {clause, var_versions}
      end)

    clauses
  end

  defp increase_var_versions(var_versions, vars) do
    Enum.reduce(vars, var_versions, fn var, var_versions ->
      Map.update(var_versions, var, 1, &(&1 + 1))
    end)
  end

  defp var_versions_to_var_renamings(var_versions) do
    var_versions
    |> Enum.map(fn {var, version} -> {var, :"#{var}@#{version}"} end)
    |> Enum.into(%{})
  end
end
