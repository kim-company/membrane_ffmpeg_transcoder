defmodule Membrane.FFmpeg.Transcoder.BinTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  @crf 26

  @input_path "test/fixtures/samples_big-buck-bunny_bun33s_720x480.h264"

  @outputs [
    # uhd: [
    #   resolution: {3840, 2160},
    #   bitrate: 12_800_000,
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
      bitrate: 6_500_000,
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
      bitrate: 3_300_000,
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
      bitrate: 1_200_000,
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
      bitrate: 200_000,
      profile: :baseline,
      fps: 15,
      gop_size: 30,
      b_frames: 0,
      crf: @crf,
      preset: :veryfast,
      tune: :zerolatency
    ]
  ]

  @tag :tmp_dir
  test "transcodes an input video into multiple qualities", %{tmp_dir: tmp_dir} do
    spec =
      [
        child(:source, %Membrane.File.Source{
          location: @input_path
        })
        |> child(:parser, %Membrane.H264.Parser{output_stream_structure: :annexb})
        |> child(:transcoder, Membrane.FFmpeg.Transcoder.Bin)
      ] ++
        Enum.map(@outputs, fn {id, opts} ->
          get_child(:transcoder)
          |> via_out(:output, options: opts)
          |> child({:parser, id}, %Membrane.H264.Parser{
            output_stream_structure: :avc1
          })
          # We're outputing it into mp4 to onbtain all stream information
          # with ffprobe.
          |> child({:muxer, id}, %Membrane.MP4.Muxer.ISOM{
            fast_start: true
          })
          |> child({:sink, id}, %Membrane.File.Sink{location: "#{tmp_dir}/#{id}.mp4"})
        end)

    pid = Membrane.Testing.Pipeline.start_link_supervised!(spec: spec)

    @outputs
    |> Enum.each(fn {id, opts} ->
      assert_end_of_stream(pid, {:sink, ^id}, :input, 60_000)
      assert_stream_properties("#{tmp_dir}/#{id}.mp4", opts)
    end)
  end

  defp assert_stream_properties(path, opts) do
    props =
      Exile.stream!(~w(ffprobe -show_streams -of json #{path}), stderr: :disable)
      |> Enum.into(<<>>)
      |> Jason.decode!(keys: :atoms)

    assert [stream] = props.streams

    assert {stream.width, stream.height} == opts[:resolution]

    # Instead of matching directly we use this for baseline profile, which in
    # ffmpeg results in "Contrained Baseline".
    expected_profile = opts[:profile] |> to_string |> String.capitalize()
    assert String.contains?(stream.profile, expected_profile)
    assert stream.codec_name == "h264"
    assert String.to_integer(stream.bit_rate) <= opts[:bitrate]

    [num, den] =
      stream.avg_frame_rate
      |> String.split("/")
      |> Enum.map(&String.to_integer/1)

    have_framerate = num / den
    assert_in_delta have_framerate, opts[:fps], 0.1
  end
end
