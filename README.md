# Membrane.FFmpeg.Transcoder
Membrane plugin to transcode video into different qualities using FFmpeg and Exile.

## Requirements
- ffmpeg
- named pipes (mkfifo)

## Usage
Put `Membrane.FFmpeg.Transcoder` somewhere in your pipeline.

## Features
- buffers come with pts and dts values
- same performance as ffmpeg
- simple API: attach an output with options, that's it (check the test)
- constrains the bitrate
- by adding a Membrane.h264.Parser in the middle, it is compatible with Membrane.MP4.Muxer.CMAF and Membrane.MP4.Muxer.ISOM

## Copyright and License
Copyright 2024, [KIM Keep In Mind GmbH](https://www.keepinmind.info/)
Licensed under the [Apache License, Version 2.0](LICENSE)

