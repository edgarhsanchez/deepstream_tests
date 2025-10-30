#!/bin/bash

# Export YOLO11 with DeepStream compatibility using Docker with older PyTorch
# Usage: ./export_yolo11_fixed.sh [model.pt] [model_dir]
#   model.pt  - Name of the .pt file (default: yolo11s.pt)
#   model_dir - Directory containing the .pt file (default: /mnt/d/github/ultralytics)

echo "=========================================="
echo "YOLO11 DeepStream Export Script"
echo "=========================================="

# Parse arguments
MODEL_FILE="${1:-yolo11s.pt}"
YOLO_MODEL_DIR="${2:-/mnt/d/github/ultralytics}"
DEEPSTREAM_YOLO_DIR="/mnt/d/github/deepstream_tests/deepstream-yolo"
OUTPUT_DIR="/mnt/d/github/deepstream_tests/models"

# Validate inputs
if [ ! -f "$YOLO_MODEL_DIR/$MODEL_FILE" ]; then
    echo "❌ Error: Model file not found: $YOLO_MODEL_DIR/$MODEL_FILE"
    echo ""
    echo "Usage: $0 [model.pt] [model_dir]"
    echo "  model.pt  - Name of the .pt file (default: yolo11s.pt)"
    echo "  model_dir - Directory containing the .pt file (default: /mnt/d/github/ultralytics)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Export yolo11s.pt from default directory"
    echo "  $0 yolo11m.pt                # Export yolo11m.pt from default directory"
    echo "  $0 custom.pt /path/to/models # Export custom.pt from specific directory"
    exit 1
fi

echo "Model file: $MODEL_FILE"
echo "Model directory: $YOLO_MODEL_DIR"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Use PyTorch 2.4 container which doesn't have the breaking changes
docker run --rm \
  -v "$YOLO_MODEL_DIR":/workspace/ultralytics \
  -v "$DEEPSTREAM_YOLO_DIR":/workspace/deepstream-yolo \
  -v "$OUTPUT_DIR":/workspace/models \
  pytorch/pytorch:2.4.0-cuda12.1-cudnn9-runtime \
  bash -c "
    set -e
    MODEL_FILE='$MODEL_FILE'
    
    echo 'Installing system dependencies...'
    apt-get update -qq && apt-get install -y -qq libgl1 libglib2.0-0 > /dev/null 2>&1
    
    echo 'Installing required packages...'
    pip install --no-cache-dir -q onnx ultralytics
    
    cd /workspace/ultralytics
    echo 'Copying export script...'
    cp /workspace/deepstream-yolo/utils/export_yolo11.py .
    
    echo 'Exporting \$MODEL_FILE with DeepStream compatibility...'
    python3 export_yolo11.py -w \$MODEL_FILE --dynamic
    
    echo 'Copying ONNX to models folder...'
    cp \${MODEL_FILE}.onnx /workspace/models/
    
    echo ''
    echo '✅ Export complete!'
    echo 'File: /workspace/models/'\${MODEL_FILE}'.onnx'
    echo 'This ONNX includes the DeepStreamOutput layer for correct bounding box parsing'
  "

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ SUCCESS!"
    echo "=========================================="
    echo "Exported: $OUTPUT_DIR/${MODEL_FILE}.onnx"
    echo ""
    echo "Next steps:"
    echo "1. Update your config to use the new ONNX file"
    echo "2. Delete old TensorRT engines:"
    echo "   rm -f $OUTPUT_DIR/*.engine"
    echo "3. Run detection test:"
    echo "   cd /mnt/d/github/deepstream_tests && ./test_detect.sh person"
    echo ""
    echo "The new ONNX file has DeepStream post-processing built-in,"
    echo "so bounding boxes should now appear in the correct positions!"
else
    echo ""
    echo "❌ Export failed. Check error messages above."
fi
