defmodule Membrane.FFmpeg.TranscoderTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  require Membrane.Pad
  import Membrane.Testing.Assertions

  @crf 26

  @input_path "test/fixtures/av-sync-test.flv"

  @video_outputs [
    fhd: [
      resolution: {-2, 1080},
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
      resolution: {-2, 720},
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
      resolution: {-2, 360},
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
      resolution: {-2, 234},
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

  @audio_outputs [
    hd: [
      bitrate: 98_000
    ],
    fhd: [
      bitrate: 128_000
    ]
  ]

  @tag :tmp_dir
  test "transcodes an input video into multiple qualities", %{tmp_dir: tmp_dir} do
    spec =
      [
        child(:source, %Membrane.File.Source{
          location: @input_path
        })
        |> child(:transcoder, Membrane.FFmpeg.Transcoder)
      ] ++
        Enum.map(@audio_outputs, fn {id, opts} ->
          id = "a_#{id}"

          get_child(:transcoder)
          |> via_out(:audio, options: opts)
          |> child({:parser, id}, %Membrane.AAC.Parser{
            out_encapsulation: :none,
            output_config: :esds
          })
          |> child({:muxer, id}, %Membrane.MP4.Muxer.ISOM{
            fast_start: true
          })
          |> child({:sink, id}, %Membrane.File.Sink{location: "#{tmp_dir}/#{id}.mp4"})
        end) ++
        Enum.map(@video_outputs, fn {id, opts} ->
          id = "v_#{id}"

          get_child(:transcoder)
          |> via_out(:video, options: opts)
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

    @video_outputs
    |> Enum.each(fn {id, opts} ->
      id = "v_#{id}"
      assert_end_of_stream(pid, {:sink, ^id}, :input, 60_000)
      assert_video_properties("#{tmp_dir}/#{id}.mp4", opts)
    end)

    @audio_outputs
    |> Enum.each(fn {id, opts} ->
      id = "a_#{id}"
      assert_end_of_stream(pid, {:sink, ^id}, :input, 60_000)
      assert_audio_properties("#{tmp_dir}/#{id}.mp4", opts)
    end)
  end

  defp assert_video_properties(path, opts) do
    props =
      Exile.stream!(~w(ffprobe -show_streams -of json #{path}), stderr: :disable)
      |> Enum.into(<<>>)
      |> Jason.decode!(keys: :atoms)

    assert [stream] = props.streams
    {_width, height} = opts[:resolution]
    assert stream.height == height

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

  defp assert_audio_properties(path, opts) do
    props =
      Exile.stream!(~w(ffprobe -show_streams -of json #{path}), stderr: :disable)
      |> Enum.into(<<>>)
      |> Jason.decode!(keys: :atoms)

    assert [stream] = props.streams
    assert stream.codec_name == "aac"
    assert String.to_integer(stream.bit_rate) <= opts[:bitrate]
  end
end
