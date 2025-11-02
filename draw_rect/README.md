# Draw Rectangle - Zero-Copy CUDA Rectangle Drawing on RTSP Video# Draw Rectangle - CUDA NV12 Video Processing



GPU-accelerated rectangle drawing on live RTSP video streams using CUDA kernels with zero-copy memory operations. Draws 5-pixel thick white rectangle outlines directly on GPU memory for maximum performance.This project demonstrates drawing 1-pixel rectangle outlines on NV12 video frames using CUDA kernels. It reads video from an RTSP source and outputs the modified stream to a new RTSP server.



## Features## Features



- ✅ **Zero-Copy GPU Drawing**: CUDA kernel operates directly on GPU memory, no CPU transfers- **CUDA Kernel**: Direct manipulation of Y (luma) plane in NV12 format

- ✅ **5-Pixel Thick Rectangles**: Highly visible white outlines on video frames- **GPU-Accelerated**: All drawing operations happen on GPU without CPU round-trips

- ✅ **Split Architecture**: Processor handles source connection, server provides instant client access- **RTSP Input/Output**: Seamless integration with RTSP video streams

- ✅ **Hardware Encoding**: Uses NVIDIA NVENC (dedicated encoder chip, not CUDA cores)- **Multiple Rectangles**: Support for drawing multiple rectangles per frame

- ✅ **Low Latency**: ~50-100ms total latency from source to output- **GStreamer Pipeline**: Uses NVIDIA DeepStream elements for zero-copy operations

- ✅ **Multiple Rectangles**: Draw unlimited rectangles per frame- **Two Implementations**: 

- ✅ **RTSP Input/Output**: Seamless streaming pipeline integration  - **PyCUDA** (Recommended): No compilation needed, kernel defined in Python

- ✅ **Production Ready**: Docker containerized, automatic cleanup, robust error handling  - **C++/CUDA**: Traditional approach with separate compilation



## Architecture## Architecture



The system uses a **split architecture** with two applications:### Implementation 1: PyCUDA (Recommended)



```**File: `draw_rect_pycuda.py`**

Source RTSP (8554) → Processor (8555) → Server (8556) → Clients

                       ↓ CUDA Drawing- CUDA kernel defined as Python string

```- Runtime compilation by PyCUDA

- No separate build step required

### Why Split Architecture?- Easier to modify and experiment with



**Problem**: RTSP source takes 10-30 seconds to connect. Clients connecting to a single-app RTSP server would see "503 Service Unavailable" during this time.Advantages:

- ✅ No compilation step

**Solution**: - ✅ Faster development iteration

1. **Processor** maintains persistent connection to source, draws rectangles, serves on port 8555- ✅ Kernel code in same file as Python code

2. **Server** connects to processor once, re-streams on port 8556 with instant availability- ✅ Automatic GPU initialization

3. **Clients** connect to server and get immediate response (no wait time)

### Implementation 2: C++/CUDA (Traditional)

### Data Flow

**Files: `cuda_draw.cu` + `draw_rect.py`**

```

┌─────────────────────────────────────────────────────────────────┐- CUDA kernel in separate `.cu` file

│ Processor (Port 8555)                                           │- Compiled to shared library using nvcc

├─────────────────────────────────────────────────────────────────┤- Python loads library via ctypes

│ Source (8554) → nvurisrcbin → nvvideoconvert (CUDA unified)   │- Traditional CUDA development workflow

│                    ↓                                            │

│              identity ← CUDA Drawing Probe                      │Advantages:

│                    ↓                                            │- ✅ Potentially faster compilation (pre-built)

│         queue → nvvideoconvert (NV12→I420) → nvv4l2h264enc    │- ✅ Familiar to CUDA developers

│                    ↓                                            │- ✅ Can optimize compile flags

│         h264parse → rtph264pay → RTSP Server (8555)            │

└─────────────────────────────────────────────────────────────────┘### Common Features

                            ↓

┌─────────────────────────────────────────────────────────────────┐- Draws 1-pixel rectangle outlines on Y plane of NV12 frames

│ Server (Port 8556)                                              │- Efficient parallel implementation using 4 thread blocks (one per edge)

├─────────────────────────────────────────────────────────────────┤- Supports multiple rectangles in a single call

│  rtspsrc (8555) → rtph264depay → h264parse → rtph264pay        │- Boundary checking to handle edge cases

│                         ↓                                       │- GStreamer-based RTSP server

│                  RTSP Server (8556) → Multiple Clients          │- Buffer probe to intercept and modify video frames

└─────────────────────────────────────────────────────────────────┘- Configurable rectangle positions and colors

```

