#!/usr/bin/env python3
"""
Draw rectangles on video frames using CUDA kernels with zero-copy NvBufSurface.
Reads from RTSP source and outputs to RTSP server.
Uses NvBufSurface API to access GPU memory directly - NO CPU TRANSFER!
Based on: https://forums.developer.nvidia.com/t/338908
"""

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib
import sys
import os
import ctypes
import argparse
from ctypes import c_void_p, c_int, c_uint32, c_uint64, c_ubyte, POINTER, Structure

# Initialize GStreamer
Gst.init(None)

# Load libraries
libnvbufsurface = ctypes.CDLL('/opt/nvidia/deepstream/deepstream/lib/libnvbufsurface.so')
libcuda_draw = None  # Will be loaded later

# NvBufSurface structures (simplified for our use)
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

class NvBufSurfaceMappedAddr(Structure):
    _fields_ = [
        ('addr', c_void_p * 4),
        ('eglImage', c_void_p),
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
        ('dataPtr', c_void_p),  # This is the GPU pointer!
        ('planeParams', NvBufSurfacePlaneParams),
        ('mappedAddr', NvBufSurfaceMappedAddr),
    ]

class NvBufSurface(Structure):
    _fields_ = [
        ('gpuId', c_uint32),
        ('batchSize', c_uint32),
        ('numFilled', c_uint32),
        ('isContiguous', c_int),
        ('memType', c_int),
        ('surfaceList', POINTER(NvBufSurfaceParams)),
    ]

# NvBufSurface API functions
libnvbufsurface.NvBufSurfaceMap.argtypes = [POINTER(NvBufSurface), c_int, c_int, c_int]
libnvbufsurface.NvBufSurfaceMap.restype = c_int

libnvbufsurface.NvBufSurfaceUnMap.argtypes = [POINTER(NvBufSurface), c_int, c_int]
libnvbufsurface.NvBufSurfaceUnMap.restype = c_int

libnvbufsurface.NvBufSurfaceSyncForDevice.argtypes = [POINTER(NvBufSurface), c_int, c_int]
libnvbufsurface.NvBufSurfaceSyncForDevice.restype = c_int

# Constants
NVBUF_MAP_READ_WRITE = 3


