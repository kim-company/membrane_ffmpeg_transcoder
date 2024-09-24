defmodule Membrane.FFmpeg.Transcoder.Bin do
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
      |> child(:transcoder, Membrane.FFmpeg.Transcoder)
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
    # id = Enum.count(ctx.pads)

    spec = [
      get_child(:transcoder)
      |> via_out(:output, options: Keyword.new(ctx.pad_options))
      |> bin_output(pad)
      # |> child({:demuxer, id}, Membrane.MP4.Demuxer.ISOM)
      # Audio (ignored)
      # |> via_out(:output, options: [kind: :audio])
      # |> child({:null, id}, Membrane.Debug.Sink),

      # # Video
      # get_child({:demuxer, id})
      # |> via_out(:output, options: [kind: :video])
      # |> bin_output(pad)
    ]

    {[spec: spec], state}
  end
end