## Requirements

## Quick Start

- NVIDIA GPU with CUDA support

### Option 1: Using the Launch Script (Recommended)- NVIDIA DeepStream SDK 8.0+

- GStreamer with RTSP server support

```bash- Python 3.8+

cd draw_rect- CUDA Toolkit 11.0+



# Start both processor and server## Quick Start

./run_split.sh

### Option 1: PyCUDA (No Build Required) ⭐ Recommended

# The script will:

# 1. Build Docker image```bash

# 2. Start processor on port 8555# Install PyCUDA (first time only)

# 3. Start server on port 8556pip3 install pycuda

# 4. Show logs from both containers

# Press Ctrl+C to stop both containers# Run with default settings (port 8558)

```python3 draw_rect_pycuda.py



### Option 2: Manual Docker Commands# Or use the test script

./test_draw_rect_pycuda.sh

```bash```

cd draw_rect

### Option 2: Traditional C++/CUDA

# Build the image

docker build -t draw_rect:latest .```bash

cd draw_rect

# Start processor (port 8555)

docker run -d --name draw_rect_processor \# Build the CUDA library

  --gpus all --network host --ipc=host \make

  draw_rect:latest \

  python3 -u /workdir/draw_rect_processor.py \# Run the Python app

    --input rtsp://172.20.96.1:8554/live \python3 draw_rect.py

    --port 8555 \

    --width 960 --height 540# Or use the test script

./test_draw_rect.sh

# Start server (port 8556)```

docker run -d --name draw_rect_server \

  --network host --ipc=host \The build will create `libcuda_draw.so` which is loaded by the Python application.

  draw_rect:latest \

  python3 -u /workdir/draw_rect_server.py \## Usage

    --input rtsp://localhost:8555/processed \

    --port 8556### Basic Usage (PyCUDA)



# View logs```bash

docker logs -f draw_rect_processor# Run with default settings (port 8558)

docker logs -f draw_rect_serverpython3 draw_rect_pycuda.py

```

# Stop and cleanup

docker stop draw_rect_processor draw_rect_server### Basic Usage (C++/CUDA)

docker rm draw_rect_processor draw_rect_server

``````bash

# Run with default settings (port 8558)

## Usagepython3 draw_rect.py

```

### Viewing the Output Stream

### Custom Configuration

```bash

# Using ffplay (recommended, low latency)Both implementations support the same command-line options:

ffplay rtsp://localhost:8556/live

```bash

# Using VLC# Custom input RTSP source

vlc rtsp://localhost:8556/livepython3 draw_rect_pycuda.py --input rtsp://192.168.1.100:8554/live



# Using GStreamer# Custom output port

gst-launch-1.0 playbin uri=rtsp://localhost:8556/livepython3 draw_rect_pycuda.py --port 9000

```

# Custom resolution

### Viewing Intermediate Stream (Processor Output)python3 draw_rect_pycuda.py --width 1920 --height 1080



```bash# All options combined

# View processor output directly (bypass server)python3 draw_rect_pycuda.py \

ffplay rtsp://localhost:8555/processed  --input rtsp://camera.local:8554/stream \

```  --port 9000 \

  --width 1920 \

### Custom Configuration  --height 1080

```

#### Environment Variables (for run_split.sh):

Replace `draw_rect_pycuda.py` with `draw_rect.py` to use the C++/CUDA version.

```bash

# Custom source### Viewing the Output

INPUT_RTSP=rtsp://192.168.1.100:8554/camera1 ./run_split.sh

```bash

# Custom ports# Using ffplay

