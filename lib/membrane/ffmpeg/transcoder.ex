defmodule Membrane.FFmpeg.Transcoder do
  use Membrane.Filter

  def_input_pad(:input,
    flow_control: :auto,
    accepted_format: Membrane.H264
  )

  def_output_pad(:output,
    flow_control: :auto,
    accepted_format: Membrane.RemoteStream,
    availability: :on_request,
    options: [
      resolution: [
        spec: {pos_integer(), pos_integer()},
        description: "Resolution of the given output."
      ],
      profile: [
        spec: atom(),
        description: "H264 Profile"
      ],
      crf: [
        spec: pos_integer(),
        default: 29
      ],
      preset: [
        spec: atom(),
        default: :high
      ],
      tune: [
        spec: atom(),
        default: :zerolatency
      ],
      fps: [
        spec: pos_integer(),
        default: 30
      ],
      gop_size: [
        spec: pos_integer(),
        default: 60
      ],
      b_frames: [
        spec: pos_integer(),
        default: 3
      ]
    ]
  )

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{ffmpeg: nil}}
  end

  @impl true
  def handle_stream_format(_pad, _stream_format, _ctx, state) do
    {[forward: %Membrane.RemoteStream{content_format: Membrane.MP4}], state}
  end

  @impl true
  def handle_playing(ctx, state) do
    outputs =
      ctx.pads
      |> Map.values()
      |> Enum.filter(&(&1.direction == :output))
      |> Enum.with_index(1)

    tmp_dir = System.tmp_dir!()

    filtergraph =
      [
        "[0:v]split=#{length(outputs)}#{Enum.map(outputs, fn {_output, index} -> "[v#{index}]" end)}",
        Enum.map(outputs, fn {output, index} ->
          opts = output.options
          {w, h} = opts.resolution

          "[v#{index}]fps=#{opts.fps},scale=#{w}:#{h}[v#{index}out]"
        end)
      ]
      |> List.flatten()
      |> Enum.join(";")

    Enum.each(outputs, fn {output, index} ->
      path = Path.join(tmp_dir, "#{index}.pipe")
      File.rm(path)
      {_, 0} = System.cmd("mkfifo", [path])

      # spawn(fn ->
      #   System.cmd("ffplay", [path])
      # end)

      parent = self()

      spawn_link(fn ->
        Exile.stream!(~w(cat #{path}))
        |> Enum.each(fn data ->
          send(parent, {:data, output.ref, data})
        end)
      end)
    end)

    command =
      List.flatten([
        ~w(ffmpeg -y -hide_banner -loglevel error -i - -filter_complex #{filtergraph}),
        Enum.map(outputs, fn {output, index} ->
          opts = output.options

          ~w(-map [v#{index}out] -c:v:#{index - 1} libx264 -preset #{opts.preset} -crf #{opts.crf} -tune #{opts.tune} -profile #{opts.profile} -g #{opts.gop_size} -bf #{opts.b_frames} -f h264 #{Path.join(tmp_dir, "#{index}.pipe")})
        end)
      ])

    {:ok, ffmpeg} = Exile.Process.start_link(command)

    {[], %{state | ffmpeg: ffmpeg}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    :ok = Exile.Process.write(state.ffmpeg, buffer.payload)
    {[], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    Exile.Process.close_stdin(state.ffmpeg)
    Exile.Process.await_exit(state.ffmpeg)
    {[forward: :end_of_stream], state}
  end

  @impl true
  def handle_pad_added(_pad, _context, state) do
    {[], state}
  end

  @impl true
  def handle_info({:data, pad, payload}, _ctx, state) do
    buffer = %Membrane.Buffer{payload: payload}
    {[buffer: {pad, buffer}], state}
  end
end
