#!/usr/bin/env bash
# compile_yolo_parser.sh - Compile the DeepStream YOLO custom parser inside the container

set -eu -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_TAG="deepstream-rust-builder:latest"

echo "========================================"
echo "Compiling DeepStream YOLO Parser"
echo "========================================"

# Check if the parser is already compiled
if [ -f "${SCRIPT_DIR}/deepstream-yolo/nvdsinfer_custom_impl_Yolo/libnvdsinfer_custom_impl_Yolo.so" ]; then
  echo "Parser library already exists, skipping compilation."
  exit 0
fi

# Compile inside the container
docker run --rm \
  -v "${SCRIPT_DIR}/deepstream-yolo":/workspace/deepstream-yolo \
  -w /workspace/deepstream-yolo/nvdsinfer_custom_impl_Yolo \
  "${DOCKER_TAG}" bash -c "make clean && make"

if [ -f "${SCRIPT_DIR}/deepstream-yolo/nvdsinfer_custom_impl_Yolo/libnvdsinfer_custom_impl_Yolo.so" ]; then
  echo "Parser compiled successfully!"
else
  echo "ERROR: Parser compilation failed!"
  exit 1
fi
