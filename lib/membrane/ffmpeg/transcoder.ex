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
  def handle_init(ctx, _opts) do
    outputs =
      ctx.pads
      |> Map.values()
      |> Enum.filter(&(&1.direction == :output))
      |> Enum.map(fn x -> x.options end)
      |> IO.inspect(label: "OPTS")

    spec = [
      bin_input(:input)
      |> child(:transcoder, %Membrane.FFmpeg.Transcoder.Filter{
        outputs: outputs
      })
      |> child(:demuxer, Membrane.MPEG.TS.Demuxer)
    ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification({:mpeg_ts_pmt, pmt}, :demuxer, ctx, state) do
    IO.inspect(pmt, label: "PMT TABLE")
    {[], state}
  end
end
