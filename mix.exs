defmodule AsyncWith.Mixfile do
  use Mix.Project

  @version "0.2.2"

  def project do
    [
      app: :async_with,
      version: @version,
      elixir: "~> 1.4",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      preferred_cli_env: [docs: :docs],
      description: description(),
      docs: docs(),
      test_coverage: [tool: AsyncWith.Cover, ignore_modules: [AsyncWith.ClauseError]],
      dialyzer: [flags: [:unmatched_returns, :error_handling, :race_conditions, :underspecs]]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AsyncWith.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 0.8.10", only: :dev, runtime: false},
      {:dialyxir, "~> 0.5.1", only: :dev, runtime: false},
      {:ex_doc, "~> 0.18.3", only: :docs}
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
      links: %{"GitHub" => "https://github.com/fertapric/async_with"},
      files: ~w(mix.exs LICENSE README.md lib)
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
end
