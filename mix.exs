defmodule AsyncWith.MixProject do
  use Mix.Project

  @version "0.3.0"

  def project do
    [
      app: :async_with,
      version: @version,
      elixir: "~> 1.4",
      deps: deps(),
      package: package(),
      preferred_cli_env: [docs: :docs, "hex.publish": :docs],
      description: description(),
      docs: docs(),
      dialyzer: [flags: [:unmatched_returns, :error_handling, :race_conditions, :underspecs]]
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
      {:credo, "~> 1.1.1", only: :dev, runtime: false},
      {:dialyxir, "~> 0.5.1", only: :dev, runtime: false},
      {:ex_doc, "~> 0.20.1", only: :docs}
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
end
