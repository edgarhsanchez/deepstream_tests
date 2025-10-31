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

### Detect (Rust)
GPU-accelerated object detection with YOLO11 models using Rust.

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
- `RTSP_OUTPUT` - Enable RTSP output (set to "enabled")
- `RTSP_OUTPUT_PORT` - RTSP output port (default: 8554)
- `SHOW_DISPLAY` - Show X11 window (default: true)

### RTSP Stream Output

The detect application can stream the processed video with bounding boxes to an RTSP server. This allows you to view the detection stream remotely or integrate it with other applications.

**Basic Usage:**
```bash
./test_detect_rtsp_output.sh person
```

**Detect Different Objects:**
```bash
./test_detect_rtsp_output.sh car        # Detect cars
./test_detect_rtsp_output.sh dog        # Detect dogs
./test_detect_rtsp_output.sh bicycle    # Detect bicycles
./test_detect_rtsp_output.sh "cell phone"  # Multi-word objects need quotes
```

**View the Stream:**

In another terminal, connect to the RTSP stream:
```bash
# Using ffplay (recommended for low latency)
ffplay rtsp://localhost:8555/ds-detect

# Using VLC
vlc rtsp://localhost:8555/ds-detect

# Using GStreamer directly
gst-launch-1.0 rtspsrc location=rtsp://localhost:8555/ds-detect ! decodebin ! autovideosink
```

**Advanced Configuration:**

Use environment variables to customize the RTSP server:

```bash
# Use faster nano model for better performance
MODEL_CONFIG=/models/config_infer_yolo11n.txt ./test_detect_rtsp_output.sh person

# Change RTSP port (if 8555 is already in use)
RTSP_OUTPUT_PORT=8556 ./test_detect_rtsp_output.sh car

# Change input source
RTSP_URL=rtsp://192.168.1.100:8554/camera1 ./test_detect_rtsp_output.sh person

# Change output resolution
OUTPUT_WIDTH=1920 OUTPUT_HEIGHT=1080 ./test_detect_rtsp_output.sh car

# Combine multiple options
MODEL_CONFIG=/models/config_infer_yolo11n.txt \
RTSP_OUTPUT_PORT=8556 \
OUTPUT_WIDTH=1920 \
OUTPUT_HEIGHT=1080 \
./test_detect_rtsp_output.sh bicycle
```

**Environment Variables:**

| Variable | Description | Default |
|----------|-------------|---------|
| `MODEL_CONFIG` | Model configuration file path | `/models/config_infer_yolo11n.txt` |
| `RTSP_URL` | Input RTSP stream URL | `rtsp://172.20.96.1:8554/live` |
| `RTSP_OUTPUT_PORT` | RTSP server output port | `8555` |
| `OUTPUT_WIDTH` | Stream output width | `1280` |
| `OUTPUT_HEIGHT` | Stream output height | `720` |

**RTSP Stream Details:**
- **URL**: `rtsp://localhost:<PORT>/ds-detect`
- **Default Port**: 8555
- **Protocol**: H.264 over RTP
- **Latency**: Optimized for low-latency streaming
- **GPU Acceleration**: Uses NVENC hardware encoder for minimal CPU usage

**Troubleshooting:**

If you can't connect to the RTSP stream:

1. **Check if server is running**:
   ```bash
   ss -tln | grep 8555
   ```

2. **Check for port conflicts**:
   ```bash
   RTSP_OUTPUT_PORT=8556 ./test_detect_rtsp_output.sh person
   ```

3. **Test with ffplay first** (simpler than VLC):
   ```bash
   ffplay -rtsp_transport tcp rtsp://localhost:8555/ds-detect
   ```

4. **Check Docker network**:
   The container uses `--network host`, so the RTSP port is directly accessible on localhost.

5. **Verify engine file exists**:
   The TensorRT engine needs to be pre-built. On first run, it will take 2-3 minutes to build the engine from the ONNX model.

---

### Detect (Python)
Python implementation of the detect application - identical features to the Rust version.

**Quick Start:**
```bash
cd detect_py

# Detect people
./test_detect_rtsp_output_py.sh person

# Detect cars
./test_detect_rtsp_output_py.sh car

# Detect with custom port
./test_detect_rtsp_output_py.sh dog 8556
```

**View the Stream:**
```bash
ffplay rtsp://localhost:8556/ds-detect
```

**Note:** Python version uses port 8556 by default (Rust version uses 8555).

**Why Python?**
- Faster development and prototyping
- Easier to modify and experiment with
- Same performance (uses native GStreamer plugins)
- Pre-installed dependencies in DeepStream container
- Great for learning and testing

**Full Documentation:**
See [detect_py/README.md](detect_py/README.md) for complete Python version documentation.

**Comparison:**
Both Rust and Python versions use identical GStreamer pipelines and achieve the same performance. Choose Python for quick experiments and Rust for production deployments requiring maximum type safety.

---

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
