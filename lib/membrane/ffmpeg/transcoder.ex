defmodule Membrane.FFmpeg.Transcoder do
  use Membrane.Bin

  require Membrane.Logger

  # FFmpeg always puts the first MPEGTS stream at this index,
  # the other ones follow.
  @mpeg_ts_sid_index_offset 256

  def_input_pad(:input,
    accepted_format:
      %Membrane.RemoteStream{content_format: content_format}
      when content_format in [nil, Membrane.FLV]
  )

  def_output_pad(:audio,
    accepted_format: Membrane.RemoteStream,
    availability: :on_request,
    options: [
      bitrate: [
        spec: pos_integer(),
        description: "Maximum bitrate"
      ],
      sample_rate: [
        spec: pos_integer(),
        default: 48_000
      ]
    ]
  )

  def_output_pad(:video,
    accepted_format: Membrane.RemoteStream,
    availability: :on_request,
    options: [
      resolution: [
        spec: {integer(), integer()},
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
      |> child(:demuxer, Membrane.MPEG.TS.Demuxer)
    ]

    {[spec: spec], %{sid_to_pad: %{}}}
  end

  @impl true
  def handle_pad_added(_pad, ctx, _state) when ctx.playback == :playing,
    do:
      raise(
        "New pads can be added to #{inspect(__MODULE__)} only before playback transition to :playing"
      )

  def handle_pad_added(pad, ctx, state) do
    sid = Enum.count(state.sid_to_pad) + @mpeg_ts_sid_index_offset

    spec = [
      # Pad needs to be attached straight away. We use a funnel to allow the
      # playlist to go to playing state, su we can let the demuxer find the pmt
      # table and connect the everything.
      child({:funnel, sid}, Membrane.Funnel)
      |> bin_output(pad)
    ]

    actions =
      [
        spec: spec,
        notify_child: {:transcoder, {:stream_added, {Pad.name_by_ref(pad), sid}, ctx.pad_options}}
      ]

    state = put_in(state, [:sid_to_pad, sid], pad)
    {actions, state}
  end

  @impl true
  def handle_child_notification(
        {:mpeg_ts_pmt, pmt = %MPEG.TS.PMT{streams: streams}},
        :demuxer,
        _ctx,
        state
      ) do
    Membrane.Logger.debug("PMT table received: #{inspect(pmt)}")
    # We expect a stream in the PMT for each pad attached.
    actions =
      state.sid_to_pad
      |> Enum.map(fn {sid, _pad} ->
        _info = Map.fetch!(streams, sid)

        spec = [
          get_child(:demuxer)
          |> via_out(Pad.ref(:output, {:stream_id, sid}))
          |> get_child({:funnel, sid})
        ]

        {:spec, spec}
      end)

    {actions, state}
  end
end