PROCESSOR_PORT=8557 SERVER_PORT=8558 ./run_split.shffplay rtsp://localhost:8558/draw-rect



# Custom resolution# Using VLC

WIDTH=1920 HEIGHT=1080 ./run_split.shvlc rtsp://localhost:8558/draw-rect

```

# All options

INPUT_RTSP=rtsp://camera:554/live \## Docker Usage

PROCESSOR_PORT=8557 \

SERVER_PORT=8558 \### PyCUDA Version (Easiest)

WIDTH=1920 HEIGHT=1080 \

./run_split.sh```bash

```docker run --rm -it \

  --gpus all \

#### Command-Line Arguments (manual Docker run):  -v $(pwd)/draw_rect:/workdir \

  -w /workdir \

**Processor:**  --network host \

```bash  nvcr.io/nvidia/deepstream:8.0-samples-multiarch \

python3 draw_rect_processor.py \  bash -c "pip3 install pycuda && python3 draw_rect_pycuda.py"

  --input rtsp://camera:554/live \```

  --port 8555 \

  --width 1920 \### C++/CUDA Version

  --height 1080

``````bash

# Build with CUDA development container

**Server:**docker run --rm \

```bash  --gpus all \

python3 draw_rect_server.py \  -v $(pwd)/draw_rect:/workdir \

  --input rtsp://localhost:8555/processed \  -w /workdir \

  --port 8556  nvidia/cuda:12.6.0-devel-ubuntu22.04 \

```  make



### Customizing Rectangles# Run with DeepStream container

docker run --rm -it \

Edit `draw_rect_processor.py` and modify the rectangles list:  --gpus all \

  -v $(pwd)/draw_rect:/workdir \

```python  -w /workdir \

# In DrawRectProcessor.__init__()  --network host \

self.rectangles = [  nvcr.io/nvidia/deepstream:8.0-samples-multiarch \

    Rectangle(100, 100, 200, 150),  # x=100, y=100, w=200, h=150  python3 draw_rect.py

    Rectangle(400, 200, 300, 200),  # x=400, y=200, w=300, h=200```

    Rectangle(150, 350, 250, 100),  # x=150, y=350, w=250, h=100

]## Customizing Rectangles

```

Edit the `rectangles` list in either `draw_rect_pycuda.py` or `draw_rect.py`:

**Rectangle Parameters:**

- `x, y`: Top-left corner position (pixels)```python

- `w, h`: Width and height (pixels)self.rectangles = [

- Drawn as 5-pixel thick white outlines on Y (luma) plane    [x, y, width, height],  # Rectangle 1

    [x, y, width, height],  # Rectangle 2

## Port Assignments    # Add more rectangles...

]

| Port | Service | Description |```

|------|---------|-------------|

| 8554 | Source | Input RTSP stream |Coordinates:

| 8555 | Processor | CUDA-processed stream with rectangles |- `x, y`: Top-left corner position

| 8556 | Server | Final output for clients |- `width, height`: Rectangle dimensions

- All values in pixels

**Note**: Ports are configurable via environment variables or command-line arguments.

## NV12 Format

## Performance

NV12 is a semi-planar YUV format:

### Typical Metrics (960x540 @ 60fps):- **Y plane**: Full resolution luma (brightness) - `width × height` bytes

- **UV plane**: Half resolution chroma (color) - `(width × height) / 2` bytes

| Component | Usage |

|-----------|-------|This project draws on the Y plane only, creating white (255) or black (0) rectangle outlines.

| **GPU Compute** | ~5% (GStreamer + CUDA drawing) |

| **NVDEC** (Decoder) | ~10-15% |## Performance

| **NVENC** (Encoder) | ~20-30% |

| **CPU** | ~5-10% per container |The CUDA kernel is highly efficient:

| **Memory (GPU)** | ~200MB |- Direct GPU memory access (no CPU transfers)

| **Memory (CPU)** | ~50MB per container |- Parallel processing of rectangle edges

| **Latency** | ~50-100ms end-to-end |- Minimal overhead on video pipeline

- Can handle 4K video at 30+ FPS

### Why It's Fast:

## API Reference

1. ✅ **Zero-Copy Pipeline**: GPU → CUDA kernel → GPU encoder (no CPU transfers)

2. ✅ **Hardware Encoding**: NVENC chip (not CUDA cores)### PyCUDA API

3. ✅ **Efficient CUDA Kernel**: 5-pixel drawing with parallel execution

4. ✅ **Optimized Memory**: CUDA unified memory (type 3)```python

