# DeepStream Python Object Detection with RTSP Streaming

Python implementation of the DeepStream object detection application with RTSP input/output support.

## Quick Reference

```bash
# Basic usage
./test_detect_rtsp_output_py.sh <object> [port] [width] [height]

# Examples
./test_detect_rtsp_output_py.sh person              # Default: 1920x1080, port 8556
./test_detect_rtsp_output_py.sh car 8557            # Custom port
./test_detect_rtsp_output_py.sh dog 8556 1280 720   # Custom resolution
./test_detect_rtsp_output_py.sh cup 8556 640 480    # Low resolution (faster)

# View stream
ffplay rtsp://localhost:8556/ds-detect
```

## Features

- GPU-accelerated object detection using YOLO11 models
- RTSP input stream support
- RTSP output streaming capability
- Configurable target object filtering
- Zero-copy GPU processing
- Multiple model support (YOLO11s, YOLO11n)

## Requirements

- NVIDIA GPU with CUDA support
- DeepStream SDK 8.0
- Python 3 with GStreamer bindings (pre-installed in DeepStream container)
- Docker (for containerized execution)

## How to Run

The Python detect application can be run in several ways:

### Method 1: Using Test Script (Recommended)

The easiest way is using the provided test script:

```bash
cd detect_py
./test_detect_rtsp_output_py.sh <object> [port] [width] [height]
```

**Examples:**
```bash
# Detect person with defaults (1920x1080, port 8556)
./test_detect_rtsp_output_py.sh person

# Detect car on custom port
./test_detect_rtsp_output_py.sh car 8557

# Detect with lower resolution for better performance
./test_detect_rtsp_output_py.sh dog 8556 1280 720

# Detect with minimal resolution (fastest)
./test_detect_rtsp_output_py.sh "cell phone" 8556 640 480
```

### Method 2: With Environment Variables

Combine parameters and environment variables:

```bash
# Use faster nano model
MODEL_CONFIG=/models/config_infer_yolo11n.txt ./test_detect_rtsp_output_py.sh bicycle

# Custom RTSP input
RTSP_URL="rtsp://192.168.1.100:554/stream" ./test_detect_rtsp_output_py.sh person

# Multiple overrides
MODEL_CONFIG=/models/config_infer_yolo11n.txt \
RTSP_URL="rtsp://camera.local:554/live" \
./test_detect_rtsp_output_py.sh car 8557 1280 720
```

### Method 3: Direct Docker Command

For maximum control, run Docker directly:

```bash
cd detect_py
docker run --rm -it \
    --gpus all \
    --net host \
    -v "$(pwd)/..":/workdir \
    -v "$(pwd)/../models":/models \
    -v "$(pwd)/../deepstream-yolo":/workspace/deepstream-yolo \
    -w /workdir \
    -e DETECT_OBJECT="person" \
    -e RTSP_URL="rtsp://172.20.96.1:8554/live" \
    -e MODEL_CONFIG="/models/config_infer_yolo11s.txt" \
    -e RTSP_OUTPUT=true \
    -e RTSP_OUTPUT_PORT=8556 \
    -e OUTPUT_WIDTH=1920 \
    -e OUTPUT_HEIGHT=1080 \
    nvcr.io/nvidia/deepstream:8.0-samples-multiarch \
    python3 detect_py/detect.py
```

## Quick Start

### Basic Usage

Detect a specific object and stream to RTSP:

```bash
cd detect_py
chmod +x test_detect_rtsp_output_py.sh

# Basic detection
./test_detect_rtsp_output_py.sh person

# View the stream in another terminal
ffplay rtsp://localhost:8556/ds-detect
```

### Script Parameters

The test script accepts positional parameters:

```bash
./test_detect_rtsp_output_py.sh <object> [port] [width] [height]
```

**Parameters:**
1. `object` - Object to detect (default: `person`)
2. `port` - RTSP output port (default: `8556`)
3. `width` - Output width in pixels (default: `1920`)
4. `height` - Output height in pixels (default: `1080`)

### Usage Examples

```bash
# Detect cars with default settings
./test_detect_rtsp_output_py.sh car

# Detect dogs on custom port
./test_detect_rtsp_output_py.sh dog 8557

# Detect cups with custom resolution
./test_detect_rtsp_output_py.sh cup 8556 1280 720

# Detect bicycles with HD resolution
./test_detect_rtsp_output_py.sh bicycle 8556 1920 1080

# Detect cell phones with lower resolution for better performance
./test_detect_rtsp_output_py.sh "cell phone" 8556 640 480
```

## Viewing the Stream

Once the application is running, view the RTSP stream with:

### Using ffplay
```bash
ffplay rtsp://localhost:8556/ds-detect
```

### Using VLC
```bash
vlc rtsp://localhost:8556/ds-detect
```

### Using GStreamer
```bash
gst-launch-1.0 rtspsrc location=rtsp://localhost:8556/ds-detect ! rtph264depay ! h264parse ! avdec_h264 ! videoconvert ! autovideosink
```

## Advanced Configuration

### Environment Variables

The Python application supports the following environment variables:

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `DETECT_OBJECT` | Object to detect from COCO dataset | `person` | `car`, `dog`, `cup` |
| `RTSP_URL` | Input RTSP stream URL | `rtsp://172.20.96.1:8554/live` | `rtsp://192.168.1.100:554/stream` |
| `MODEL_CONFIG` | Path to model config file | `/models/config_infer_yolo11s.txt` | `/models/config_infer_yolo11n.txt` |
| `MODEL_ENGINE` | Path to TensorRT engine file | Auto-detected | `/workdir/model_b1_gpu0_fp32.engine` |
| `SHOW_DISPLAY` | Enable local display output | `false` | `true`, `false` |
| `RTSP_OUTPUT` | Enable RTSP streaming output | `true` | `true`, `false` |
| `RTSP_OUTPUT_PORT` | RTSP server port | `8556` | `8555`, `8557` |
| `OUTPUT_WIDTH` | Output stream width in pixels | `1920` | `1280`, `640` |
| `OUTPUT_HEIGHT` | Output stream height in pixels | `1080` | `720`, `480` |

