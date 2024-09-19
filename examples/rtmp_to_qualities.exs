Mix.install([
  :membrane_core,
  :membrane_file_plugin,
  :membrane_mp4_plugin,
  :membrane_realtimer_plugin,
  :membrane_h26x_plugin,
  :membrane_rtmp_plugin,
  :membrane_tee_plugin,
  {:membrane_ffmpeg_transcoder_plugin, [path: "../"]}
])

defmodule ExamplePipeline do
  use Membrane.Pipeline

  @crf 23

  @outputs [
    # uhd: [
    #   resolution: {3840, 2160},
    #   profile: :high,
    #   fps: 30,
    #   gop_size: 60,
    #   b_frames: 2,
    #   crf: 29,
    #   preset: :veryfast,
    #   tune: :zerolatency
    # ],
    fhd: [
      resolution: {1920, 1080},
      profile: :high,
      fps: 30,
      gop_size: 60,
      b_frames: 3,
      crf: @crf,
      preset: :veryfast,
      tune: :zerolatency
    ],
    hd: [
      resolution: {1280, 720},
      profile: :high,
      fps: 30,
      gop_size: 60,
      b_frames: 3,
      crf: @crf,
      preset: :veryfast,
      tune: :zerolatency
    ],
    sd: [
      resolution: {640, 360},
      profile: :main,
      fps: 15,
      gop_size: 30,
      b_frames: 3,
      crf: @crf,
      preset: :veryfast,
      tune: :zerolatency

    ],
    mobile: [
      resolution: {416, 234},
      profile: :baseline,
      fps: 15,
      gop_size: 30,
      b_frames: 0,
      crf: @crf,
      preset: :veryfast,
      tune: :zerolatency
    ]
  ]

  @impl true
  def handle_init(_ctx, _opts) do
    File.rm_rf("output")
    File.mkdir("output")

    spec =
      [
        child(:source, %Membrane.RTMP.SourceBin{url: "rtmp://0.0.0.0:1935/app/stream_key"})
        |> via_out(:video)
        |> child(:parser, %Membrane.H264.Parser{output_stream_structure: :annexb})
        |> child(:tee, Membrane.Tee.Parallel),
        # Video to transcoder
        get_child(:tee)
        |> child(:transcoder, Membrane.FFmpeg.Transcoder),
        # Original video
        get_child(:tee)
        |> child({:sink, :original}, %Membrane.File.Sink{location: "output/original.h264"}),
        # Audio
        get_child(:source)
        |> via_out(:audio)
        |> child(:sink_audio, Membrane.Debug.Sink)
      ] ++
        Enum.map(@outputs, fn {id, opts} ->
          get_child(:transcoder)
          |> via_out(:output, options: opts)
          # |> child({:parser, id}, %Membrane.H264.Parser{output_stream_structure: :avc1})
          |> child({:sink, id}, %Membrane.File.Sink{location: "output/#{id}.h264"})
          # |> child({:sink, id}, %Membrane.Debug.Sink{
          #   handle_stream_format: &IO.inspect/1
          #   # handle_buffer: &IO.inspect(&1, label: inspect(id))
          # })
        end)

    {[spec: spec], %{children_with_eos: MapSet.new()}}
  end

  @impl true
  def handle_element_end_of_stream(element, _pad, _ctx, state) do
    state = %{state | children_with_eos: MapSet.put(state.children_with_eos, element)}

    IO.inspect element

    sinks = Enum.map(@outputs, fn {id, _opts} -> {:sink, id} end) ++ [{:sink, :original}]

    actions =
      if Enum.all?(sinks, &(&1 in state.children_with_eos)),
        do: [terminate: :shutdown],
        else: []

    {actions, state}
  end
end

IO.puts "🚀 Starting RTMP server on rtmp://0.0.0.0:1935/app/stream_key"

# Start and monitor the pipeline
{:ok, _supervisor_pid, pipeline_pid} = Membrane.Pipeline.start_link(ExamplePipeline)
ref = Process.monitor(pipeline_pid)

# Wait for the pipeline to finish
receive do
  {:DOWN, ^ref, :process, _pipeline_pid, _reason} ->
    :ok
end