from draw_rect_pycuda import PyCUDADrawRect

## Technical Details

# Initialize (kernel compiled automatically)

### CUDA Implementationcuda_draw = PyCUDADrawRect()



**File**: `cuda_draw.cu`# Draw single rectangle

cuda_draw.draw_rectangle(

- **Kernel**: `draw_rectangle_kernel<<<>>>` draws 4 edges in parallel    d_y_plane_ptr=gpu_ptr,  # Integer pointer to GPU memory

- **Thickness**: 5-pixel lines for high visibility    width=1280,

- **Memory**: Operates directly on Y plane GPU pointer    height=720,

- **Zero-Copy**: No cudaMalloc or cudaMemcpy operations    stride=1280,

- **Function**: `draw_rectangles(device_ptr, ...)` - zero-copy entry point    x=100, y=100,

    w=400, h=300,

**Compiled to**: `libcuda_draw.so` (44MB shared library)    color=255  # White

)

### Python Integration

# Draw multiple rectangles

**Processor**: `draw_rect_processor.py`rectangles = [

- Creates RTSP server using GstRtspServer    [100, 100, 400, 300],

- GStreamer pipeline with nvurisrcbin → nvvideoconvert → identity probe    [600, 200, 200, 150],

- Buffer probe intercepts frames, extracts GPU pointer via NvBufSurface]

- Calls CUDA kernel with GPU pointer (zero-copy)cuda_draw.draw_rectangles(

- Encodes with nvv4l2h264enc (hardware H.264 encoder)    d_y_plane_ptr=gpu_ptr,

    width=1280,

**Server**: `draw_rect_server.py`    height=720,

- Simple RTSP re-streaming server    stride=1280,

- Reads from processor's RTSP output    rectangles=rectangles,

- Re-packages for multiple clients    color=255

- Minimal CPU/GPU usage)

```

### NvBufSurface Zero-Copy Access

### C++/CUDA API

```python

# Extract NvBufSurface from GStreamer buffer**CUDA Functions (C++):**

surface_ptr = ctypes.cast(map_info.data, POINTER(NvBufSurface))

surface = surface_ptr.contents```c

// Draw a single rectangle

# Map for GPU accesscudaError_t draw_rectangle(

libnvbufsurface.NvBufSurfaceMap(surface_ptr, 0, 0, NVBUF_MAP_READ_WRITE)    unsigned char* d_y_plane,  // GPU pointer to Y plane

    int width,                  // Frame width

# Get GPU pointer    int height,                 // Frame height

device_ptr = surface.surfaceList[0].dataPtr  # GPU address!    int stride,                 // Y plane stride (usually equals width)

    int x, int y,              // Rectangle position

# Draw with CUDA (operates directly on this GPU memory)    int w, int h,              // Rectangle dimensions

libcuda_draw.draw_rectangles(device_ptr, width, height, pitch, rects, ...)    unsigned char color,        // Y value (0-255)

    cudaStream_t stream        // CUDA stream (optional)

# Sync and unmap);

libnvbufsurface.NvBufSurfaceSyncForDevice(surface_ptr, 0, 0)```

libnvbufsurface.NvBufSurfaceUnMap(surface_ptr, 0, 0)

```**Python Wrapper (ctypes):**



### GStreamer Pipeline Components```python

from draw_rect import CudaDrawRect

**Key Elements**:

- `nvurisrcbin`: Smart RTSP source with auto-decoder# Initialize

- `nvvideoconvert nvbuf-memory-type=3`: Convert to CUDA unified memorycuda_draw = CudaDrawRect('libcuda_draw.so')

- `identity`: Pass-through element for buffer probe insertion

