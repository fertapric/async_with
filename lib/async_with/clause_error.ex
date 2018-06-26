defmodule AsyncWith.ClauseError do
  defexception [:term]

  @impl true
  def message(exception) do
    "no async with clause matching: #{inspect(exception.term)}"
  end
end
