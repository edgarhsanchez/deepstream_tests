#!/usr/bin/env bash
# Test yolo11n model with multiple object classes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================" echo "YOLO11n Model Test Suite"
echo "Testing detection with multiple classes"
echo "========================================"
echo ""

# Test objects
OBJECTS=("person" "cup" "cell phone" "bottle" "chair")

for obj in "${OBJECTS[@]}"; do
    echo "Testing detection: $obj"
    echo "Press Ctrl+C to skip to next test after viewing..."
    
    MODEL_CONFIG=/models/config_infer_yolo11n.txt "${SCRIPT_DIR}/test_detect.sh" "$obj" rtsp://172.20.96.1:8554/live 800 600 || true
    
    echo ""
    echo "--------------------------------------"
    echo ""
    sleep 2
done

echo ""
echo "========================================" 
echo "YOLO11n Test Suite Complete!"
echo ""
echo "Model info:"
echo "  - Size: 11MB (vs 37MB for yolo11s)"
echo "  - Parameters: 2.6M (vs 11M for yolo11s)"
echo "  - Classes: 80 COCO classes"
echo "  - Speed: ~2-3x faster than yolo11s"
echo "  - Accuracy: ~95% of yolo11s accuracy"
echo ""
echo "Both models use the same:"
echo "  - DeepStream parser"
echo "  - Class filtering mechanism"
echo "  - Output format"
echo "========================================"
