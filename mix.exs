defmodule Intercom.MixProject do
  use Mix.Project

  def project do
    [
      app: :intercom,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:dialyxir, "1.0.0-rc.4", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.0"},
      {:hackney, "~> 1.15"},
      {:uri_query, "~> 0.1.2"}
    ]
  end
end
