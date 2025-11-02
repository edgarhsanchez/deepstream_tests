#!/bin/bash

# Test script for draw_rect project with CUDA rectangle drawing

RTSP_INPUT="${RTSP_URL:-rtsp://172.20.96.1:8554/live}"
RTSP_OUTPUT_PORT="${RTSP_OUTPUT_PORT:-8558}"
OUTPUT_WIDTH="${OUTPUT_WIDTH:-1280}"
OUTPUT_HEIGHT="${OUTPUT_HEIGHT:-720}"

echo "========================================"
echo "Draw Rectangles with CUDA on RTSP Stream"
echo "  Input:  $RTSP_INPUT"
echo "  Output: rtsp://localhost:$RTSP_OUTPUT_PORT/draw-rect"
echo "  Size:   ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"
echo "========================================"
echo ""
echo "To view the stream, run in another terminal:"
echo "  ffplay rtsp://localhost:$RTSP_OUTPUT_PORT/draw-rect"
echo "  or: vlc rtsp://localhost:$RTSP_OUTPUT_PORT/draw-rect"
echo ""

# Check if library needs to be built
if [ ! -f "draw_rect/libcuda_draw.so" ]; then
    echo "Building CUDA library..."
    echo "Note: Using CUDA container for compilation (requires CUDA toolkit)"
    
    docker run --rm \
      --gpus all \
      -v $(pwd)/draw_rect:/workdir \
      -w /workdir \
      nvidia/cuda:12.6.0-devel-ubuntu22.04 \
      bash -c "apt-get update -qq && apt-get install -y -qq make && make"
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to build CUDA library"
        echo "You can also build manually with: cd draw_rect && make"
        exit 1
    fi
    echo "✓ CUDA library built successfully"
    echo ""
fi

echo "Running draw_rect with RTSP output..."
docker run --rm -it \
  --gpus all \
  -v $(pwd)/draw_rect:/workdir \
  -w /workdir \
  --network host \
  -e RTSP_URL="$RTSP_INPUT" \
  -e RTSP_OUTPUT_PORT="$RTSP_OUTPUT_PORT" \
  -e OUTPUT_WIDTH="$OUTPUT_WIDTH" \
  -e OUTPUT_HEIGHT="$OUTPUT_HEIGHT" \
  nvcr.io/nvidia/deepstream:8.0-samples-multiarch \
  python3 draw_rect.py \
    --input "$RTSP_INPUT" \
    --port "$RTSP_OUTPUT_PORT" \
    --width "$OUTPUT_WIDTH" \
    --height "$OUTPUT_HEIGHT"
