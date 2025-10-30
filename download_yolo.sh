#!/bin/bash
set -e

echo "Installing ultralytics and downloading YOLOv8 model..."

# Check if python3 and pip are available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not installed"
    exit 1
fi

# Install ultralytics to user directory
echo "Installing ultralytics package (to user directory)..."
pip install --user ultralytics

# Create models directory if it doesn't exist
mkdir -p models

# Export YOLOv8 nano model to ONNX format
echo "Downloading and exporting YOLOv8n (nano) to ONNX..."
cd models
python3 -m ultralytics.engine.exporter model=yolov8n.pt format=onnx || \
  ~/.local/bin/yolo export model=yolov8n.pt format=onnx

echo ""
echo "✓ YOLOv8 model downloaded and exported!"
echo "  Location: $(pwd)/yolov8n.onnx"
echo ""
echo "YOLOv8 can detect 80 object classes including:"
echo "  - person, bicycle, car, motorcycle, airplane, bus, train, truck, boat"
echo "  - bottle, wine glass, cup, fork, knife, spoon, bowl"
echo "  - chair, couch, bed, dining table, toilet"
echo "  - tv, laptop, mouse, keyboard, cell phone, microwave, oven"
echo "  - and many more..."
echo ""
echo "To use this model with detect app, set MODEL_CONFIG environment variable"
echo "to point to the YOLOv8 config file (will be created next)"