### Using Environment Variables

Override defaults using environment variables:

```bash
# Use faster nano model
MODEL_CONFIG=/models/config_infer_yolo11n.txt ./test_detect_rtsp_output_py.sh car

# Custom input source
RTSP_URL="rtsp://192.168.1.100:554/camera1" ./test_detect_rtsp_output_py.sh person

# Lower resolution for better performance
./test_detect_rtsp_output_py.sh person 8556 640 480

# Combine environment variables and parameters
MODEL_CONFIG=/models/config_infer_yolo11n.txt \
RTSP_URL="rtsp://192.168.1.100:554/stream" \
./test_detect_rtsp_output_py.sh bicycle 8557 1280 720
```

### Direct Docker Execution

For full control, run the Docker container directly:

```bash
docker run --rm -it \
    --gpus all \
    --net host \
    -v "$(pwd)/..":/workdir \
    -v "$(pwd)/../models":/models \
    -v "$(pwd)/../deepstream-yolo":/workspace/deepstream-yolo \
    -w /workdir \
    -e DETECT_OBJECT="bicycle" \
    -e RTSP_URL="rtsp://your-camera-ip:554/stream" \
    -e MODEL_CONFIG="/models/config_infer_yolo11n.txt" \
    -e RTSP_OUTPUT=true \
    -e RTSP_OUTPUT_PORT=8556 \
    -e OUTPUT_WIDTH=1280 \
    -e OUTPUT_HEIGHT=720 \
    nvcr.io/nvidia/deepstream:8.0-samples-multiarch \
    python3 detect_py/detect.py
```

### Model Selection

Choose between different YOLO11 models:

```bash
# Fast nano model (11MB) - 2-3x faster, good accuracy
MODEL_CONFIG=/models/config_infer_yolo11n.txt ./test_detect_rtsp_output_py.sh car

# Standard small model (37MB) - default, better accuracy
./test_detect_rtsp_output_py.sh car
```

## Pipeline Architecture

The Python application creates the following GStreamer pipeline:

```
nvurisrcbin → nvvideoconvert → nvstreammux → nvinfer → nvdsosd → 
nvvideoconvert → nvv4l2h264enc → h264parse → rtph264pay
```

Key components:
- **nvurisrcbin**: Handles RTSP input streams with auto-reconnection
- **nvstreammux**: Batches frames for inference (batch-size=1)
- **nvinfer**: TensorRT-accelerated YOLO11 inference
- **nvdsosd**: On-screen display for bounding boxes and labels
- **nvv4l2h264enc**: Hardware H.264 encoding
- **rtph264pay**: RTP packetization for RTSP streaming

All video processing happens in GPU memory (NVMM) for zero-copy efficiency.

## RTSP Stream Details

- **Protocol**: RTSP over TCP
- **Video Codec**: H.264
- **RTP Payload**: PT=96
- **Bitrate**: 4 Mbps
- **URL Format**: `rtsp://localhost:8556/ds-detect`
- **Note**: Port 8556 is used to avoid conflict with Rust version (port 8555)

## Supported Objects

The application can detect any object from the COCO dataset (80 classes). Common examples:

- person, bicycle, car, motorcycle, airplane, bus, train, truck
- traffic light, fire hydrant, stop sign, parking meter, bench
- cat, dog, horse, sheep, cow, elephant, bear, zebra, giraffe
- backpack, umbrella, handbag, tie, suitcase
- bottle, wine glass, cup, fork, knife, spoon, bowl
- chair, couch, potted plant, bed, dining table, toilet, tv
- laptop, mouse, remote, keyboard, cell phone, microwave, oven
- book, clock, vase, scissors, teddy bear, hair drier, toothbrush

See `/models/labels.txt` for the complete list.

## Troubleshooting

### RTSP Server Not Starting

1. **Check if port is already in use**:
   ```bash
   ss -tln | grep 8556
   ```

2. If port is in use, use a different port:
   ```bash
   ./test_detect_rtsp_output_py.sh person 8557
   ```

### No Video in Stream

1. Verify GPU is accessible:
   ```bash
   nvidia-smi
   ```

2. Check if input RTSP stream is accessible:
   ```bash
   ffprobe rtsp://your-camera-ip:554/stream
   ```

3. Review Docker container logs for errors

### Import Errors (gi.repository)

The Python GStreamer bindings should be pre-installed in the DeepStream container. If running outside the container:

```bash
sudo apt-get install python3-gi python3-gi-cairo gir1.2-gtk-3.0
sudo apt-get install gir1.2-gst-rtsp-server-1.0
```

### Engine File Issues

The TensorRT engine files are generated on first run. If you encounter errors:

1. Delete existing engine files:
   ```bash
   rm *.engine
   ```

2. Run the application again to regenerate engines

## Comparison: Python vs Rust

| Feature | Python Version | Rust Version |
|---------|---------------|--------------|
| Performance | High (GStreamer native) | High (GStreamer native) |
| Memory Safety | Runtime checks | Compile-time checks |
| Development Speed | Fast prototyping | More verbose |
| Dependencies | Pre-installed in DS | Requires Rust toolchain |
| Type Safety | Dynamic typing | Strong static typing |
| Use Case | Quick experiments | Production systems |

Both versions use the same GStreamer pipeline and achieve similar performance since the heavy lifting is done by native GStreamer plugins.

## License

Same as parent project.
