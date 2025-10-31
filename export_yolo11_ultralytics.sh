#!/bin/bash

################################################################################
# export_yolo11_ultralytics.sh
#
# Export YOLO11 models to ONNX format using official Ultralytics method
# This script uses the native Ultralytics export functionality without custom
# post-processing layers, suitable for standard DeepStream deployments.
#
# USAGE:
#   ./export_yolo11_ultralytics.sh [MODEL_FILE] [MODEL_DIR]
#
# PARAMETERS:
#   MODEL_FILE  - Name of the .pt file (default: yolo11s.pt)
#   MODEL_DIR   - Directory containing the .pt file (default: /mnt/d/github/ultralytics)
#
# EXAMPLES:
#   # Export yolo11s.pt from default directory
#   ./export_yolo11_ultralytics.sh
#
#   # Export yolo11n.pt from default directory
#   ./export_yolo11_ultralytics.sh yolo11n.pt
#
#   # Export yolo11m.pt from custom directory
#   ./export_yolo11_ultralytics.sh yolo11m.pt /path/to/models
#
#   # Export custom trained model
#   ./export_yolo11_ultralytics.sh best.pt /path/to/runs/train/exp
#
# FEATURES:
#   - Uses official Ultralytics export API
#   - Dynamic batch size support for flexibility
#   - ONNX simplification for optimal performance
#   - Latest ONNX opset for compatibility
#   - Works with any YOLO11 variant (n, s, m, l, x)
#   - Supports custom trained models
#
# OUTPUT:
#   - Creates .onnx file in the models/ directory
#   - Ready for DeepStream TensorRT engine generation
#
# REQUIREMENTS:
#   - Docker with ultralytics/ultralytics image
#   - NVIDIA GPU support (for validation)
#   - Input .pt model file
#
# NOTES:
#   - Uses dynamic=True for flexible input sizes
#   - Simplifies ONNX graph for better performance
#   - TensorRT will build engine on first run (~1-2 minutes)
#   - Exported models compatible with DeepStream 8.0+
#
################################################################################

echo "=========================================="
echo "YOLO11 Ultralytics Export Script"
echo "=========================================="

# Parse arguments
MODEL_INPUT="${1:-yolo11s.pt}"
YOLO_MODEL_DIR="${2:-}"
OUTPUT_DIR="/mnt/d/github/deepstream_tests/models"

# Handle different input formats
if [ -z "$YOLO_MODEL_DIR" ]; then
    # No second argument provided
    if [ -f "$MODEL_INPUT" ]; then
        # First argument is a full path
        MODEL_PATH="$MODEL_INPUT"
        MODEL_FILE=$(basename "$MODEL_INPUT")
        YOLO_MODEL_DIR=$(dirname "$MODEL_INPUT")
    elif [ -f "/mnt/d/github/ultralytics/$MODEL_INPUT" ]; then
        # First argument is just filename in default directory
        MODEL_FILE="$MODEL_INPUT"
        YOLO_MODEL_DIR="/mnt/d/github/ultralytics"
        MODEL_PATH="$YOLO_MODEL_DIR/$MODEL_FILE"
    else
        # File not found
        MODEL_PATH="$MODEL_INPUT"
        MODEL_FILE="$MODEL_INPUT"
        YOLO_MODEL_DIR="/mnt/d/github/ultralytics"
    fi
else
    # Second argument provided - use as directory
    MODEL_FILE="$MODEL_INPUT"
    MODEL_PATH="$YOLO_MODEL_DIR/$MODEL_FILE"
fi

# Validate inputs
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model file not found: $MODEL_PATH"
    echo ""
    echo "Usage: $0 [model.pt] [model_dir]"
    echo "  model.pt  - Name of the .pt file (default: yolo11s.pt)"
    echo "  model_dir - Directory containing the .pt file (default: /mnt/d/github/ultralytics)"
    echo ""
    echo "Examples:"
    echo "  $0                              # Export yolo11s.pt from default directory"
    echo "  $0 yolo11m.pt                   # Export yolo11m.pt from default directory"
    echo "  $0 custom.pt /path/to/models    # Export custom.pt from specific directory"
    exit 1
