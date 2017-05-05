defmodule Odo.Mixfile do
  use Mix.Project

  def project do
    [app: :odo,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     package: package(),
     description: description(),
     deps: deps(),
     dialyzer: [ flags: ["-Wunmatched_returns", :error_handling, :underspecs, :unknown]],
     source_url: "https://github.com/nigelsmith/odo"
     ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [
      extra_applications: [:logger],
      mod: {Odo.Application, []}
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:benchfella, "~> 0.3.0", only: [:dev]},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false}
    ]
  end

  defp description do
    """
    Odo is a simple GenServer based token bucket which can be used for communicating with remote APIs.  It lets you know
    when it's safe to proceed, given a particular rate limit.
    """
  end

  defp package do
    [
      licenses: ["Apache 2.0"],
      maintainers: ["Nigel Smith"],
      links: %{"GitHub" => "https://github.com/nigelsmith/odo"}
    ]
  end
end
