defmodule AsyncWith.Cover do
  @moduledoc """
  Wrapper class for Erlang's cover tool.
  """

  @doc """
  This method will be called from mix to trigger coverage analysis.
  """
  def start(compile_path, opts) do
    # Ensure to clear previous :cover result for avoiding duplicated display
    :cover.stop()
    :cover.start()

    case compile_path |> to_charlist() |> :cover.compile_beam_directory() do
      results when is_list(results) -> :ok
      {:error, _} -> Mix.raise("Failed to cover compile directory: " <> compile_path)
    end

    output = opts[:output]
    ignore_modules = Keyword.get(opts, :ignore_modules, [])
    modules = filter_modules(:cover.modules(), [__MODULE__ | ignore_modules])

    fn ->
      File.mkdir_p!(output)
      Enum.each(modules, &write_coverage_html_file(&1, output))
      print_coverage(get_coverage(modules))
    end
  end

  defp filter_modules(modules, ignore_list) do
    Enum.reject(modules, &Enum.member?(ignore_list, &1))
  end

  defp write_coverage_html_file(module, output) do
    {:ok, _} = :cover.analyse_to_file(module, '#{output}/#{module}.html', [:html])
  end

  defp print_coverage({covered, 0, _modules_coverage}) do
    IO.puts("Covered #{covered} of #{covered} lines (100%)")
  end

  defp print_coverage({covered, non_covered, modules_coverage}) do
    total = covered + non_covered
    coverage = percentage(covered, total)

    uncovered_modules_coverage =
      modules_coverage
      |> Enum.filter(fn {_module, _covered, non_covered, _missing} -> non_covered > 0 end)
      |> sort_modules_coverage_by_coverage()

    IO.puts("Covered #{covered} of #{total} lines (#{coverage}%). Modules (coverage asc):\n")
    Enum.each(uncovered_modules_coverage, &print_module_coverage/1)
    IO.puts("")

    covered_modules_num = length(modules_coverage) - length(uncovered_modules_coverage)
    if covered_modules_num > 0, do: IO.puts("#{covered_modules_num} modules with 100% coverage")
  end

  defp sort_modules_coverage_by_coverage(modules_coverage) do
    Enum.sort(modules_coverage, fn {_, covered_1, non_covered_1, _},
                                   {_, covered_2, non_covered_2, _} ->
      total_1 = covered_1 + non_covered_1
      total_2 = covered_2 + non_covered_2
      percentage(covered_2, total_2) >= percentage(covered_1, total_1)
    end)
  end

  defp print_module_coverage({module, covered, non_covered, missing}) do
    total = covered + non_covered
    coverage = percentage(covered, total)

    formatted_coverage =
      coverage
      |> :erlang.float_to_binary(decimals: 2)
      |> String.pad_leading(5)

    formatted_missing =
      missing
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.join(", ")

    IO.puts("  #{formatted_coverage}%  #{module}")
    IO.puts("          Missing lines (#{non_covered}/#{total}): #{formatted_missing}")
  end

  defp get_coverage(modules) when is_list(modules) do
    Enum.reduce(modules, {0, 0, []}, fn module, {covered, non_covered, modules_coverage} ->
      {_mod, mod_covered, mod_non_covered, _missing} = mod_coverage = get_module_coverage(module)
      {covered + mod_covered, non_covered + mod_non_covered, [mod_coverage | modules_coverage]}
    end)
  end

  defp get_module_coverage(module) do
    {:ok, lines_coverage} = :cover.analyse(module, :coverage, :line)

    lines_coverage
    |> remove_hidden_lines()
    |> Enum.reduce({module, 0, 0, []}, fn
      {{_module, line}, {0, _}}, {module, covered, non_covered, missing} ->
        {module, covered, non_covered + 1, [line | missing]}

      _line_coverage, {module, covered, non_covered, missing} ->
        {module, covered + 1, non_covered, missing}
    end)
  end

  defp remove_hidden_lines(lines_coverage) do
    Enum.reject(lines_coverage, fn
      {{_, 0}, _} -> true
      _ -> false
    end)
  end

  defp percentage(_covered, 0), do: 0.0
  defp percentage(dividend, divisor), do: Float.round(dividend * 100 / divisor, 2)
end
