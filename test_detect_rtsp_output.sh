#!/bin/bash

# Test script for detect with RTSP output
# This will stream the detected video with bounding boxes to an RTSP server

MODEL_CONFIG_PATH="${MODEL_CONFIG:-/models/config_infer_yolo11n.txt}"
DETECT_TARGET="${1:-person}"
RTSP_INPUT="${RTSP_URL:-rtsp://172.20.96.1:8554/live}"
RTSP_OUTPUT_PORT="${RTSP_OUTPUT_PORT:-8555}"
OUTPUT_WIDTH="${OUTPUT_WIDTH:-1280}"
OUTPUT_HEIGHT="${OUTPUT_HEIGHT:-720}"

# Extract model name from config path
MODEL_NAME=$(basename "$MODEL_CONFIG_PATH" | sed 's/config_infer_//' | sed 's/.txt//')

echo "========================================"
echo "DeepStream Detection with RTSP Stream Output"
echo "  Object: $DETECT_TARGET"
echo "  Input:  $RTSP_INPUT"
echo "  Output: rtsp://localhost:$RTSP_OUTPUT_PORT/ds-detect"
echo "  Size:   ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"
echo "  Model:  $MODEL_NAME (80 COCO classes)"
echo "  Config: $MODEL_CONFIG_PATH"
echo "========================================"
echo ""
echo "To view the stream, run in another terminal:"
echo "  ffplay rtsp://localhost:$RTSP_OUTPUT_PORT/ds-detect"
echo "  or: vlc rtsp://localhost:$RTSP_OUTPUT_PORT/ds-detect"
echo ""

echo "Building detect binary..."
docker run --rm \
  -v $(pwd)/detect:/workdir \
  -w /workdir \
  deepstream-rust-builder:latest \
  cargo build --release

echo ""
echo "Running detect with RTSP output..."
docker run --rm -it \
  --gpus all \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v $(pwd)/detect:/workdir \
  -v $(pwd)/models:/models \
  -v $(pwd)/deepstream-yolo:/workspace/deepstream-yolo \
  -w /workdir \
  --network host \
  -e MODEL_CONFIG="$MODEL_CONFIG_PATH" \
  -e DETECT_OBJECT="$DETECT_TARGET" \
  -e RTSP_URL="$RTSP_INPUT" \
  -e RTSP_OUTPUT="enabled" \
  -e RTSP_OUTPUT_PORT="$RTSP_OUTPUT_PORT" \
  -e OUTPUT_WIDTH="$OUTPUT_WIDTH" \
  -e OUTPUT_HEIGHT="$OUTPUT_HEIGHT" \
  -e SHOW_DISPLAY=false \
  deepstream-rust-builder:latest \
  /workdir/target/release/detect
