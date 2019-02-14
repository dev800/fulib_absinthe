defmodule FulibAbsinthe.MixProject do
  use Mix.Project

  def project do
    [
      app: :fulib_absinthe,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "Lib for elixir",
      source_url: "https://github.com/dev800/fulib_absinthe",
      homepage_url: "https://github.com/dev800/fulib_absinthe",
      package: package(),
      docs: [
        extras: ["README.md"],
        main: "readme"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:absinthe_plug, "~> 1.4"},
      {:fulib, "~> 0.1"},
      {:ex_doc, "~> 0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    %{
      files: ["lib", "priv", "mix.exs", "README.md", "config/config.exs"],
      maintainers: ["happy"],
      licenses: ["BSD 3-Clause"],
      links: %{"Github" => "https://github.com/dev800/fulib_absinthe"}
    }
  end
end
