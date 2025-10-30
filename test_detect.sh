#!/usr/bin/env bash
# Quick test script for object detection — run the built binary inside the DeepStream build container

set -eu -o pipefail

# Usage: ./test_detect.sh [object] [rtsp_url]
# Defaults: object=cup, rtsp_url=rtsp://172.20.96.1:8554/live

OBJECT="${1:-cup}"
RTSP_URL="${2:-rtsp://172.20.96.1:8554/live}"
OUTPUT_WIDTH="${3:-1280}"
OUTPUT_HEIGHT="${4:-720}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DOCKER_TAG="deepstream-rust-builder:latest"

# Find the class ID for the target object
CLASS_ID=$(grep -n "^${OBJECT}$" "${SCRIPT_DIR}/models/labels.txt" | head -1 | cut -d: -f1)
if [ -z "$CLASS_ID" ]; then
  echo "ERROR: Object '${OBJECT}' not found in models/labels.txt"
  echo "Available objects:"
  head -20 "${SCRIPT_DIR}/models/labels.txt"
  echo "..."
  exit 1
fi
CLASS_ID=$((CLASS_ID - 1))  # Convert to 0-indexed

# Determine which config to use
MODEL_CONFIG_PATH="${MODEL_CONFIG:-/models/config_infer_yolo11s.txt}"
MODEL_NAME=$(basename "$MODEL_CONFIG_PATH" | sed 's/config_infer_//;s/.txt//')

echo "========================================"
echo "Testing DeepStream Detection (direct container run)"
echo "  Object: ${OBJECT} (class ID: ${CLASS_ID})"
echo "  RTSP:   ${RTSP_URL}"
echo "  Output: ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"
echo "  Model:  ${MODEL_NAME} (80 COCO classes)"
echo "  Config: ${MODEL_CONFIG_PATH}"
echo "========================================"

# Compile the YOLO parser if not already compiled
if [ ! -f "${SCRIPT_DIR}/deepstream-yolo/nvdsinfer_custom_impl_Yolo/libnvdsinfer_custom_impl_Yolo.so" ]; then
  echo "YOLO parser not found — compiling inside container..."
  docker run --rm \
    --gpus all \
    -v "${SCRIPT_DIR}/deepstream-yolo":/workspace/deepstream-yolo \
    -w /workspace/deepstream-yolo/nvdsinfer_custom_impl_Yolo \
    "${DOCKER_TAG}" bash -c "
      # Create symlinks for cublas libraries in CUDA 12.5 (they only have .so.12, not .so)
      cd /usr/local/cuda-12.5/lib64 && \
      ln -sf libcublas.so.12 libcublas.so 2>/dev/null || true && \
      ln -sf libcublasLt.so.12 libcublasLt.so 2>/dev/null || true && \
      cd /workspace/deepstream-yolo/nvdsinfer_custom_impl_Yolo && \
      CUDA_VER=12.5 make clean && \
      CUDA_VER=12.5 make
    "
  
  if [ ! -f "${SCRIPT_DIR}/deepstream-yolo/nvdsinfer_custom_impl_Yolo/libnvdsinfer_custom_impl_Yolo.so" ]; then
    echo "ERROR: Failed to compile YOLO parser!"
    exit 1
  fi
  echo "YOLO parser compiled successfully!"
fi

# Build the Rust binary (rebuild to pick up code changes)
echo "Building detect binary..."
docker run --rm -v "${SCRIPT_DIR}":/workdir -w /workdir \
  "${DOCKER_TAG}" bash -lc "cd detect && source /usr/local/cargo/env || true; cargo build --release"

echo "Running detect inside container (will forward X11)"

# Use MODEL_CONFIG from environment or default to yolo11s
MODEL_CONFIG_PATH="${MODEL_CONFIG:-/models/config_infer_yolo11s.txt}"

docker run --rm -it --gpus all \
  -e DISPLAY="$DISPLAY" \
  -e FILTER_CLASS_ID="$CLASS_ID" \
  -e MODEL_CONFIG="${MODEL_CONFIG_PATH}" \
  -e DETECT_OBJECT="${OBJECT}" \
  -e RTSP_URL="${RTSP_URL}" \
  -e OUTPUT_WIDTH="${OUTPUT_WIDTH}" \
  -e OUTPUT_HEIGHT="${OUTPUT_HEIGHT}" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v "${SCRIPT_DIR}":/workdir \
  -v "${SCRIPT_DIR}/models":/models \
  -v "${SCRIPT_DIR}/deepstream-yolo":/workspace/deepstream-yolo \
  -w /workdir \
  "${DOCKER_TAG}" /workdir/detect/target/release/detect