- `nvv4l2h264enc`: Hardware H.264 encoder (NVENC)# Draw multiple rectangles

- `rtph264pay`: RTP packetization for RTSPrectangles = [

    [100, 100, 400, 300],

**Full Documentation**: See `GSTREAMER_COMPONENTS_EXPLAINED.md`    [600, 200, 200, 150],

]

### Memory Type Explanationcuda_draw.draw_rectangles(

    d_y_plane=gpu_ptr,

| Type | Name | Description | Usage |    width=1280,

|------|------|-------------|-------|    height=720,

| 0 | Default | Platform default (NVMM on Jetson) | Auto |    stride=1280,

| 1 | Pinned | CPU pinned memory | CPU processing |    rectangles=rectangles,

| 2 | NVMM | Jetson-specific GPU memory | Jetson only |    color=255

| 3 | **CUDA Unified** | **CUDA-accessible GPU memory** | **Our choice (dGPU compatible)** |)

| 4 | Surface Array | Array of surfaces | Batch processing |```



**Why Type 3**: Allows direct CUDA kernel access on both Jetson and dGPU systems.## Troubleshooting



## Troubleshooting### PyCUDA import error

```bash

### Cannot connect to output stream# Install PyCUDA

pip3 install pycuda

**Symptoms**: ffplay shows "Connection refused" or "503 Service Unavailable"

# Or in container

**Solutions**:docker run ... bash -c "pip3 install pycuda && python3 ..."

```bash```

# 1. Check containers are running

docker ps | grep draw_rect### Library not found (C++/CUDA version)

```bash

# 2. Check ports are listening# Check library exists

sudo ss -tuln | grep -E "8555|8556"ls -lh libcuda_draw.so



# 3. Check processor logs for errors# Build if missing

docker logs draw_rect_processor 2>&1 | tail -50make



# 4. Check server logs# Run from same directory as library

docker logs draw_rect_server 2>&1 | tail -50cd draw_rect

python3 draw_rect.py

# 5. Verify source is reachable```

ffprobe rtsp://172.20.96.1:8554/live

```### CUDA errors

- Verify GPU is accessible: `nvidia-smi`

### Rectangles not visible- Check CUDA version: `nvcc --version` (for C++ version) or `python3 -c "import pycuda.driver; pycuda.driver.init()"`

- Ensure proper GPU architecture in Makefile (`CUDA_ARCH`) if using C++ version

**Symptoms**: Stream plays but no rectangles

### PyCUDA compilation errors

**Solutions**:- Check GPU compute capability matches kernel code

```bash- Ensure CUDA drivers are properly installed

# 1. Check CUDA kernel is executing- Try simpler kernel first to verify PyCUDA works

docker logs draw_rect_processor | grep "Frame"

# Should see: "Frame 1: memType=3, batchSize=1"### GStreamer errors

- Verify DeepStream installation

# 2. Verify GPU pointer extraction- Check RTSP input is accessible: `ffprobe rtsp://...`

docker logs draw_rect_processor | grep "GPU memory pointer"- Ensure no port conflicts on output port

# Should see: "GPU memory pointer: 0x..."

### Performance issues

# 3. Check rectangle coordinates are within frame- Check if GPU is being used: `nvidia-smi` while running

# Edit draw_rect_processor.py, ensure x+w < width and y+h < height- Reduce number of rectangles

```- Ensure NVMM (GPU) memory is being used in pipeline



### High GPU usage## License



**Symptoms**: GPU compute usage > 20%This project is part of the deepstream_tests repository.



**Solutions**:## See Also

```bash

# 1. Check memory type is 3 (CUDA unified)- [DeepStream SDK Documentation](https://docs.nvidia.com/metropolis/deepstream/dev-guide/)

docker logs draw_rect_processor | grep "memType"- [CUDA Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/)

# Should see: "memType=3"- [GStreamer RTSP Server](https://gstreamer.freedesktop.org/documentation/gst-rtsp-server/)


# 2. Verify hardware encoder is used (should show NVENC usage, not compute)
nvidia-smi dmon -s u

