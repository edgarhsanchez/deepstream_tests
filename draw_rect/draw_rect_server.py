#!/usr/bin/env python3
"""
RTSP Re-streaming Server
Reads RTSP from processor (port 8555) and re-serves on port 8556
This is Part 2 of a 2-part system for low-latency RTSP serving
"""

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib
import sys
import argparse

# Initialize GStreamer
Gst.init(None)


class FastRTSPServer:
    """RTSP server that re-streams from processor"""
    
    def __init__(self, input_rtsp, port=8556):
        self.input_rtsp = input_rtsp
        self.port = port
        self.server = None
        self.loop = None
        
        print(f"\n{'='*50}")
        print(f"Fast RTSP Re-streaming Server")
        print(f"  Input:  {self.input_rtsp}")
        print(f"  Output: rtsp://localhost:{self.port}/live")
        print(f"  Clients connect instantly")
        print(f"{'='*50}\n")
        
        self.create_server()
        
    def create_server(self):
        """Create RTSP server"""
        self.server = GstRtspServer.RTSPServer()
        self.server.set_service(str(self.port))
        
        # Create media factory
        factory = GstRtspServer.RTSPMediaFactory()
        
        # Pipeline: Read from RTSP, decode, re-encode, and serve
        pipeline_str = (
            f"rtspsrc location={self.input_rtsp} latency=0 ! "
            f"rtph264depay ! "
            f"h264parse ! "
            f"rtph264pay name=pay0 pt=96 config-interval=1"
        )
        
        factory.set_launch(pipeline_str)
        
        # Share the pipeline - all clients get the same stream
        factory.set_shared(True)
        
        # Set as live source
        factory.set_latency(0)  # Minimal latency
        
        # Mount the factory
        mount_points = self.server.get_mount_points()
        mount_points.add_factory("/live", factory)
        
        print(f"✓ RTSP server configured")
        print(f"✓ Pipeline: rtspsrc → rtph264depay → h264parse → rtph264pay")
        print(f"✓ Shared pipeline enabled (efficient multi-client)")
        
    def run(self):
        """Start the RTSP server"""
        # Attach server to default main context
        self.server.attach(None)
        
        print(f"\n🚀 RTSP server started on port {self.port}")
        print(f"📡 Mount point: /live")
        print(f"\n📺 To view the stream:")
        print(f"   ffplay rtsp://localhost:{self.port}/live")
        print(f"   vlc rtsp://localhost:{self.port}/live")
        print(f"   gst-launch-1.0 playbin uri=rtsp://localhost:{self.port}/live")
        print(f"\n⚡ Clients will connect instantly (no delay)!")
        print(f"\nPress Ctrl+C to stop\n")
        
        # Run main loop
        self.loop = GLib.MainLoop()
        try:
            self.loop.run()
        except KeyboardInterrupt:
            print("\n⏹️  Stopping RTSP server...")
        finally:
            if self.loop:
                self.loop.quit()


def main():
    parser = argparse.ArgumentParser(
        description='Fast RTSP Re-streaming Server (Part 2: Serving)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example usage:
  python3 draw_rect_server.py --input rtsp://localhost:8555/processed --port 8556

This server:
  1. Reads RTSP stream from processor (port 8555)
  2. Re-serves it via RTSP with instant connection
  3. Supports multiple clients efficiently
  4. Minimal latency

NOTE: Start draw_rect_processor.py FIRST before starting this server!
        """
    )
    parser.add_argument('--input', required=True, help='Input RTSP URI from processor')
    parser.add_argument('--port', type=int, default=8556, help='RTSP server port')
    
    args = parser.parse_args()
    
    server = FastRTSPServer(args.input, args.port)
    server.run()


if __name__ == '__main__':
    main()
