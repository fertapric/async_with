defmodule AsyncWith.MixProject do
  use Mix.Project

  @version "0.3.0"

  def project do
    [
      app: :async_with,
      version: @version,
      elixir: "~> 1.7",
      deps: deps(),
      package: package(),
      preferred_cli_env: [docs: :docs, "hex.publish": :docs],
      description: description(),
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AsyncWith.Application, []}
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.27.0", only: :docs}
    ]
  end

  def description do
    """
    The asynchronous version of Elixir's "with", resolving the dependency graph and executing
    the clauses in the most performant way possible!
    """
  end

  defp package do
    [
      maintainers: ["Fernando Tapia Rico"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/fertapric/async_with"}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "AsyncWith",
      canonical: "http://hexdocs.pm/async_with",
      source_url: "https://github.com/fertapric/async_with"
    ]
  end

  defp dialyzer do
    plt_core_path = System.get_env("DIALYZER_PLT_CORE_PATH") || Mix.Utils.mix_home()
    plt_local_path = System.get_env("DIALYZER_PLT_LOCAL_PATH") || Mix.Project.build_path()

    [
      plt_core_path: plt_core_path,
      plt_file: {:no_warn, Path.join(plt_local_path, "async_with.plt")},
      plt_add_deps: :transitive,
      flags: [:unmatched_returns, :error_handling, :race_conditions, :underspecs]
    ]
  end
end
