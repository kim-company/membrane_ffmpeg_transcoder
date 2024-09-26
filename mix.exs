defmodule MembraneFFmpegTranscoder.MixProject do
  use Mix.Project

  def project do
    [
      app: :membrane_ffmpeg_transcoder_plugin,
      version: "0.1.0",
      elixir: "~> 1.15",
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
      {:membrane_core, "~> 1.1"},
      {:membrane_h264_format, "~> 0.6.0"},
      {:membrane_funnel_plugin, "~> 0.9.0"},
      {:membrane_mpeg_ts_plugin, "~> 1.0"},

      #
      {:exile, "~> 0.11.0"},

      #
      {:membrane_file_plugin, ">= 0.0.0", only: :test},
      {:membrane_h26x_plugin, ">= 0.0.0", only: :test},
      {:membrane_mp4_plugin, ">= 0.0.0", only: :test},
      {:jason, ">= 0.0.0", only: :test}
    ]
  end
end
