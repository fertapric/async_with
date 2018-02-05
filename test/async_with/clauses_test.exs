defmodule AsyncWith.ClausesTest do
  use ExUnit.Case, async: true

  alias AsyncWith.Clauses
  alias AsyncWith.Clauses.Clause

  doctest Clauses
  doctest Clause
end
