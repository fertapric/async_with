defmodule AsyncWith.Cover do
  @moduledoc """
  Wrapper class for Erlang's cover tool.
  """

  @doc """
  This method will be called from mix to trigger coverage analysis.
  The special functions `__info__` and `__struct__` are filtered out of the coverage.
  """
  def start(compile_path, opts) do
    # Ensure to clear previous :cover result for avoiding duplicated display (umbrella)
    :cover.stop()
    :cover.start()

    case compile_path |> to_charlist() |> :cover.compile_beam_directory() do
      results when is_list(results) -> :ok
      {:error, _} -> Mix.raise("Failed to cover compile directory: " <> compile_path)
    end

    output = opts[:output]
    ignore_modules = Keyword.get(opts, :ignore_modules, [])
    modules = filter_modules(:cover.modules, [__MODULE__ | ignore_modules])

    fn ->
      File.mkdir_p!(output)
      Enum.each(modules, &write_coverage_html_file(&1, output))

      case get_coverage(modules) do
        {0, non_covered} ->
          IO.puts("Covered 0 lines of #{non_covered} (0%)")
        {covered, non_covered} ->
          lines = covered + non_covered
          coverage = Float.round(covered * 100 / lines, 2)

          IO.puts("Covered #{covered} lines of #{lines} (#{coverage}%)")
        end
    end
  end

  defp write_coverage_html_file(module, output) do
    {:ok, _} = :cover.analyse_to_file(module, '#{output}/#{module}.html', [:html])
  end

  defp get_coverage(modules) when is_list(modules) do
    Enum.reduce(modules, {0, 0}, fn(module, {total_covered, total_non_covered}) ->
      {covered, non_covered} = get_module_coverage(module)
      {total_covered + covered, total_non_covered + non_covered}
    end)
  end

  defp get_module_coverage(module) do
    {:ok, functions} = :cover.analyse(module, :coverage, :function)

    functions
    |> filter_functions()
    |> Enum.reduce({0, 0}, fn({_, {covered, non_covered}}, {total_covered, total_non_covered}) ->
      {total_covered + covered, total_non_covered + non_covered}
    end)
  end

  defp filter_modules(modules, ignore_list) do
    Enum.reject(modules, &Enum.member?(ignore_list, &1))
  end

  defp filter_functions(functions) do
    Enum.reject(functions, fn {{_, :__info__, _}, _} -> true
                              {{_, :__struct__, _}, _} -> true
                              {{_, :"MACRO-__using__", _}, _} -> true
                              _ -> false end)
  end
end
