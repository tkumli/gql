defmodule GQL.MixProject do
  use Mix.Project

  def project do
    [
      app: :gql,
      version: "0.1.0",
      elixir: "~> 1.17 or ~> 1.18 or ~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/bsanyi/gql",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    "A GraphQL query builder for Elixir"
  end

  defp package do
    [
      name: "gql_builder",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bsanyi/gql"},
      maintainers: ["bsanyi"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.40.0", only: :dev, runtime: false},
      {:makeup_graphql, ">= 0.0.0", only: :dev, runtime: false},
      {:absinthe, ">= 0.0.0"}
    ]
  end
end
