#!/usr/bin/env bash
# Compare yolo11s vs yolo11n performance

set -euo pipefail

echo "======================================"
echo "YOLO11 Model Comparison"
echo "======================================"
echo ""

echo "Testing YOLO11s (standard model - 11M parameters)..."
MODEL_CONFIG=/models/config_infer_yolo11s.txt ./test_detect.sh person &
PID_S=$!
sleep 10
kill $PID_S 2>/dev/null || true
wait $PID_S 2>/dev/null || true

echo ""
echo "--------------------------------------"
echo ""

echo "Testing YOLO11n (nano model - 2.6M parameters)..."
MODEL_CONFIG=/models/config_infer_yolo11n.txt ./test_detect.sh person &
PID_N=$!
sleep 10
kill $PID_N 2>/dev/null || true
wait $PID_N 2>/dev/null || true

echo ""
echo "======================================"
echo "Comparison complete!"
echo ""
echo "Model sizes:"
ls -lh models/yolo11*.onnx | awk '{print $9, $5}'
echo ""
echo "Both models detect the same 80 COCO classes"
echo "YOLO11n is faster but slightly less accurate"
echo "YOLO11s has better accuracy but uses more resources"
echo "======================================"
