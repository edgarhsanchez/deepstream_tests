#!/usr/bin/env bash
# generate_yolo_config.sh - Generate YOLO11 config with class filtering

set -eu -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_OBJECT="${1:-cup}"
OUTPUT_CONFIG="${2:-/tmp/config_infer_yolo11s_filtered.txt}"

# Find the class ID for the target object
CLASS_ID=$(grep -n "^${TARGET_OBJECT}$" "${SCRIPT_DIR}/models/labels.txt" | cut -d: -f1)

if [ -z "$CLASS_ID" ]; then
  echo "ERROR: Object '${TARGET_OBJECT}' not found in labels.txt"
  exit 1
fi

# Class IDs are 0-indexed, so subtract 1
CLASS_ID=$((CLASS_ID - 1))

echo "Generating config for object '${TARGET_OBJECT}' (class ID: ${CLASS_ID})"

# Generate the config file
cat > "${OUTPUT_CONFIG}" << EOF
[property]
gpu-id=0
net-scale-factor=0.0039215697906911373
model-color-format=0
onnx-file=/models/yolo11s.onnx
model-engine-file=/models/yolo11s_b1_gpu0_fp32.engine
labelfile-path=/models/labels.txt
batch-size=1
network-mode=0
num-detected-classes=80
interval=0
gie-unique-id=1
process-mode=1
network-type=0
cluster-mode=2
maintain-aspect-ratio=1
symmetric-padding=1
parse-bbox-func-name=NvDsInferParseYolo
custom-lib-path=/workspace/deepstream-yolo/nvdsinfer_custom_impl_Yolo/libnvdsinfer_custom_impl_Yolo.so
engine-create-func-name=NvDsInferYoloCudaEngineGet

[class-attrs-all]
nms-iou-threshold=0.45
pre-cluster-threshold=0.25
topk=300
# Disable display for all classes by default
roi-top-offset=0
roi-bottom-offset=0
detected-min-w=0
detected-min-h=0
detected-max-w=0
detected-max-h=0

[class-attrs-${CLASS_ID}]
# Enable only the target class
pre-cluster-threshold=0.25
nms-iou-threshold=0.45
detected-min-w=4
detected-min-h=4
detected-max-w=4000
detected-max-h=4000
EOF

echo "Config generated: ${OUTPUT_CONFIG}"
