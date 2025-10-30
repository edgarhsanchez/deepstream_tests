# DeepStream Tests

DeepStream applications using NVIDIA GPU acceleration with Rust and GStreamer.

## Applications

### Scale
Video scaling and display using GStreamer.

**Run:**
```bash
./build.sh --project scale --run --x11 --device /dev/video0
```

**Environment Variables:**
- `OUTPUT_WIDTH` - Output width (default: 640)
- `OUTPUT_HEIGHT` - Output height (default: 480)

---

### Detect
GPU-accelerated object detection with YOLO11 models.

**Quick Start:**
```bash
# Detect people
./test_detect.sh person

# Detect cups
./test_detect.sh cup

# Detect other objects (80 COCO classes available)
./test_detect.sh "cell phone"
```

**Using Different Models:**
```bash
# Fast nano model (11MB, 2-3x faster)
MODEL_CONFIG=/models/config_infer_yolo11n.txt ./test_detect.sh person

# Standard model (37MB, better accuracy) - default
./test_detect.sh person
```

**Environment Variables:**
- `MODEL_CONFIG` - Model configuration file (default: yolo11s)
- `OUTPUT_WIDTH` - Display width (default: 1280)
- `OUTPUT_HEIGHT` - Display height (default: 720)

**Available Objects (80 COCO classes):**
person, bicycle, car, motorcycle, airplane, bus, train, truck, boat, traffic light, fire hydrant, stop sign, parking meter, bench, bird, cat, dog, horse, sheep, cow, elephant, bear, zebra, giraffe, backpack, umbrella, handbag, tie, suitcase, frisbee, skis, snowboard, sports ball, kite, baseball bat, baseball glove, skateboard, surfboard, tennis racket, bottle, wine glass, cup, fork, knife, spoon, bowl, banana, apple, sandwich, orange, broccoli, carrot, hot dog, pizza, donut, cake, chair, couch, potted plant, bed, dining table, toilet, tv, laptop, mouse, remote, keyboard, cell phone, microwave, oven, toaster, sink, refrigerator, book, clock, vase, scissors, teddy bear, hair drier, toothbrush

## Models

Two YOLO11 models are available:

| Model | Size | Speed | Best For |
|-------|------|-------|----------|
| yolo11n | 11MB | Fastest | Real-time, multiple cameras |
| yolo11s | 37MB | Fast | General purpose (default) |

Both detect the same 80 COCO object classes with GPU acceleration via TensorRT.

## Setup

### First-Time Setup

1. **Clone DeepStream-YOLO** (external dependency):
```bash
./setup_deepstream_yolo.sh
```

This script:
- Clones the DeepStream-YOLO repository
- Applies CUDA 12.8 compatibility patch
- Compiles the YOLO parser library

**Note**: The `deepstream-yolo/` directory is excluded from git (managed separately).

### Requirements

- Docker with NVIDIA GPU support
- NVIDIA drivers installed
- X11 forwarding for display

## Converting PyTorch Models to DeepStream-Compatible ONNX

To use custom YOLO11 models, you need to export them with DeepStream compatibility:

**Export Script:**
```bash
./export_yolo11_fixed.sh <model.pt> <model_directory>
```

**Examples:**
```bash
# Export yolo11n.pt from models directory
./export_yolo11_fixed.sh yolo11n.pt /mnt/d/github/deepstream_tests/models

# Export yolo11m.pt from a custom location
./export_yolo11_fixed.sh yolo11m.pt /path/to/your/models
```

**What it does:**
1. Runs in PyTorch 2.4 Docker container (compatible version)
2. Adds DeepStreamOutput layer to fix bounding box coordinates
3. Exports to ONNX format with `--dynamic` flag
4. Outputs `<model>.pt.onnx` in the specified directory

**Important:**
- Standard Ultralytics YOLO export produces incorrect bounding boxes
- The DeepStreamOutput layer transposes output and extracts coordinates correctly
- Without this layer, all bounding boxes appear in the upper-left corner

**Supported Models:**
- yolo11n (nano), yolo11s (small), yolo11m (medium), yolo11l (large), yolo11x (xlarge)
- All variants export to the same format with 80 COCO classes

## TensorRT Engine Files

On first run, DeepStream builds a GPU-optimized TensorRT engine from the ONNX model:

**Build Process:**
- Takes ~1-2 minutes on first run
- Creates `.engine` files in the `models/` directory
- Example: `yolo11n.pt.onnx` → `yolo11n.pt.onnx_b1_gpu0_fp32.engine`

**Caching:**
- Engine files are cached and reused on subsequent runs
- Startup time: ~2 seconds (vs 2 minutes without cache)
- Rebuilds automatically if ONNX file changes

**Important:**
- `.engine` files are GPU-specific (not portable between different GPUs)
- Large files (100-200MB+)
- Excluded from git (in `.gitignore`)
- Safe to delete - will rebuild automatically when needed

## Notes

- Detection works with RTSP streams, local video files, webcams, or test patterns
- Only one object class can be detected at a time (filtered for performance)
