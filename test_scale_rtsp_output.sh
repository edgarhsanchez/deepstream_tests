#!/bin/bash

################################################################################
# test_scale_rtsp_output.sh
# 
# Test script for DeepStream scale application with RTSP input/output
# Scales an RTSP video stream and outputs to a new RTSP server
#
# USAGE:
#   ./test_scale_rtsp_output.sh [INPUT_URL] [WIDTH] [HEIGHT] [OUTPUT_URL]
#
# PARAMETERS:
#   INPUT_URL   - RTSP source stream URL (default: rtsp://172.20.96.1:8554/live)
#   WIDTH       - Output video width in pixels (default: 1920)
#   HEIGHT      - Output video height in pixels (default: 1080)
#   OUTPUT_URL  - RTSP output server URL (default: rtsp://localhost:8557/ds-scale)
#                 Port is automatically extracted from URL
#
# EXAMPLES:
#   # Use all defaults (1920x1080)
#   ./test_scale_rtsp_output.sh
#
#   # Scale to 720p
#   ./test_scale_rtsp_output.sh rtsp://172.20.96.1:8554/live 1280 720
#
#   # Scale to 640x480 with custom output URL
#   ./test_scale_rtsp_output.sh rtsp://172.20.96.1:8554/live 640 480 rtsp://localhost:8557/scaled
#
#   # Scale to 4K
#   ./test_scale_rtsp_output.sh rtsp://172.20.96.1:8554/live 3840 2160
#
# VIEWING THE OUTPUT:
#   ffplay rtsp://localhost:8557/ds-scale
#   vlc rtsp://localhost:8557/ds-scale
#
# FEATURES:
#   - GPU-accelerated scaling (NVIDIA nvvideoconvert)
#   - High-quality interpolation (method=5)
#   - Zero-copy GPU processing (NVMM memory)
#   - Supports scale up or scale down
#   - H.264 encoding at 4Mbps bitrate
#   - Automatic port extraction from URLs
#
# NOTES:
#   - Input video is STRETCHED to exact dimensions (not aspect-ratio preserving)
#   - To maintain aspect ratio, calculate matching dimensions
#   - Requires DeepStream 8.0+ container with GPU support
#   - Port must be unique (not conflicting with other RTSP servers)
#
################################################################################

# Default values
DEFAULT_RTSP_URL="rtsp://172.20.96.1:8554/live"
DEFAULT_WIDTH="1920"
DEFAULT_HEIGHT="1080"
DEFAULT_OUTPUT_URL="rtsp://localhost:8557/ds-scale"

# Get parameters from command line or environment variables
RTSP_URL="${1:-${RTSP_URL:-$DEFAULT_RTSP_URL}}"
OUTPUT_WIDTH="${2:-${OUTPUT_WIDTH:-$DEFAULT_WIDTH}}"
OUTPUT_HEIGHT="${3:-${OUTPUT_HEIGHT:-$DEFAULT_HEIGHT}}"
OUTPUT_URL="${4:-${RTSP_OUTPUT_URL:-$DEFAULT_OUTPUT_URL}}"

# Extract port from output URL (e.g., rtsp://localhost:8557/path -> 8557)
if [[ "$OUTPUT_URL" =~ :([0-9]+)/ ]]; then
    RTSP_OUTPUT_PORT="${BASH_REMATCH[1]}"
elif [[ "$OUTPUT_URL" =~ :([0-9]+)$ ]]; then
    RTSP_OUTPUT_PORT="${BASH_REMATCH[1]}"
else
    # If no port in URL, assume default RTSP port or extract from default
    RTSP_OUTPUT_PORT="8557"
fi

echo "========================================"
echo "DeepStream Scale - RTSP to RTSP"
echo "  Input:  $RTSP_URL"
echo "  Output: $OUTPUT_URL"
echo "  Size:   ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"
echo "  Port:   $RTSP_OUTPUT_PORT"
echo "========================================"
echo ""
echo "This will:"
echo "  1. Connect to RTSP input stream"
echo "  2. Scale to ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"
echo "  3. Stream via RTSP server on port $RTSP_OUTPUT_PORT"
echo ""
echo "To view the scaled stream:"
echo "  ffplay $OUTPUT_URL"
echo "  or: vlc $OUTPUT_URL"
echo ""

echo "Building scale binary..."
docker run --rm \
  -v $(pwd)/scale:/workdir \
  -w /workdir \
  deepstream-rust-builder:latest \
  cargo build --release

echo ""
echo "Running scale with RTSP output..."
docker run --rm -it \
  --gpus all \
  -v $(pwd)/scale:/workdir \
  -w /workdir \
  --network host \
  -e RTSP_URL="$RTSP_URL" \
  -e OUTPUT_WIDTH="$OUTPUT_WIDTH" \
  -e OUTPUT_HEIGHT="$OUTPUT_HEIGHT" \
  -e RTSP_OUTPUT=true \
  -e RTSP_OUTPUT_PORT="$RTSP_OUTPUT_PORT" \
  -e SHOW_DISPLAY=false \
  deepstream-rust-builder:latest \
  /workdir/target/release/scale
