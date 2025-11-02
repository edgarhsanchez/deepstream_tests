#!/usr/bin/env python3
"""
CUDA Rectangle Drawing Processor
Receives RTSP input, draws rectangles with CUDA, outputs to RTSP on port 8555
This is Part 1 of a 2-part system for low-latency RTSP serving
"""

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib
import ctypes
from ctypes import Structure, POINTER, c_void_p, c_uint32, c_int, c_uint64
import sys
import argparse
import signal
import traceback

# Initialize GStreamer
Gst.init(None)

# NvBufSurface structures for zero-copy GPU access
class NvBufSurfacePlaneParams(Structure):
    _fields_ = [
        ('num_planes', c_uint32),
        ('width', c_uint32 * 4),
        ('height', c_uint32 * 4),
        ('pitch', c_uint32 * 4),
        ('offset', c_uint32 * 4),
        ('psize', c_uint32 * 4),
        ('bytesPerPix', c_uint32 * 4),
    ]

class NvBufSurfaceParams(Structure):
    _fields_ = [
        ('width', c_uint32),
        ('height', c_uint32),
        ('pitch', c_uint32),
        ('colorFormat', c_int),
        ('layout', c_int),
        ('bufferDesc', c_uint64),
        ('dataSize', c_uint32),
        ('dataPtr', c_void_p),
        ('planeParams', NvBufSurfacePlaneParams),
        ('mappedAddr', POINTER(c_void_p)),
        ('_reserved', c_void_p * 3),
    ]

class NvBufSurface(Structure):
    _fields_ = [
        ('gpuId', c_uint32),
        ('batchSize', c_uint32),
        ('numFilled', c_uint32),
        ('isContiguous', c_int),
        ('memType', c_int),
        ('surfaceList', POINTER(NvBufSurfaceParams)),
        ('_reserved', c_void_p * 4),
    ]

# Rectangle structure for CUDA
class Rectangle(Structure):
    _fields_ = [
        ('x', c_int),
        ('y', c_int),
        ('width', c_int),
        ('height', c_int),
    ]

# Load libraries
try:
    libcuda_draw = ctypes.CDLL('/workdir/libcuda_draw.so')
    print(f"✓ Loaded CUDA library: /workdir/libcuda_draw.so")
except Exception as e:
    print(f"✗ Failed to load CUDA library: {e}")
    sys.exit(1)

try:
    libnvbufsurface = ctypes.CDLL('/opt/nvidia/deepstream/deepstream/lib/libnvbufsurface.so')
except Exception as e:
    print(f"✗ Failed to load NvBufSurface library: {e}")
    sys.exit(1)

# Setup function signatures
libcuda_draw.draw_rectangles.argtypes = [
    c_void_p, c_int, c_int, c_int,
    POINTER(Rectangle), c_int, c_int, c_void_p
]
libcuda_draw.draw_rectangles.restype = None

NVBUF_MAP_READ_WRITE = 1 | 2
libnvbufsurface.NvBufSurfaceMap.argtypes = [POINTER(NvBufSurface), c_int, c_int, c_int]
libnvbufsurface.NvBufSurfaceMap.restype = c_int
libnvbufsurface.NvBufSurfaceUnMap.argtypes = [POINTER(NvBufSurface), c_int, c_int]
libnvbufsurface.NvBufSurfaceUnMap.restype = c_int
libnvbufsurface.NvBufSurfaceSyncForDevice.argtypes = [POINTER(NvBufSurface), c_int, c_int]
libnvbufsurface.NvBufSurfaceSyncForDevice.restype = c_int


