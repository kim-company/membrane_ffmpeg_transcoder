defmodule Membrane.FFmpeg.Transcoder.Filter do
  use Membrane.Filter

  defmodule FFmpegError do
    defexception [:message]

    @impl true
    def exception(value) do
      %FFmpegError{message: "FFmpeg error: #{inspect(value)}"}
    end
  end

  def_input_pad(:input,
    flow_control: :auto,
    accepted_format: Membrane.H264
  )

  def_output_pad(:output,
    flow_control: :auto,
    accepted_format: Membrane.RemoteStream
  )

  def_options(
    outputs: [
      spec: :any,
      description:
        "List of output specs. They will be produced and muxed into a single mpeg-ts stream"
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{ffmpeg: nil, outputs: opts.outputs, read_task: nil}}
  end

  @impl true
  def handle_stream_format(_pad, _stream_format, _ctx, state) do
    {[forward: %Membrane.RemoteStream{}], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    IO.inspect("SETTING UP FFMPEG")

    outputs =
      state.outputs
      |> Enum.map(fn x -> Map.new(x) end)
      |> Enum.with_index(1)

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

    mappings =
      Enum.flat_map(outputs, fn {output, index} ->
        opts = output.options

        ~w(
            -map
            [v#{index}out]
            -c:v:#{index - 1}
            libx264
            -preset #{opts.preset}
            -crf #{opts.crf}
            -tune #{opts.tune}
            -profile #{opts.profile}
            -g #{opts.gop_size}
            -bf #{opts.b_frames}
          )
      end)

    command = ~w(
          ffmpeg -y -hide_banner
          -loglevel error
          -i -
          -filter_complex #{filtergraph}
        ) ++ mappings ++ ~w(-f mpegts -)

    Membrane.Logger.debug("Executing: #{Enum.join(command, " ")}")

    {:ok, ffmpeg} = Exile.Process.start_link(command)

    parent = self()

    read_loop_task =
      Task.async(fn ->
        :ok = Exile.Process.change_pipe_owner(ffmpeg, :stdout, self())
        read_loop(ffmpeg, parent)
      end)

    {[], %{state | ffmpeg: ffmpeg, read_task: read_loop_task}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    IO.inspect(byte_size(buffer.payload), label: "WRITING BUFFER")
    :ok = Exile.Process.write(state.ffmpeg, buffer.payload)
    {[], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    Exile.Process.close_stdin(state.ffmpeg)
    Exile.Process.await_exit(state.ffmpeg)
    # TODO: Read all buffers here?
    {[forward: :end_of_stream], state}
  end

  @impl true
  def handle_info({:exile, {:data, payload}}, _ctx, state) do
    {[buffer: {:output, %Membrane.Buffer{payload: payload}}], state}
  end

  def handle_info({ref, :eof}, _ctx, state) do
    # Avoid receiving the DOWN message.
    Process.demonitor(ref, [:flush])
    {:ok, 0} = Exile.Process.await_exit(state.ffmpeg)
    {[end_of_stream: :output], state}
  end

  def handle_info({_ref, {:error, any}}, _ctx, _state) do
    raise FFmpegError, any
  end

  def handle_info({_ref, {:ok, 0}}, _ctx, state) do
    {[], state}
  end

  defp read_loop(p, parent) do
    try do
      case Exile.Process.read(p) do
        {:ok, data} ->
          send(parent, {:exile, {:data, data}})
          read_loop(p, parent)

        :eof ->
          :eof

        {:error, any} ->
          {:error, any}
      end
    catch
      :exit, _e ->
        :eof
    end
  end
end
