#!/bin/bash

# Test script for draw_rect with PyCUDA (no compilation needed!)

RTSP_INPUT="${RTSP_URL:-rtsp://172.20.96.1:8554/live}"
RTSP_OUTPUT_PORT="${RTSP_OUTPUT_PORT:-8558}"
OUTPUT_WIDTH="${OUTPUT_WIDTH:-1280}"
OUTPUT_HEIGHT="${OUTPUT_HEIGHT:-720}"

echo "========================================"
echo "Draw Rectangles with PyCUDA on RTSP Stream"
echo "  Input:  $RTSP_INPUT"
echo "  Output: rtsp://localhost:$RTSP_OUTPUT_PORT/draw-rect"
echo "  Size:   ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"
echo "  Method: PyCUDA (runtime kernel compilation)"
echo "========================================"
echo ""
echo "To view the stream, run in another terminal:"
echo "  ffplay rtsp://localhost:$RTSP_OUTPUT_PORT/draw-rect"
echo "  or: vlc rtsp://localhost:$RTSP_OUTPUT_PORT/draw-rect"
echo ""

echo "Running draw_rect with C++/CUDA..."
docker run --rm \
  --gpus all \
  -v $(pwd)/draw_rect:/workdir \
  -w /workdir \
  --network host \
  -e RTSP_URL="$RTSP_INPUT" \
  -e RTSP_OUTPUT_PORT="$RTSP_OUTPUT_PORT" \
  -e OUTPUT_WIDTH="$OUTPUT_WIDTH" \
  -e OUTPUT_HEIGHT="$OUTPUT_HEIGHT" \
  draw_rect:latest \
  python3 draw_rect.py --input "$RTSP_INPUT" --port $RTSP_OUTPUT_PORT --width $OUTPUT_WIDTH --height $OUTPUT_HEIGHT