class DrawRectProcessor:
    """Processes video stream and draws rectangles using CUDA"""
    
    def __init__(self, rtsp_input, rtsp_port, width=960, height=540):
        self.rtsp_input = rtsp_input
        self.rtsp_port = rtsp_port
        self.width = width
        self.height = height
        self.pipeline = None
        self.server = None
        self.loop = None
        
        # Define rectangles to draw (example: 3 rectangles)
        self.rectangles = [
            Rectangle(100, 100, 200, 150),
            Rectangle(400, 200, 300, 200),
            Rectangle(150, 350, 250, 100),
        ]
        
        print(f"\n{'='*50}")
        print(f"CUDA Rectangle Drawing Processor")
        print(f"  Input:  {self.rtsp_input}")
        print(f"  Output: rtsp://localhost:{self.rtsp_port}/processed")
        print(f"  Size:   {self.width}x{self.height}")
        print(f"  Rectangles: {len(self.rectangles)}")
        print(f"  Method: NvBufSurface + CUDA (zero-copy GPU)")
        print(f"{'='*50}\n")
        
        self.create_rtsp_server()
        self.create_pipeline()
    
    def create_rtsp_server(self):
        """Create RTSP server to serve the processed stream"""
        self.server = GstRtspServer.RTSPServer()
        self.server.set_service(str(self.rtsp_port))
        
        factory = GstRtspServer.RTSPMediaFactory()
        factory.set_shared(True)
        factory.set_latency(0)
        
        # Store factory for later use in create_pipeline
        self.factory = factory
        
        mount_points = self.server.get_mount_points()
        mount_points.add_factory("/processed", factory)
        
        self.server.attach(None)
        print(f"✓ RTSP server configured on port {self.rtsp_port}")
        print(f"✓ Mount point: /processed")
        
    def create_pipeline(self):
        """Create the GStreamer pipeline"""
        pipeline_str = (
            f"nvurisrcbin uri={self.rtsp_input} ! "
            f"nvvideoconvert nvbuf-memory-type=3 ! "
            f"video/x-raw(memory:NVMM),format=NV12,width={self.width},height={self.height} ! "
            f"identity name=draw_point ! "
            f"queue max-size-buffers=2 leaky=downstream ! "
            f"nvvideoconvert ! "
            f"video/x-raw(memory:NVMM),format=I420 ! "
            f"nvv4l2h264enc bitrate=12000000 insert-sps-pps=true idrinterval=30 ! "
            f"video/x-h264,stream-format=byte-stream,alignment=au ! "
            f"h264parse config-interval=-1 ! "
            f"rtph264pay name=pay0 pt=96 config-interval=1"
        )
        
        # Set the pipeline on the factory - RTSP will create it on demand
        self.factory.set_launch(pipeline_str)
        
        print(f"✓ Pipeline configured: nvurisrcbin → CUDA drawing → H.264 → RTSP")
        
        # Connect to media-configure signal to add buffer probe when client connects
        self.factory.connect("media-configure", self.on_media_configure)
    
    def on_media_configure(self, factory, media):
        """Called when a client connects - add buffer probe to the pipeline"""
        pipeline = media.get_element()
        
        # Get identity element and add buffer probe
        identity = pipeline.get_by_name("draw_point")
        if identity:
            pad = identity.get_static_pad("src")
            if pad:
                pad.add_probe(Gst.PadProbeType.BUFFER, self.on_buffer_probe)
                print(f"✓ Buffer probe added to pipeline for client connection")
        
    def on_buffer_probe(self, pad, info):
        """Buffer probe callback - draws rectangles using CUDA"""
        try:
            if not hasattr(self, '_frame_count'):
                self._frame_count = 0
                print(f"🎬 BUFFER PROBE ACTIVATED!")
                print(f"   Drawing method: CUDA kernel directly on GPU memory")
                print(f"   Zero-copy: True (no CPU memory allocation or cudaMemcpy)")
            
            self._frame_count += 1
            
            # Get GStreamer buffer
            gst_buffer = info.get_buffer()
            success, map_info = gst_buffer.map(Gst.MapFlags.READ)
            
            if not success:
                print(f"✗ Failed to map buffer")
                return Gst.PadProbeReturn.OK
            
            try:
                # Cast to NvBufSurface
                surface_ptr = ctypes.cast(map_info.data, POINTER(NvBufSurface))
                surface = surface_ptr.contents
                
                if self._frame_count % 60 == 1:  # Log every 60 frames (~1 second at 60fps)
                    print(f"🔍 Frame {self._frame_count}: memType={surface.memType}, batchSize={surface.batchSize}")
                
                # Map surface for GPU access
                ret = libnvbufsurface.NvBufSurfaceMap(surface_ptr, 0, 0, NVBUF_MAP_READ_WRITE)
                if ret != 0:
                    print(f"✗ NvBufSurfaceMap failed: {ret}")
                    gst_buffer.unmap(map_info)
                    return Gst.PadProbeReturn.OK
                
                # Get GPU memory pointer
                batch_id = 0
                params = surface.surfaceList[batch_id]
                device_ptr = params.dataPtr
                width = params.width
                height = params.height
                pitch = params.pitch
                
                if self._frame_count == 1:
                    print(f"✓ Surface mapped: {width}x{height}, pitch={pitch}")
                    print(f"✓ GPU memory pointer: {hex(device_ptr)}")
                    print(f"✓ Memory location: GPU (no CPU buffer allocated)")
                    print(f"✓ CUDA kernel will operate directly on this GPU address")
                
                # Draw rectangles using CUDA (zero-copy)
                # device_ptr is already a GPU address - no cudaMalloc or cudaMemcpy needed
                # The CUDA kernel writes directly to this GPU memory location
                rects_array = (Rectangle * len(self.rectangles))(*self.rectangles)
                libcuda_draw.draw_rectangles(
                    device_ptr,      # GPU pointer (no CPU memory involved)
                    width,
                    height,
                    pitch,
                    rects_array,
                    len(self.rectangles),
                    255,             # white color
                    None             # default CUDA stream
                )
                
                # Sync back to device (non-blocking)
                libnvbufsurface.NvBufSurfaceSyncForDevice(surface_ptr, batch_id, 0)
                
                # Unmap surface
                libnvbufsurface.NvBufSurfaceUnMap(surface_ptr, batch_id, 0)
                
            finally:
                gst_buffer.unmap(map_info)
                
        except Exception as e:
            if self._frame_count < 10:  # Only print first few errors
                print(f"✗ Error in buffer probe: {e}")
                traceback.print_exc()
        
        return Gst.PadProbeReturn.OK
    
    def on_error(self, bus, message):
        """Handle pipeline errors"""
        err, debug = message.parse_error()
        print(f"❌ PIPELINE ERROR: {err.message}")
        print(f"   Debug: {debug}")
        self.stop()
    
    def run(self):
        """Start RTSP server"""
        print(f"\n🚀 Starting RTSP server on port {self.rtsp_port}...")
        print(f"� Stream will be available at: rtsp://localhost:{self.rtsp_port}/processed")
        print(f"⏳ Pipeline will connect to source when a client requests the stream")
        print(f"\nPress Ctrl+C to stop\n")
        
        # Run main loop
        self.loop = GLib.MainLoop()
        try:
            self.loop.run()
        except KeyboardInterrupt:
            print("\n⏹️  Stopping processor...")
        finally:
            self.stop()
    
    def stop(self):
        """Stop the server"""
        if self.loop:
            self.loop.quit()


def main():
    parser = argparse.ArgumentParser(
        description='CUDA Rectangle Drawing Processor (Part 1: Processing)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example usage:
  python3 draw_rect_processor.py --input rtsp://172.20.96.1:8554/live --port 8555

This processor:
  1. Creates RTSP server on specified port
  2. When client connects, fetches from source RTSP
  3. Draws rectangles with CUDA on GPU
  4. Encodes to H.264 and serves via RTSP
        """
    )
    parser.add_argument('--input', required=True, help='Input RTSP URI')
    parser.add_argument('--port', type=int, default=8555, help='RTSP output port')
    parser.add_argument('--width', type=int, default=960, help='Video width')
    parser.add_argument('--height', type=int, default=540, help='Video height')
    
    args = parser.parse_args()
    
    processor = DrawRectProcessor(args.input, args.port, args.width, args.height)
    processor.run()


if __name__ == '__main__':
    main()
