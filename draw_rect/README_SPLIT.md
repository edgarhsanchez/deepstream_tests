# CUDA Rectangle Drawing System - Split Architecture

This system draws rectangles on RTSP video streams using CUDA with **instant client connections**.

## Architecture

The system is split into two applications that communicate via shared memory:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Split Architecture Flow                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  [RTSP Source]                                                       │
│       ↓                                                              │
│  ┌─────────────────────────────────────┐                           │
│  │  App 1: Processor                   │                           │
│  │  - Connects to source RTSP once     │                           │
│  │  - Draws rectangles with CUDA       │                           │
│  │  - Encodes to H.264                 │                           │
│  │  - Outputs to shared memory         │                           │
│  └─────────────────────────────────────┘                           │
│       ↓                                                              │
│  [Shared Memory: /tmp/draw_rect_shm]                                │
│       ↓                                                              │
│  ┌─────────────────────────────────────┐                           │
│  │  App 2: RTSP Server                 │                           │
│  │  - Reads from shared memory         │                           │
│  │  - Serves via RTSP instantly        │                           │
│  │  - Multiple clients supported       │                           │
│  └─────────────────────────────────────┘                           │
│       ↓                                                              │
│  [Clients: VLC, ffplay, etc.] ← INSTANT CONNECTION! ⚡             │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

## Why Split Architecture?

### Problem with Single Application
- Creating RTSP pipeline from another RTSP source takes 10-30 seconds
- Clients timeout before pipeline is ready (503 Service Unavailable)
- Each client connection attempts to create a new pipeline

### Solution: Split Architecture
✅ **Processor runs once** - long connection time only happens at startup  
✅ **RTSP server connects instantly** - shared memory is already available  
✅ **Better separation** - processing vs serving are independent  
✅ **More robust** - if one crashes, the other continues  
✅ **Better performance** - processor runs at full speed  

## Quick Start

### Option 1: Use the launcher script (recommended)

```bash
cd draw_rect
./run_split.sh
```

### Option 2: Manual start

**Terminal 1 - Start Processor:**
```bash
docker run --rm --gpus all --network host --ipc=host \
  -v $(pwd):/workdir -v /tmp:/tmp \
  draw_rect:latest \
  python3 -u draw_rect_processor.py \
    --input rtsp://172.20.96.1:8554/live \
    --shm /tmp/draw_rect_shm \
    --width 960 \
    --height 540
```

Wait 10-30 seconds for processor to connect to source...

**Terminal 2 - Start RTSP Server:**
```bash
docker run --rm --gpus all --network host --ipc=host \
  -v /tmp:/tmp \
  draw_rect:latest \
  python3 -u draw_rect_server.py \
    --shm /tmp/draw_rect_shm \
    --port 8558
```

**Terminal 3 - View Stream:**
```bash
ffplay rtsp://localhost:8558/live
# or
vlc rtsp://localhost:8558/live
```

## Files

### Core Applications
- **`draw_rect_processor.py`** - App 1: Processes video and draws rectangles with CUDA
- **`draw_rect_server.py`** - App 2: RTSP server that serves processed stream
- **`run_split.sh`** - Helper script to run both applications

### Legacy (Single Application)
- **`draw_rect_nvbuf.py`** - Original single application (has timeout issues)

### Build Files
- **`cuda_draw.cu`** - CUDA kernel for rectangle drawing
- **`libcuda_draw.so`** - Compiled CUDA library
- **`Dockerfile`** - Docker container configuration
- **`Makefile`** - Build CUDA library

## Usage

### Environment Variables

```bash
# Customize via environment variables
export INPUT_RTSP="rtsp://192.168.1.100:8554/stream"
export OUTPUT_PORT="8558"
export WIDTH="1920"
export HEIGHT="1080"
./run_split.sh
```

### Processor Options

```
usage: draw_rect_processor.py [-h] --input INPUT [--shm SHM] 
                               [--width WIDTH] [--height HEIGHT]

  --input INPUT    Input RTSP URI (required)
  --shm SHM        Shared memory socket path (default: /tmp/draw_rect_shm)
  --width WIDTH    Video width (default: 960)
  --height HEIGHT  Video height (default: 540)
```

### Server Options

```
usage: draw_rect_server.py [-h] [--shm SHM] [--port PORT]

  --shm SHM      Shared memory socket path (default: /tmp/draw_rect_shm)
  --port PORT    RTSP server port (default: 8558)
```

## Monitoring

### View Processor Logs
```bash
docker logs -f draw_rect_processor
```

### View Server Logs
```bash
docker logs -f draw_rect_server
```

### Check if Shared Memory is Working
```bash
ls -lh /tmp/draw_rect_shm
```

## Stopping

If using `run_split.sh`:
- Press **Ctrl+C** to stop both containers

If running manually:
```bash
docker stop draw_rect_processor draw_rect_server
```

## Performance

### Connection Times
- **Old single app**: 10-30 seconds (clients timeout)
- **New split app**: <1 second (instant) ⚡

### Resource Usage
- **Processor**: High (CUDA, encoding)
- **Server**: Low (just reads and serves)

### Latency
- **Shared memory**: ~10-50ms
- **End-to-end**: ~100-200ms

## Troubleshooting

### "503 Service Unavailable"
- Make sure processor is started FIRST
- Wait 10-30 seconds for processor to connect to source
- Check processor logs: `docker logs draw_rect_processor`

### No video / black screen
- Verify source RTSP stream is accessible:
  ```bash
  ffprobe rtsp://172.20.96.1:8554/live
  ```
- Check resolution matches source (use `--width` and `--height`)

### Shared memory errors
- Ensure `--ipc=host` is used for both containers
- Check `/tmp/draw_rect_shm` exists after processor starts
- Verify both containers can access `/tmp`

### CUDA errors
- Ensure `--gpus all` is used
- Check GPU is available: `nvidia-smi`
- Verify CUDA library loads: check processor startup logs

## Technical Details

### Zero-Copy GPU Processing
1. RTSP frames arrive in NVMM GPU memory
2. NvBufSurface API provides direct GPU pointer
3. CUDA kernel draws rectangles directly on GPU
4. No CPU-GPU memory transfers needed

### Shared Memory (shmsink/shmsrc)
- **Protocol**: GStreamer shared memory plugin
- **Location**: `/tmp/draw_rect_shm` (Unix socket)
- **Format**: H.264 byte-stream
- **Benefits**: Zero-copy between processes, low latency

### Memory Type
- **NVMM (type 2)**: Jetson only
- **CUDA Unified (type 3)**: dGPU (used here)

## Comparison with Single Application

| Feature | Single App | Split App |
|---------|-----------|-----------|
| Connection time | 10-30 seconds | <1 second |
| Client timeout | Yes (503 errors) | No |
| Multiple clients | Creates new pipeline each time | Shares single stream |
| Resource usage | High per client | High (processor) + Low (server) |
| Robustness | Single point of failure | Independent components |
| Debugging | Harder | Easier (separate logs) |

## Credits

- **DeepStream SDK 8.0**: NVIDIA video processing framework
- **CUDA 12.8.1**: GPU-accelerated rectangle drawing
- **GStreamer 1.x**: Multimedia pipeline framework
- **NvBufSurface API**: Zero-copy GPU memory access
