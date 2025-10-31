use gstreamer::prelude::*;
use gstreamer_rtsp_server::prelude::*;
use std::env;
use std::path::Path;
use std::fs;
use std::io::Write;

fn create_filtered_config(base_config: &str, target_class_id: i32) -> Result<String, std::io::Error> {
    // Read the base config
    let config_content = fs::read_to_string(base_config)?;
    
    // Create a temporary config with class filtering
    let temp_config_path = "/tmp/config_infer_filtered.txt";
    let mut new_config = String::new();
    
    // Copy everything except [class-attrs-all] section
    let mut in_class_attrs = false;
    for line in config_content.lines() {
        if line.trim().starts_with("[class-attrs-all]") {
            in_class_attrs = true;
            continue;
        } else if in_class_attrs && line.trim().starts_with("[") {
            in_class_attrs = false;
        }
        
        if !in_class_attrs {
            new_config.push_str(line);
            new_config.push('\n');
        }
    }
    
    // Add class-specific filtering: high threshold for non-target classes
    new_config.push_str(&format!("\n[class-attrs-{}]\n", target_class_id));
    new_config.push_str("pre-cluster-threshold=0.25\n");
    new_config.push_str("\n[class-attrs-all]\n");
    new_config.push_str("pre-cluster-threshold=1.0\n");  // Impossible threshold to hide other classes
    
    // Write to temp file
    let mut file = fs::File::create(temp_config_path)?;
    file.write_all(new_config.as_bytes())?;
    
    Ok(temp_config_path.to_string())
}

fn setup_rtsp_server(pipeline_str: &str, port: &str, mount_point: &str) -> gstreamer_rtsp_server::RTSPServer {
    use gstreamer_rtsp_server::prelude::*;
    
    let server = gstreamer_rtsp_server::RTSPServer::new();
    
    // Create a server socket for binding
    let address = format!("0.0.0.0:{}", port);
    server.set_address("0.0.0.0");
    server.set_service(port);
    
    // Create and configure the media factory
    let factory = gstreamer_rtsp_server::RTSPMediaFactory::new();
    
    println!("DEBUG: Setting pipeline: {}", pipeline_str);
    factory.set_launch(pipeline_str);
    factory.set_shared(true);
    
    // Connect to factory signals for debugging
    factory.connect_media_constructed(|_factory, media| {
        println!("DEBUG: Media constructed");
        media.connect_new_stream(|_media, stream| {
            println!("DEBUG: New stream created: {:?}", stream);
        });
        media.connect_prepared(|_media| {
            println!("DEBUG: Media prepared");
        });
    });
    
    // Get mount points and add the factory
    let mounts = server.mount_points().expect("Could not get mount points");
    mounts.add_factory(mount_point, factory);
    
    // Connect to server signals
    server.connect_client_connected(|_server, client| {
        println!("DEBUG: Client connected: {:?}", client);
    });
    
    println!("DEBUG: RTSP server configured for {}", address);
    println!("DEBUG: Mount point: {}", mount_point);
    
    server
}

