#!/bin/bash
set -e

# Default values
DEFAULT_OBJECT="person"
DEFAULT_PORT="8556"
DEFAULT_MODEL="yolo11s"

# Get object name from command line or use default
DETECT_OBJECT=${1:-$DEFAULT_OBJECT}
RTSP_OUTPUT_PORT=${2:-$DEFAULT_PORT}

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== DeepStream Python Object Detection with RTSP Output ===${NC}"
echo "Target Object: ${DETECT_OBJECT}"
echo "RTSP Port: ${RTSP_OUTPUT_PORT}"
echo "Model: ${DEFAULT_MODEL}"
echo ""

# Set model config based on model type
if [ "${DEFAULT_MODEL}" = "yolo11n" ]; then
    MODEL_CONFIG="/models/config_infer_yolo11n.txt"
else
    MODEL_CONFIG="/models/config_infer_yolo11s.txt"
fi

# RTSP input URL (can be overridden)
RTSP_URL=${RTSP_URL:-"rtsp://172.20.96.1:8554/live"}

echo -e "${YELLOW}Starting Python detect application...${NC}"
echo "Input: ${RTSP_URL}"
echo "Output: rtsp://localhost:${RTSP_OUTPUT_PORT}/ds-detect"
echo ""
echo "View stream with:"
echo "  ffplay rtsp://localhost:${RTSP_OUTPUT_PORT}/ds-detect"
echo ""
echo "Filtering for object: ${DETECT_OBJECT}"
echo ""

# Run in Docker container
docker run --rm -it \
    --gpus all \
    --net host \
    -v "$(pwd)/..":/workdir \
    -v "$(pwd)/../models":/models \
    -v "$(pwd)/../deepstream-yolo":/workspace/deepstream-yolo \
    -w /workdir \
    -e DETECT_OBJECT="${DETECT_OBJECT}" \
    -e RTSP_URL="${RTSP_URL}" \
    -e MODEL_CONFIG="${MODEL_CONFIG}" \
    -e SHOW_DISPLAY=false \
    -e RTSP_OUTPUT=true \
    -e RTSP_OUTPUT_PORT="${RTSP_OUTPUT_PORT}" \
    -e OUTPUT_WIDTH=1920 \
    -e OUTPUT_HEIGHT=1080 \
    nvcr.io/nvidia/deepstream:8.0-samples-multiarch \
    python3 detect_py/detect.py
