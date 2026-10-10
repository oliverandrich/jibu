defmodule Jibu.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/oliverandrich/jibu"

  def project do
    [
      app: :jibu,
      version: @version,
      # ExSlop requires 1.18. One floor serves consumers and the development checks.
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Jibu",
      description: "A thin client for the Anthropic API, built on Req.",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  # Both aliases end in `mix test`, which refuses to run outside the test environment.
  def cli do
    [preferred_envs: [precommit: :test, build_and_test: :test]]
  end

  def application do
    []
  end

  # `credo/` holds this repository's own Credo checks; they never ship.
  defp elixirc_paths(:test), do: ["lib", "test/support", "credo"]
  defp elixirc_paths(:dev), do: ["lib", "credo"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # 0.5.9 accepts File.Stream and enumerables in `:form_multipart`.
      {:req, ">= 0.5.9 and < 1.0.0"},
      {:telemetry, "~> 1.0"},
      {:mime, "~> 2.0"},
      # Req.Test needs Plug, which Req only declares as optional.
      {:plug, "~> 1.16", only: :test},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.4", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.5.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Changelog" => "https://hexdocs.pm/jibu/changelog.html"},
      files: ~w(lib docs .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  @guides ~w(docs/getting-started.md docs/structured-output.md docs/prompt-caching.md docs/files.md
             docs/batches.md docs/tools.md docs/errors.md)

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md"] ++ @guides ++ ["CHANGELOG.md", {"LICENSE", title: "License"}],
      groups_for_extras: [Guides: @guides, About: ["CHANGELOG.md", "LICENSE"]],
      # `credo/` compiles in dev, so its checks would otherwise appear as public modules.
      filter_modules: fn module, _metadata ->
        not String.starts_with?(inspect(module), "Jibu.Credo.")
      end,
      groups_for_modules: [
        Client: [Jibu, Jibu.Response, Jibu.Error],
        Content: [Jibu.Content, Jibu.Files],
        Endpoints: [Jibu.Models, Jibu.Batches],
        Tools: [Jibu.Tools]
      ]
    ]
  end

  defp aliases do
    [
      # The floor CI leg runs `build_and_test` only: a formatter or Credo release judges style
      # against the toolchain the tree was written with.
      style: ["format --check-formatted", "deps.unlock --check-unused", "credo --strict"],
      build_and_test: ["compile --warnings-as-errors", "test --warnings-as-errors"],
      precommit: ["style", "build_and_test"]
    ]
  end
end