class RTSPDrawRectServer:
    """RTSP server that draws rectangles using CUDA with zero-copy"""
    
    def __init__(self, rtsp_input, rtsp_port=8558, width=1280, height=720):
        self.rtsp_input = rtsp_input
        self.rtsp_port = rtsp_port
        self.width = width
        self.height = height
        
        # Define rectangles to draw [x, y, width, height]
        self.rectangles = [
            [50, 50, 600, 400],      # Large rectangle - upper left
            [700, 100, 500, 300],    # Large rectangle - upper right
            [200, 500, 800, 150],    # Wide rectangle - bottom
        ]
        
        print(f"\n========================================")
        print(f"Draw Rectangles with CUDA (Zero-Copy)")
        print(f"  Input:  {self.rtsp_input}")
        print(f"  Output: rtsp://localhost:{self.rtsp_port}/draw-rect")
        print(f"  Size:   {self.width}x{self.height}")
        print(f"  Rectangles: {len(self.rectangles)}")
        print(f"  Method: NvBufSurface + CUDA (zero-copy GPU)")
        print(f"========================================\n")
        
        # Load CUDA library
        try:
            global libcuda_draw
            lib_path = os.path.join(os.path.dirname(__file__), 'libcuda_draw.so')
            libcuda_draw = ctypes.CDLL(lib_path)
            
            # Define CUDA function signature
            # cudaError_t draw_rectangles(
            #     unsigned char* d_y_plane, int width, int height, int stride,
            #     int* rectangles, int num_rects, unsigned char color, cudaStream_t stream
            # )
            libcuda_draw.draw_rectangles.argtypes = [
                c_void_p,  # d_y_plane (GPU pointer!)
                c_int,     # width
                c_int,     # height
                c_int,     # stride
                POINTER(c_int),  # rectangles array
                c_int,     # num_rects
                c_ubyte,   # color
                c_void_p   # stream
            ]
            libcuda_draw.draw_rectangles.restype = c_int
            
            print(f"✓ Loaded CUDA library: {lib_path}\n")
        except Exception as e:
            print(f"⚠ Failed to load CUDA library: {e}")
            print("  Rectangles will not be drawn\n")
        
        # Create RTSP server
        self.server = GstRtspServer.RTSPServer()
        self.server.set_service(str(self.rtsp_port))
        
        # Connect client signals
        self.server.connect("client-connected", self.on_client_connected)
        
        # Create media factory
        factory = GstRtspServer.RTSPMediaFactory()
        pipeline_str = self.create_pipeline_description()
        factory.set_launch(pipeline_str)
        
        # Share the pipeline - single source, multiple viewers
        factory.set_shared(True)
        
        # Enable reusable streams
        factory.set_eos_shutdown(True)
        
        # Set latency to help with buffering  
        factory.set_latency(200)  # 200ms latency
        
        # Connect signals to add buffer probe
        factory.connect("media-configure", self.on_media_configure)
        factory.connect("media-constructed", self.on_media_constructed)
        
        # Mount factory
        mount_points = self.server.get_mount_points()
        mount_points.add_factory("/draw-rect", factory)
        
        # Attach server to default main context
        self.server.attach(None)
        
        print(f"RTSP server started on port {self.rtsp_port}")
        print(f"Mount point: /draw-rect")
        print(f"\nTo view the stream, run:")
        print(f"  ffplay rtsp://localhost:{self.rtsp_port}/draw-rect")
        print(f"  or: vlc rtsp://localhost:{self.rtsp_port}/draw-rect")
        print(f"\nPress Ctrl+C to stop the server\n")
        
        # Run main loop
        self.loop = GLib.MainLoop()
        try:
            self.loop.run()
        except KeyboardInterrupt:
            print("\nStopping server...")
        finally:
            if self.loop:
                self.loop.quit()
    
    def create_pipeline_description(self):
        """Create GStreamer pipeline string"""
        # Use CUDA unified memory for dGPU systems - zero copy!
        # nvbuf-memory-type=3 is CUDA unified (works with NvBufSurfaceMap on dGPU)
        pipeline = (
            f"nvurisrcbin uri={self.rtsp_input} ! "
            f"nvvideoconvert nvbuf-memory-type=3 ! "
            f"video/x-raw(memory:NVMM),format=NV12,width={self.width},height={self.height} ! "
            f"identity name=draw_point ! "  # Our drawing happens here
            f"queue max-size-buffers=2 leaky=downstream ! "  # Buffer to smooth pipeline
            f"nvvideoconvert ! "
            f"video/x-raw(memory:NVMM),format=I420 ! "
            f"nvv4l2h264enc bitrate=12000000 insert-sps-pps=true preset-level=1 idrinterval=30 ! "  # Match source bitrate, add keyframes
            f"video/x-h264,stream-format=byte-stream,alignment=au,profile=baseline ! "  # Explicit format for compatibility
            f"h264parse config-interval=-1 ! "  # Insert SPS/PPS before every IDR
            f"rtph264pay name=pay0 pt=96 config-interval=1 mtu=1400"  # Send SPS/PPS with every keyframe, reduce MTU
        )
        return pipeline
    
    def on_buffer_probe(self, pad, info):
        """Buffer probe - draws rectangles using CUDA on GPU memory"""
        try:
            if not hasattr(self, '_frame_count'):
                self._frame_count = 0
                print(f"🎬 BUFFER PROBE ACTIVATED! Zero-copy CUDA drawing starting...")
            
            self._frame_count += 1
            if self._frame_count % 30 == 0:
                print(f"📹 Frame {self._frame_count}: Drawing {len(self.rectangles)} rectangles via CUDA")
            
            gst_buffer = info.get_buffer()
            if gst_buffer is None:
                return Gst.PadProbeReturn.OK
            
            # Map buffer READ-ONLY to access NvBufSurface structure
            # (We'll use NvBufSurfaceMap for GPU write access)
            success, map_info = gst_buffer.map(Gst.MapFlags.READ)
            if not success:
                return Gst.PadProbeReturn.OK
            
            try:
                # Cast to NvBufSurface pointer
                surface_ptr = ctypes.cast(map_info.data, POINTER(NvBufSurface))
                surface = surface_ptr.contents
                
                # Process first batch (batch_id = 0)
                batch_id = 0
                plane = 0  # Plane 0 is Y plane for NV12
                
                # Check memory type (should be 3 for CUDA unified)
                if self._frame_count == 1:
                    print(f"🔍 Surface memType={surface.memType}, batchSize={surface.batchSize}")
                
                # Map surface for GPU access
                map_result = libnvbufsurface.NvBufSurfaceMap(surface_ptr, batch_id, plane, NVBUF_MAP_READ_WRITE)
                if self._frame_count == 1:
                    print(f"🗺️  NvBufSurfaceMap result: {map_result}")
                
                if map_result != 0:
                    if self._frame_count == 1:
                        print(f"❌ Failed to map NvBufSurface (error code: {map_result})")
                    return Gst.PadProbeReturn.OK
                
                # Get surface parameters  
                params = surface.surfaceList[batch_id]
                device_ptr = params.dataPtr  # This is the GPU pointer!
                width = params.width
                height = params.height
                pitch = params.pitch
                
                if self._frame_count == 1:
                    print(f"✓ Surface mapped: {width}x{height}, pitch={pitch}, GPU ptr={hex(device_ptr) if device_ptr else 'NULL'}")
                
                # Prepare rectangles array for CUDA
                rects_flat = []
                for rect in self.rectangles:
                    rects_flat.extend(rect)
                rects_array = (c_int * len(rects_flat))(*rects_flat)
                
                # Call CUDA kernel directly on GPU memory - ZERO COPY!
                if libcuda_draw:
                    err = libcuda_draw.draw_rectangles(
                        device_ptr,      # GPU pointer from NvBufSurface!
                        width,
                        height,
                        pitch,
                        rects_array,
                        len(self.rectangles),
                        255,  # White color
                        None  # No stream (use default)
                    )
                    
                    if err != 0 and self._frame_count == 1:
                        print(f"⚠ CUDA error: {err}")
                
                # Sync buffer back to device (non-blocking, handled by driver)
                libnvbufsurface.NvBufSurfaceSyncForDevice(surface_ptr, batch_id, 0)
                
                # Unmap surface
                libnvbufsurface.NvBufSurfaceUnMap(surface_ptr, batch_id, plane)
                
            finally:
                gst_buffer.unmap(map_info)
        
        except Exception as e:
            if self._frame_count <= 1:
                print(f"❌ Error in buffer probe: {e}")
                import traceback
                traceback.print_exc()
        
        return Gst.PadProbeReturn.OK
    
    def on_client_connected(self, server, client):
        """Called when a client connects"""
        print(f"👤 Client connected: {client}")
    
    def on_pipeline_error(self, bus, message):
        """Handle pipeline errors"""
        err, debug = message.parse_error()
        print(f"❌ PIPELINE ERROR: {err.message}")
        print(f"   Debug info: {debug}")
    
    def on_pipeline_warning(self, bus, message):
        """Handle pipeline warnings"""
        warn, debug = message.parse_warning()
        print(f"⚠️  PIPELINE WARNING: {warn.message}")
        print(f"   Debug info: {debug}")
    
    def on_pipeline_state_changed(self, bus, message):
        """Monitor pipeline state changes"""
        if message.src.get_name().startswith("media-pipeline"):
            old_state, new_state, pending = message.parse_state_changed()
            print(f"🔄 Pipeline state: {old_state.value_nick} → {new_state.value_nick}")
    
    def on_media_configure(self, factory, media):
        """Called when media is configured"""
        print(f"⚠️ Media configured callback")
        element = media.get_element()
        if element:
            print(f"   Pipeline: {element.get_name()}")
            # Add bus monitoring
            bus = element.get_bus()
            if bus:
                bus.add_signal_watch()
                bus.connect("message::error", self.on_pipeline_error)
                bus.connect("message::warning", self.on_pipeline_warning)
                bus.connect("message::state-changed", self.on_pipeline_state_changed)
                print("   ✓ Added bus error/warning monitors")
        self._add_probe_to_media(media)
    
    def on_media_constructed(self, factory, media):
        """Called when media is constructed"""
        print(f"🔧 Media constructed callback")
        self._add_probe_to_media(media)
    
    def _add_probe_to_media(self, media):
        """Helper to add buffer probe to media pipeline"""
        try:
            print(f"🔍 Adding buffer probe to pipeline...")
            element = media.get_element()
            if not element:
                print(f"✗ Failed to get media element")
                return
            
            # Find identity element
            identity = element.get_by_name("draw_point")
            if not identity:
                print(f"✗ Could not find 'draw_point' identity element")
                return
            
            # Add probe to source pad
            src_pad = identity.get_static_pad("src")
            if not src_pad:
                print(f"✗ Could not get src pad from identity")
                return
            
            probe_id = src_pad.add_probe(
                Gst.PadProbeType.BUFFER,
                self.on_buffer_probe
            )
            
            print(f"✓✓✓ Buffer probe added successfully! Probe ID: {probe_id}")
        except Exception as e:
            print(f"❌ Failed to add probe: {e}")
            import traceback
            traceback.print_exc()


def main():
    parser = argparse.ArgumentParser(description='Draw rectangles on RTSP stream using zero-copy CUDA')
    parser.add_argument('--input', type=str, required=True,
                        help='Input RTSP URL (e.g., rtsp://172.20.96.1:8554/live)')
    parser.add_argument('--port', type=int, default=8558,
                        help='Output RTSP port (default: 8558)')
    parser.add_argument('--width', type=int, default=1280,
                        help='Video width (default: 1280)')
    parser.add_argument('--height', type=int, default=720,
                        help='Video height (default: 720)')
    
    args = parser.parse_args()
    
    server = RTSPDrawRectServer(args.input, args.port, args.width, args.height)
    
    # This will run indefinitely until Ctrl+C
    try:
        server.loop.run()
    except KeyboardInterrupt:
        print("\n\nStopping server...")
        server.loop.quit()


if __name__ == '__main__':
    main()