fi

echo "Model path: $MODEL_PATH"
echo "Model file: $MODEL_FILE"
echo "Model directory: $YOLO_MODEL_DIR"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Convert to absolute path for Docker mounting
YOLO_MODEL_DIR_ABS=$(cd "$YOLO_MODEL_DIR" && pwd)

# Use official Ultralytics Docker image
docker run --rm \
  --gpus all \
  -v "$YOLO_MODEL_DIR_ABS":/workspace/models \
  -v "$OUTPUT_DIR":/workspace/output \
  -e MODEL_FILE="$MODEL_FILE" \
  ultralytics/ultralytics:latest \
  bash -c "
    set -e
    
    echo 'Exporting \$MODEL_FILE to ONNX format...'
    echo ''
    
    # Export using Ultralytics Python API
    python3 << 'PYTHON_EOF'
from ultralytics import YOLO
import os
import shutil

# Model paths
model_file = os.environ['MODEL_FILE']
model_path = f'/workspace/models/{model_file}'
output_dir = '/workspace/output'

print(f'Loading model: {model_path}')
model = YOLO(model_path)

print('Exporting to ONNX with fixed batch size for DeepStream...')
print('  - format: onnx')
print('  - dynamic: False (fixed dimensions for TensorRT)')
print('  - simplify: True (optimized graph)')
print('  - opset: None (latest compatible)')
print('  - batch: 1 (single image inference)')
print('')

# Export with optimal settings for DeepStream
# Note: dynamic=False is required for DeepStream TensorRT engine building
# DeepStream requires explicit dimensions or profile configuration
export_path = model.export(
    format='onnx',
    dynamic=False,     # Fixed dimensions (required for DeepStream)
    simplify=True,     # Simplify ONNX graph
    opset=None,        # Use latest opset
    imgsz=640,         # Default input size
    batch=1            # Batch size of 1
)

print(f'Export complete: {export_path}')

# Copy to output directory with original filename
onnx_filename = f'{model_file}.onnx'
output_path = os.path.join(output_dir, onnx_filename)
shutil.copy(export_path, output_path)

print(f'Copied to: {output_path}')
print('')
print('✅ Export successful!')
PYTHON_EOF

    echo ''
    echo 'ONNX file created with official Ultralytics export'
  "

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ SUCCESS!"
    echo "=========================================="
    echo "Exported: $OUTPUT_DIR/${MODEL_FILE}.onnx"
    echo ""
    echo "Export Configuration:"
    echo "  - Format: ONNX"
    echo "  - Dynamic: No (fixed dimensions for DeepStream/TensorRT)"
    echo "  - Batch Size: 1"
    echo "  - Input Size: 640x640"
    echo "  - Simplified: Yes (optimized graph)"
    echo "  - Opset: Latest compatible"
    echo ""
    echo "Next steps:"
    echo "1. Update your config to use the new ONNX file:"
    echo "   onnx-file=/models/${MODEL_FILE}.onnx"
    echo ""
    echo "2. Delete old TensorRT engines (if any):"
    echo "   rm -f $OUTPUT_DIR/*.engine"
    echo ""
    echo "3. Run detection test:"
    echo "   cd /mnt/d/github/deepstream_tests"
    echo "   ./test_detect.sh person"
    echo ""
    echo "4. Or run Python detection:"
    echo "   cd /mnt/d/github/deepstream_tests/detect_py"
    echo "   ./test_detect_rtsp_output_py.sh person"
    echo ""
    echo "Note: TensorRT will build optimized engine on first run (~1-2 minutes)"
    echo "      Subsequent runs will be fast (~2 seconds startup)"
else
    echo ""
    echo "❌ Export failed. Check error messages above."
    exit 1
fi
