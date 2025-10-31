use gstreamer::prelude::*;
use gstreamer_rtsp_server::prelude::*;
use std::env;
use std::path::Path;

fn setup_rtsp_server(pipeline_str: &str, port: &str, mount_point: &str) -> gstreamer_rtsp_server::RTSPServer {
    let server = gstreamer_rtsp_server::RTSPServer::new();
    server.set_address("0.0.0.0");
    server.set_service(port);
    
    let factory = gstreamer_rtsp_server::RTSPMediaFactory::new();
    factory.set_launch(pipeline_str);
    factory.set_shared(true);
    
    // Debug signals
    factory.connect_media_constructed(|_, media| {
        println!("DEBUG: Media constructed");
        
        media.connect_new_stream(|_, stream| {
            println!("DEBUG: New stream created: {:?}", stream);
        });
        
        media.connect_prepared(|_| {
            println!("DEBUG: Media prepared");
        });
    });
    
    server.connect_client_connected(|_, client| {
        println!("DEBUG: Client connected: {:?}", client);
    });
    
    let mounts = server.mount_points().unwrap();
    mounts.add_factory(mount_point, factory);
    
    println!("DEBUG: RTSP server configured for 0.0.0.0:{}", port);
    println!("DEBUG: Mount point: {}", mount_point);
    
    server
}

fn main() {
    // Initialize GStreamer
    gstreamer::init().expect("Failed to initialize GStreamer");

    // Input device can be passed via env GST_DEVICE or RTSP_URL
    let device = env::var("RTSP_URL")
        .or_else(|_| env::var("GST_DEVICE"))
        .unwrap_or_else(|_| "test".to_string());

    // Output dimensions for scaling (optional)
    let output_width = env::var("OUTPUT_WIDTH").unwrap_or_else(|_| "1920".to_string());
    let output_height = env::var("OUTPUT_HEIGHT").unwrap_or_else(|_| "1080".to_string());
    
    // RTSP output configuration
    let rtsp_output = env::var("RTSP_OUTPUT").is_ok();
    let rtsp_output_port = env::var("RTSP_OUTPUT_PORT").unwrap_or_else(|_| "8557".to_string());
    let show_display = env::var("SHOW_DISPLAY").unwrap_or_else(|_| "true".to_string()) == "true";

    // Build pipeline with scaling
    // All pipelines use DeepStream's hardware-accelerated elements for GPU processing
    // Optimized: tee before encoding to avoid unnecessary decode/re-encode cycle
    
    // Determine output sink based on configuration
    let output_sink = if rtsp_output {
        // RTSP output with H.264 encoding
        "nvvideoconvert ! video/x-raw(memory:NVMM),format=I420 ! \
         nvv4l2h264enc bitrate=4000000 insert-sps-pps=true ! \
         h264parse ! rtph264pay name=pay0 pt=96".to_string()
    } else if show_display {
        // Local display only
        "nvvideoconvert ! ximagesink sync=false".to_string()
    } else {
        // No output (headless)
        "fakesink".to_string()
    };
    
    let pipeline_str = if device.starts_with("rtsp://") || device.starts_with("http://") {
        // Network stream (RTSP, HTTP) - scale and output
        format!(
            "nvurisrcbin uri={} ! \
             nvvideoconvert interpolation-method=5 ! \
             video/x-raw(memory:NVMM),width={},height={} ! \
             {}",
            device, output_width, output_height, output_sink
        )
    } else if device.ends_with(".mp4") || device.ends_with(".avi") || device.ends_with(".mkv") {
        // Video file with hardware decoding and scaling
        format!(
            "nvurisrcbin uri=file://{} ! \
             nvvideoconvert interpolation-method=5 ! \
             video/x-raw(memory:NVMM),width={},height={} ! \
             {}",
            device, output_width, output_height, output_sink
        )
    } else if Path::new(&device).exists() && device.starts_with("/dev/video") {
        // Local camera device with hardware processing and scaling
        format!(
            "v4l2src device={} ! \
             nvvideoconvert interpolation-method=5 ! \
             video/x-raw(memory:NVMM),width={},height={} ! \
             {}",
            device, output_width, output_height, output_sink
        )
    } else {
        // Fallback to test pattern with hardware processing and scaling
        println!("Using test video source (no camera/stream specified)");
        let test_pattern = "0"; // SMPTE color bars
        format!(
            "videotestsrc pattern={} ! video/x-raw,width={},height={} ! \
             nvvideoconvert interpolation-method=5 ! video/x-raw(memory:NVMM) ! \
             {}",
            test_pattern, output_width, output_height, output_sink
        )
    };

    println!("DeepStream GPU-Accelerated Scaling Pipeline");
    println!("  Input: {}", device);
    println!("  Output dimensions: {}x{}", output_width, output_height);
    println!("  Display: {}", if show_display { "enabled" } else { "disabled" });
    if rtsp_output {
        println!("  RTSP Stream: rtsp://localhost:{}/ds-scale", rtsp_output_port);
    }
    println!("  Pipeline: {}", pipeline_str);
    println!();
    println!("Note: Video will be STRETCHED to fit {}x{} exactly", output_width, output_height);
    println!("      To maintain aspect ratio, use matching dimensions");
    
    // Handle RTSP server if RTSP output is enabled
    if rtsp_output {
        println!("      RTSP stream available at rtsp://localhost:{}/ds-scale", rtsp_output_port);
        println!("      View with: ffplay rtsp://localhost:{}/ds-scale", rtsp_output_port);
        println!();
        println!("Starting RTSP server...");
        
        println!("DEBUG: Setting pipeline: {}", pipeline_str);
        
        // Create RTSP server
        let server = setup_rtsp_server(&pipeline_str, &rtsp_output_port, "/ds-scale");
        
        // Attach server to main context
        server.attach(None);
        
        println!("RTSP server started on port {}", rtsp_output_port);
        println!("Server bound to 0.0.0.0:{}", rtsp_output_port);
        println!("Waiting for RTSP clients to connect...");
        println!("Press Ctrl+C to stop the server");
        
        // Run main loop
        let main_loop = glib::MainLoop::new(None, false);
        main_loop.run();
        
        return;
    }
    
    // Non-RTSP mode: create and run pipeline directly
    let pipeline = gstreamer::parse_launch(&pipeline_str).expect("Failed to create pipeline");
    let pipeline = pipeline
        .downcast::<gstreamer::Pipeline>()
        .expect("Expected a gstreamer::Pipeline");

    let bus = pipeline
        .bus()
        .expect("Pipeline without bus. Shouldn't happen.");

    pipeline
        .set_state(gstreamer::State::Playing)
        .expect("Unable to set the pipeline to the `Playing` state");

    // Wait until error or EOS
    for msg in bus.iter_timed(gstreamer::ClockTime::NONE) {
        use gstreamer::MessageView;

        match msg.view() {
            MessageView::Eos(..) => {
                println!("End-Of-Stream reached.");
                break;
            }
            MessageView::Error(err) => {
                eprintln!(
                    "Error from {:?}: {} ({:?})",
                    err.src().map(|s| s.path_string()),
                    err.error(),
                    err.debug()
                );
                break;
            }
            _ => (),
        }
    }

    pipeline
        .set_state(gstreamer::State::Null)
        .expect("Unable to set the pipeline to the `Null` state");
}

