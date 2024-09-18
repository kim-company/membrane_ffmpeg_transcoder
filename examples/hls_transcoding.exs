Mix.install([
  :membrane_core,
  :membrane_file_plugin,
  :membrane_mp4_plugin,
  :membrane_realtimer_plugin,
  :membrane_h26x_plugin,
  {:membrane_ffmpeg_transcoder_plugin, [path: "../"]}
])

defmodule ExamplePipeline do
  use Membrane.Pipeline

  @outputs [
    {3840, 2160},
    {1920, 1080},
    {1280, 720},
    {640, 360},
    {416, 234}
  ]

  @impl true
  def handle_init(_ctx, _opts) do
    spec =
      [
        child(:source, %Membrane.File.Source{
          chunk_size: 40_960,
          location: "~/Documents/Testdata/lg-uhd-LG-Greece-and-Norway.mp4"
        })
        |> child(:demuxer, Membrane.MP4.Demuxer.ISOM)
        |> via_out(:output, options: [kind: :video])
        |> child(:parser, %Membrane.H264.Parser{output_stream_structure: :annexb})
        |> child(:rt, Membrane.Realtimer)
        |> child(:transcoder, Membrane.FFmpeg.Transcoder),
        # Audio
        get_child(:demuxer)
        |> via_out(:output, options: [kind: :audio])
        |> child(:sink_audio, Membrane.Debug.Sink)
      ] ++
        Enum.map(@outputs, fn resolution ->
          get_child(:transcoder)
          |> via_out(:output,
            options: [
              resolution: resolution,
              profile: :baseline,
              crf: 29,
              preset: :veryfast,
              tune: :zerolatency
            ]
          )
          # TODO: Check this out
          # |> child({:parser, resolution}, Membrane.H264.Parser)
          |> child({:sink, resolution}, %Membrane.Debug.Sink{
            handle_buffer: &IO.inspect(&1, label: inspect(resolution))
          })
        end)

    {[spec: spec], %{children_with_eos: MapSet.new()}}
  end

  @impl true
  def handle_element_end_of_stream(element, _pad, _ctx, state) do
    state = %{state | children_with_eos: MapSet.put(state.children_with_eos, element)}

    sinks = Enum.map(@outputs, &{:sink, &1})

    actions =
      if Enum.all?(sinks, &(&1 in state.children_with_eos)),
        do: [terminate: :shutdown],
        else: []

    {actions, state}
  end
end

# Start and monitor the pipeline
{:ok, _supervisor_pid, pipeline_pid} = Membrane.Pipeline.start_link(ExamplePipeline)
ref = Process.monitor(pipeline_pid)

# Wait for the pipeline to finish
receive do
  {:DOWN, ^ref, :process, _pipeline_pid, _reason} ->
    :ok
end
