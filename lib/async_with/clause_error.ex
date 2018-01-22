defmodule AsyncWith.ClauseError do
  defexception [:term]

  def message(exception) do
    "no async with clause matching: #{inspect(exception.term)}"
  end
end
