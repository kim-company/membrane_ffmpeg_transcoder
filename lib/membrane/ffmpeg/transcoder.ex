defmodule Membrane.FFmpeg.Transcoder do
  use Membrane.Bin

  def_input_pad(:input,
    accepted_format: Membrane.H264
  )

  def_output_pad(:output,
    accepted_format: Membrane.RemoteStream,
    availability: :on_request,
    options: [
      resolution: [
        spec: {pos_integer(), pos_integer()},
        description: "Resolution of the given output."
      ],
      bitrate: [
        spec: pos_integer(),
        description: "Maximum bitrate"
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
    spec = [
      bin_input()
      |> child(:transcoder, Membrane.FFmpeg.Transcoder.Filter)
    ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_pad_added(_pad, ctx, _state) when ctx.playback == :playing,
    do:
      raise(
        "New pads can be added to #{inspect(__MODULE__)} only before playback transition to :playing"
      )

  def handle_pad_added(pad, ctx, state) do
    id = Enum.count(ctx.pads)

    spec = [
      # Pad needs to be attached straight away. We use a funnel to allow the
      # playlist to go to playing state, su we can let the demuxer find the pmt
      # table and connect the everything.
      child({:funnel, id}, Membrane.Funnel)
      |> bin_output(pad),
      get_child(:transcoder)
      |> via_out(:output, options: Keyword.new(ctx.pad_options))
      |> child({:demuxer, id}, Membrane.MPEG.TS.Demuxer)
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(
        {:mpeg_ts_pmt, %MPEG.TS.PMT{streams: streams}},
        {:demuxer, id},
        _ctx,
        state
      ) do
    {sid, _} = Enum.find(streams, fn {_, x} -> x.stream_type == :H264 end)

    spec = [
      get_child({:demuxer, id})
      |> via_out(Pad.ref(:output, {:stream_id, sid}))
      |> get_child({:funnel, id})
    ]

    {[spec: spec], state}
  end
end
