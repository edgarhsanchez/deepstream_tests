#!/usr/bin/env python3
"""
DeepStream Object Detection with RTSP Streaming
GPU-accelerated object detection using YOLO11 models with optional RTSP output
"""

import sys
import os
import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GLib, GstRtspServer

def create_filtered_config(base_config, target_object):
    """Create a filtered config that only detects the target object"""
    
    # Read labels to find class ID
    labels_path = "/models/labels.txt"
    target_class_id = None
    
    try:
        with open(labels_path, 'r') as f:
            for idx, line in enumerate(f):
                if line.strip() == target_object:
                    target_class_id = idx
                    break
    except FileNotFoundError:
        print(f"Warning: Could not find '{labels_path}'")
        return base_config, None
    
    if target_class_id is None:
        print(f"Warning: Could not find '{target_object}' in labels file")
        print("Class filtering: DISABLED - Showing all detections")
        return base_config, None
    
    print(f"Target object '{target_object}' (class ID: {target_class_id})")
    print("Class filtering: ENABLED - Only showing '{}' detections".format(target_object))
    
    # Read base config
    try:
        with open(base_config, 'r') as f:
            config_content = f.read()
    except FileNotFoundError:
        print(f"Error: Config file not found: {base_config}")
        return base_config, None
    
    # Create filtered config
    temp_config_path = "/tmp/config_infer_filtered.txt"
    new_config = []
    in_class_attrs = False
    
    for line in config_content.split('\n'):
        if line.strip().startswith('[class-attrs-all]'):
            in_class_attrs = True
            continue
        elif in_class_attrs and line.strip().startswith('['):
            in_class_attrs = False
        
        if not in_class_attrs:
            # Fix the model-engine-file path to point to /workdir
            if line.strip().startswith('model-engine-file='):
                # Extract just the filename and point to /workdir
                original_path = line.split('=', 1)[1].strip()
                filename = os.path.basename(original_path)
                # Change to the actual generated engine name
                if 'yolo11s' in filename:
                    line = 'model-engine-file=/workdir/model_b1_gpu0_fp32.engine'
                elif 'yolo11n' in filename:
                    line = 'model-engine-file=/workdir/yolo11n_b1_gpu0_fp32.engine'
            new_config.append(line)
    
    # Add filtered class attributes for target class
    new_config.append(f"\n[class-attrs-{target_class_id}]")
    new_config.append("pre-cluster-threshold=0.25")
    
    # Add high threshold for all other classes to hide them
    new_config.append("\n[class-attrs-all]")
    new_config.append("pre-cluster-threshold=1.0")  # Impossible threshold to hide other classes
    
    # Write filtered config
    with open(temp_config_path, 'w') as f:
        f.write('\n'.join(new_config))
    
    print(f"✓ Created filtered config: {temp_config_path}")
    return temp_config_path, target_class_id


def setup_rtsp_server(pipeline_str, port, mount_point):
    """Setup RTSP server with the detection pipeline"""
    
    server = GstRtspServer.RTSPServer.new()
    server.props.service = port
    
    factory = GstRtspServer.RTSPMediaFactory.new()
    factory.set_launch(pipeline_str)
    factory.set_shared(True)
    
    # Connect to factory signals for debugging
    def on_media_constructed(factory, media):
        print("DEBUG: Media constructed")
        
        def on_new_stream(media, stream):
            print(f"DEBUG: New stream created: {stream}")
        
        def on_prepared(media):
            print("DEBUG: Media prepared")
        
        media.connect("new-stream", on_new_stream)
        media.connect("prepared", on_prepared)
    
    factory.connect("media-constructed", on_media_constructed)
    
    # Add factory to mount points
    mounts = server.get_mount_points()
    mounts.add_factory(mount_point, factory)
    
    # Connect to server signals
    def on_client_connected(server, client):
        print(f"DEBUG: Client connected: {client}")
    
    server.connect("client-connected", on_client_connected)
    
    print(f"DEBUG: RTSP server configured for 0.0.0.0:{port}")
    print(f"DEBUG: Mount point: {mount_point}")
    
    return server