# 3. Check for unnecessary synchronization
# (cudaDeviceSynchronize should NOT be called)
```

### Port conflicts

**Symptoms**: "Address already in use" errors

**Solutions**:
```bash
# Check what's using the ports
sudo ss -tulnp | grep -E "8555|8556"

# Use different ports
PROCESSOR_PORT=8557 SERVER_PORT=8558 ./run_split.sh

# Or stop conflicting services
docker stop $(docker ps -q --filter name=draw_rect)
```

## Files

### Active Files (Current Implementation)

| File | Description | Size |
|------|-------------|------|
| `draw_rect_processor.py` | Processor application (port 8555) | 321 lines |
| `draw_rect_server.py` | Server application (port 8556) | 122 lines |
| `cuda_draw.cu` | CUDA kernel source code | 218 lines |
| `libcuda_draw.so` | Compiled CUDA library | 44 MB |
| `run_split.sh` | Launch script for both apps | 102 lines |
| `Dockerfile` | Container build configuration | 18 lines |
| `Makefile` | CUDA library build script | - |

### Documentation

| File | Description |
|------|-------------|
| `README.md` | This file - main documentation |
| `GSTREAMER_COMPONENTS_EXPLAINED.md` | Deep dive into GStreamer pipeline |
| `ENCODER_ANALYSIS.md` | Why nvv4l2h264enc is best encoder |
| `PYCUDA_VS_CUDA.md` | Comparison of PyCUDA vs C++/CUDA approaches |
| `README_SPLIT.md` | Original split architecture documentation |

### Legacy/Reference Files

| File | Status | Note |
|------|--------|------|
| `draw_rect_nvbuf.py` | ⚠️ Legacy | Single-app version (has timeout issues) |
| `requirements.txt` | ⚠️ Unused | No pip packages needed (uses ctypes) |

## Building from Source

### Build CUDA Library

```bash
cd draw_rect
make
```

This compiles `cuda_draw.cu` → `libcuda_draw.so`

**Requirements**:
- CUDA Toolkit 12.0+
- nvcc compiler
- Make

### Build Docker Image

```bash
cd draw_rect
docker build -t draw_rect:latest .
```

**Base Image**: `deepstream-rust-builder:latest`

## Advanced Topics

### Encoder Performance Tuning

See `ENCODER_ANALYSIS.md` for detailed encoder optimization guide.

**Quick tips**:
```gstreamer
# Ultra-low latency
nvv4l2h264enc preset-id=1 tuning-info-id=3

# Best quality
nvv4l2h264enc preset-id=7 tuning-info-id=1

# Current (balanced)
nvv4l2h264enc bitrate=12000000 insert-sps-pps=true idrinterval=30
```

### Zero-Copy Verification

See logs for confirmation:
```bash
docker logs draw_rect_processor | grep -A 5 "BUFFER PROBE"
```

Output:
```
🎬 BUFFER PROBE ACTIVATED!
   Drawing method: CUDA kernel directly on GPU memory
   Zero-copy: True (no CPU memory allocation or cudaMemcpy)
✓ GPU memory pointer: 0x205a00000
✓ Memory location: GPU (no CPU buffer allocated)
✓ CUDA kernel will operate directly on this GPU address
```

### Monitoring Performance

```bash
# GPU utilization (encoder, decoder, memory)
nvidia-smi dmon -s u

# Container resource usage
docker stats draw_rect_processor draw_rect_server

# Pipeline state and frame counts
docker logs -f draw_rect_processor | grep Frame
```

## References

- [NVIDIA DeepStream SDK](https://developer.nvidia.com/deepstream-sdk)
- [GStreamer Documentation](https://gstreamer.freedesktop.org/documentation/)
- [NVENC Video Encoder](https://developer.nvidia.com/nvidia-video-codec-sdk)
- [NvBufSurface API](https://docs.nvidia.com/metropolis/deepstream/dev-guide/text/DS_plugin_gst-nvdspreprocess.html)
- [NV12 Format Specification](https://www.kernel.org/doc/html/latest/userspace-api/media/v4l/pixfmt-nv12.html)

## License

See main repository LICENSE file.