fn main() {
    // Initialize GStreamer
    gstreamer::init().expect("Failed to initialize GStreamer");

    // Input device can be passed via env GST_DEVICE or RTSP_URL
    let device = env::var("GST_DEVICE")
        .or_else(|_| env::var("RTSP_URL"))
        .unwrap_or_else(|_| "test".to_string());
    
    // Object to detect (e.g., "person", "car", "dog", etc.)
    let target_object = env::var("DETECT_OBJECT").unwrap_or_else(|_| "person".to_string());
    
    // Find the class ID for the target object from labels.txt
    let labels_path = "/models/labels.txt";
    let target_class_id = if let Ok(contents) = fs::read_to_string(labels_path) {
        contents.lines()
            .enumerate()
            .find(|(_, line)| line.trim() == target_object)
            .map(|(idx, _)| idx as i32)
    } else {
        None
    };
    
    let filter_class_id = env::var("FILTER_CLASS_ID").ok()
        .and_then(|v| v.parse::<i32>().ok())
        .or(target_class_id);
    
    // Model configuration
    let model_engine = env::var("MODEL_ENGINE").unwrap_or_else(|_| "".to_string());
    let model_config = env::var("MODEL_CONFIG").unwrap_or_else(|_| "/opt/nvidia/deepstream/deepstream/samples/configs/deepstream-app/config_infer_primary.txt".to_string());
    
    // Create filtered config if class filtering is requested
    let final_config = if let Some(class_id) = filter_class_id {
        println!("Target object '{}' (class ID: {})", target_object, class_id);
        println!("Class filtering: ENABLED - Only showing '{}' detections", target_object);
        
        match create_filtered_config(&model_config, class_id) {
            Ok(filtered_config) => {
                println!("✓ Created filtered config: {}", filtered_config);
                filtered_config
            }
            Err(e) => {
                eprintln!("Warning: Failed to create filtered config: {}. Using original config.", e);
                model_config.clone()
            }
        }
    } else {
        println!("Warning: Could not find '{}' in labels file", target_object);
        println!("Class filtering: DISABLED - Showing all detections");
        model_config.clone()
    };
    
    // Display options
    let show_display = env::var("SHOW_DISPLAY").unwrap_or_else(|_| "true".to_string()) == "true";
    
    // RTSP output options
    let rtsp_output = env::var("RTSP_OUTPUT").ok();
    let rtsp_port = env::var("RTSP_OUTPUT_PORT").unwrap_or_else(|_| "8555".to_string());
    
    // Output dimensions (optional)
    let output_width = env::var("OUTPUT_WIDTH").unwrap_or_else(|_| "1920".to_string());
    let output_height = env::var("OUTPUT_HEIGHT").unwrap_or_else(|_| "1080".to_string());

    println!("DeepStream Object Detection Pipeline");
    println!("  Input: {}", device);
    println!("  Target Object: {}", target_object);
    println!("  Model Engine: {}", model_engine);
    println!("  Model Config: {}", final_config);
    println!("  Display: {}", if show_display { "enabled" } else { "disabled" });
    if rtsp_output.is_some() {
        println!("  RTSP Stream: rtsp://localhost:{}/ds-detect", rtsp_port);
    }

    // Build output sink based on configuration
    // IMPORTANT: nvdsosd outputs video/x-raw(memory:NVMM) - keep it in GPU memory!
    let output_sink = if rtsp_output.is_some() {
        // RTSP output - encode to H.264 and pay for RTP
        // The RTSP server will handle the streaming
        let rtsp_sink = "nvvideoconvert ! video/x-raw(memory:NVMM),format=I420 ! \
                         nvv4l2h264enc bitrate=4000000 insert-sps-pps=true ! \
                         h264parse ! rtph264pay name=pay0 pt=96".to_string();
        
        if show_display {
            // Use tee to split for both RTSP and display
            format!(
                "nvvideoconvert ! video/x-raw(memory:NVMM),format=I420 ! tee name=t \
                 t. ! queue ! nvv4l2h264enc bitrate=4000000 insert-sps-pps=true ! h264parse ! rtph264pay name=pay0 pt=96 \
                 t. ! queue ! nvvideoconvert ! ximagesink sync=false"
            )
        } else {
            rtsp_sink
        }
    } else if show_display {
        // Display only - convert from GPU to CPU for X11
        "nvvideoconvert ! ximagesink sync=false".to_string()
    } else {
        "fakesink sync=false".to_string()
    };

    // Build the DeepStream pipeline with nvinfer for object detection
    // Pipeline stays in GPU memory (NVMM) throughout: nvstreammux → nvinfer → nvdsosd
    let source_pipeline = if device.starts_with("rtsp://") || device.starts_with("http://") {
        // Network stream with object detection
        format!(
            "nvurisrcbin uri={} ! \
             nvvideoconvert interpolation-method=5 ! \
             m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
             nvinfer config-file-path={} ! \
             nvdsosd",
            device, output_width, output_height, final_config
        )
    } else if device.ends_with(".mp4") || device.ends_with(".avi") || device.ends_with(".mkv") {
        // Video file with object detection
        format!(
            "nvurisrcbin uri=file://{} ! \
             nvvideoconvert interpolation-method=5 ! \
             m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
             nvinfer config-file-path={} ! \
             nvdsosd",
            device, output_width, output_height, final_config
        )
    } else if Path::new(&device).exists() && device.starts_with("/dev/video") {
        // Local camera with object detection
        format!(
            "v4l2src device={} ! \
             nvvideoconvert interpolation-method=5 ! \
             m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
             nvinfer config-file-path={} ! \
             nvdsosd",
            device, output_width, output_height, final_config
        )
    } else {
        // Default to test pattern
        format!(
            "videotestsrc ! \
             nvvideoconvert interpolation-method=5 ! \
             m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
             nvinfer config-file-path={} ! \
             nvdsosd",
            output_width, output_height, final_config
        )
    };
    
    let pipeline_str = format!("{} ! {}", source_pipeline, output_sink);

    println!("  Pipeline: {}", pipeline_str);
    println!("  Output: {}", output_sink);
    println!("\nNote: This uses DeepStream's nvinfer element for GPU-accelerated inference");
    println!("      nvdsosd draws bounding boxes and labels on detected objects");
    println!("      You can customize the model by setting MODEL_CONFIG environment variable");
    
    // Handle RTSP server if RTSP output is enabled
    if rtsp_output.is_some() {
        println!("      RTSP stream available at rtsp://localhost:{}/ds-detect", rtsp_port);
        println!("      View with: ffplay rtsp://localhost:{}/ds-detect", rtsp_port);
        println!("\nStarting RTSP server...");
        
        // Create RTSP server with the detection pipeline
        // Note: Do NOT wrap in ( ) for RTSP server - it expects a raw pipeline string
        let server = setup_rtsp_server(&pipeline_str, &rtsp_port, "/ds-detect");
        
        // Attach the server to the default main context
        // This actually starts the server listening on the port  
        let _server_id = server.attach(None);
        
        println!("RTSP server started on port {}", rtsp_port);
        println!("Server bound to 0.0.0.0:{}", rtsp_port);
        println!("Waiting for RTSP clients to connect...");
        println!("Press Ctrl+C to stop the server");
        
        // Create a main loop to keep the server running
        let main_loop = glib::MainLoop::new(None, false);
        main_loop.run();
        
        return; // Exit here - RTSP server handles everything
    }

    // Parse and create the pipeline (only if not using RTSP server)
    let pipeline = gstreamer::parse_launch(&pipeline_str)
        .expect("Failed to create pipeline");

    // Get the pipeline bus for messages
    let bus = pipeline
        .bus()
        .expect("Pipeline should have a bus");

    // Start playing
    pipeline
        .set_state(gstreamer::State::Playing)
        .expect("Unable to set the pipeline to the Playing state");

    // Wait for error or EOS
    for msg in bus.iter_timed(gstreamer::ClockTime::NONE) {
        use gstreamer::MessageView;

        match msg.view() {
            MessageView::Eos(..) => {
                println!("End of stream");
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
            MessageView::StateChanged(state_changed) => {
                if state_changed
                    .src()
                    .map(|s| s == &pipeline)
                    .unwrap_or(false)
                {
                    println!(
                        "Pipeline state changed from {:?} to {:?}",
                        state_changed.old(),
                        state_changed.current()
                    );
                }
            }
            _ => (),
        }
    }

    // Cleanup
    pipeline
        .set_state(gstreamer::State::Null)
        .expect("Unable to set the pipeline to the Null state");
}