def main():
    # Initialize GStreamer
    Gst.init(None)
    
    # Get environment variables
    device = os.getenv('GST_DEVICE') or os.getenv('RTSP_URL') or 'test'
    target_object = os.getenv('DETECT_OBJECT', 'person')
    model_config = os.getenv('MODEL_CONFIG', '/models/config_infer_yolo11s.txt')
    model_engine = os.getenv('MODEL_ENGINE', '')
    show_display = os.getenv('SHOW_DISPLAY', 'true').lower() == 'true'
    rtsp_output = os.getenv('RTSP_OUTPUT')
    rtsp_port = os.getenv('RTSP_OUTPUT_PORT', '8555')
    output_width = os.getenv('OUTPUT_WIDTH', '1920')
    output_height = os.getenv('OUTPUT_HEIGHT', '1080')
    
    # Create filtered config
    final_config, target_class_id = create_filtered_config(model_config, target_object)
    
    # Build pipeline based on input source
    if device.startswith('rtsp://'):
        source_pipeline = (
            f"nvurisrcbin uri={device} ! "
            f"nvvideoconvert interpolation-method=5 ! "
            f"m.sink_0 nvstreammux name=m width={output_width} height={output_height} batch-size=1 ! "
            f"nvinfer config-file-path={final_config} ! "
            f"nvdsosd"
        )
    elif os.path.exists(device) and device.startswith('/dev/video'):
        source_pipeline = (
            f"v4l2src device={device} ! "
            f"nvvideoconvert interpolation-method=5 ! "
            f"m.sink_0 nvstreammux name=m width={output_width} height={output_height} batch-size=1 ! "
            f"nvinfer config-file-path={final_config} ! "
            f"nvdsosd"
        )
    else:
        # Test pattern
        source_pipeline = (
            f"videotestsrc ! "
            f"nvvideoconvert interpolation-method=5 ! "
            f"m.sink_0 nvstreammux name=m width={output_width} height={output_height} batch-size=1 ! "
            f"nvinfer config-file-path={final_config} ! "
            f"nvdsosd"
        )
    
    # Output sink
    if rtsp_output:
        output_sink = (
            f"nvvideoconvert ! video/x-raw(memory:NVMM),format=I420 ! "
            f"nvv4l2h264enc bitrate=4000000 insert-sps-pps=true ! "
            f"h264parse ! rtph264pay name=pay0 pt=96"
        )
    elif show_display:
        output_sink = "nvvideoconvert ! nveglglessink"
    else:
        output_sink = "fakesink"
    
    pipeline_str = f"{source_pipeline} ! {output_sink}"
    
    # Print pipeline info
    print("DeepStream Object Detection Pipeline")
    print(f"  Input: {device}")
    print(f"  Target Object: {target_object}")
    print(f"  Model Engine: {model_engine}")
    print(f"  Model Config: {final_config}")
    print(f"  Display: {'enabled' if show_display else 'disabled'}")
    if rtsp_output:
        print(f"  RTSP Stream: rtsp://localhost:{rtsp_port}/ds-detect")
    print(f"  Pipeline: {pipeline_str}")
    print(f"  Output: {output_sink}")
    print("\nNote: This uses DeepStream's nvinfer element for GPU-accelerated inference")
    print("      nvdsosd draws bounding boxes and labels on detected objects")
    print("      You can customize the model by setting MODEL_CONFIG environment variable")
    
    # Handle RTSP server if RTSP output is enabled
    if rtsp_output:
        print(f"      RTSP stream available at rtsp://localhost:{rtsp_port}/ds-detect")
        print(f"      View with: ffplay rtsp://localhost:{rtsp_port}/ds-detect")
        print("\nStarting RTSP server...")
        
        print(f"DEBUG: Setting pipeline: {pipeline_str}")
        
        # Create RTSP server
        server = setup_rtsp_server(pipeline_str, rtsp_port, "/ds-detect")
        
        # Attach server to main context
        server.attach(None)
        
        print(f"RTSP server started on port {rtsp_port}")
        print(f"Server bound to 0.0.0.0:{rtsp_port}")
        print("Waiting for RTSP clients to connect...")
        print("Press Ctrl+C to stop the server")
        
        # Run main loop
        loop = GLib.MainLoop()
        try:
            loop.run()
        except KeyboardInterrupt:
            print("\nStopping RTSP server...")
        
        return
    
    # Create pipeline (only if not using RTSP server)
    pipeline = Gst.parse_launch(pipeline_str)
    
    # Get bus for messages
    bus = pipeline.get_bus()
    bus.add_signal_watch()
    
    def on_message(bus, message):
        t = message.type
        if t == Gst.MessageType.EOS:
            print("End of stream")
            loop.quit()
        elif t == Gst.MessageType.ERROR:
            err, debug = message.parse_error()
            print(f"Error from {message.src.get_name()}: {err.message}")
            if debug:
                print(f"Debug info: {debug}")
            loop.quit()
        elif t == Gst.MessageType.STATE_CHANGED:
            if message.src == pipeline:
                old_state, new_state, pending_state = message.parse_state_changed()
                print(f"Pipeline state changed from {old_state.value_nick} to {new_state.value_nick}")
    
    bus.connect("message", on_message)
    
    # Start playing
    pipeline.set_state(Gst.State.PLAYING)
    
    # Run main loop
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        print("\nStopping pipeline...")
    
    # Cleanup
    pipeline.set_state(Gst.State.NULL)


if __name__ == '__main__':
    main()
