defmodule MembraneFFmpegTranscoder.MixProject do
  use Mix.Project

  @github_url "https://github.com/kim-company/membrane_ffmpeg_transcoder_plugin"

  def project do
    [
      app: :membrane_ffmpeg_transcoder_plugin,
      version: "1.1.3",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      source_url: @github_url,
      name: "Membrane FFmpeg Transcoder Plugin",
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  defp package do
    [
      maintainers: ["KIM Keep In Mind"],
      files: ~w(lib mix.exs README.md LICENSE),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @github_url}
    ]
  end

  defp description do
    """
    Membrane plugin to transcode video into different qualities using FFmpeg and Exile.
    """
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
      {:membrane_core, "~> 1.1"},
      {:membrane_h264_format, "~> 0.6.0"},
      {:membrane_funnel_plugin, "~> 0.9.0"},
      {:membrane_mpeg_ts_plugin, "~> 1.0"},
      {:membrane_flv_plugin, "~> 0.12.0"},

      #
      {:exile, "~> 0.11.0"},

      #
      {:membrane_file_plugin, ">= 0.0.0", only: :test},
      {:membrane_h26x_plugin, ">= 0.0.0", only: :test},
      {:membrane_mp4_plugin, ">= 0.0.0", only: :test},
      {:membrane_aac_plugin, ">= 0.0.0", only: :test},
      {:jason, ">= 0.0.0", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
