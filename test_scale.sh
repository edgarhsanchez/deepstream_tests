#!/bin/bash

# Test script for scale application
# This will scale video and stream via RTP/UDP multicast

# Default values
DEFAULT_DEVICE="test"
DEFAULT_WIDTH="1920"
DEFAULT_HEIGHT="1080"
DEFAULT_PORT="5000"

# Get parameters from command line or environment variables
INPUT_DEVICE="${1:-${GST_DEVICE:-$DEFAULT_DEVICE}}"
OUTPUT_WIDTH="${2:-${OUTPUT_WIDTH:-$DEFAULT_WIDTH}}"
OUTPUT_HEIGHT="${3:-${OUTPUT_HEIGHT:-$DEFAULT_HEIGHT}}"
RTSP_PORT="${4:-${RTSP_PORT:-$DEFAULT_PORT}}"

# Determine input type for display
INPUT_TYPE="test pattern"
if [[ "$INPUT_DEVICE" == rtsp://* ]] || [[ "$INPUT_DEVICE" == http://* ]]; then
    INPUT_TYPE="network stream"
elif [[ "$INPUT_DEVICE" == *.mp4 ]] || [[ "$INPUT_DEVICE" == *.avi ]] || [[ "$INPUT_DEVICE" == *.mkv ]]; then
    INPUT_TYPE="video file"
elif [[ "$INPUT_DEVICE" == /dev/video* ]]; then
    INPUT_TYPE="camera device"
fi

echo "========================================"
echo "DeepStream Scale with UDP/RTP Output"
echo "  Input:  $INPUT_DEVICE ($INPUT_TYPE)"
echo "  Output: UDP multicast stream"
echo "  Size:   ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"
echo "  Port:   $RTSP_PORT"
echo "========================================"
echo ""
echo "To view the stream, run in another terminal:"
echo "  VLC: Media -> Open Network Stream -> udp://@224.1.1.1:$RTSP_PORT"
echo "  ffplay: ffplay udp://224.1.1.1:$RTSP_PORT"
echo ""
echo "Building scale binary..."
docker run --rm \
  -v $(pwd)/scale:/workdir \
  -w /workdir \
  deepstream-rust-builder:latest \
  cargo build --release

echo ""
echo "Running scale application..."
docker run --rm -it \
  --gpus all \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v $(pwd)/scale:/workdir \
  -w /workdir \
  --network host \
  -e GST_DEVICE="$INPUT_DEVICE" \
  -e OUTPUT_WIDTH="$OUTPUT_WIDTH" \
  -e OUTPUT_HEIGHT="$OUTPUT_HEIGHT" \
  -e RTSP_PORT="$RTSP_PORT" \
  deepstream-rust-builder:latest \
  /workdir/target/release/scale
