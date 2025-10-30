use gstreamer::prelude::*;
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
    
    // Output dimensions (optional)
    let output_width = env::var("OUTPUT_WIDTH").unwrap_or_else(|_| "1920".to_string());
    let output_height = env::var("OUTPUT_HEIGHT").unwrap_or_else(|_| "1080".to_string());

    println!("DeepStream Object Detection Pipeline");
    println!("  Input: {}", device);
    println!("  Target Object: {}", target_object);
    println!("  Model Engine: {}", model_engine);
    println!("  Model Config: {}", final_config);
    println!("  Display: {}", if show_display { "enabled" } else { "disabled" });

    // Build the DeepStream pipeline with nvinfer for object detection
    let pipeline_str = if device.starts_with("rtsp://") || device.starts_with("http://") {
        // Network stream with object detection
        if show_display {
            format!(
                "nvurisrcbin uri={} ! \
                 nvvideoconvert interpolation-method=5 ! \
                 m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
                 nvinfer config-file-path={} ! \
                 nvvideoconvert ! \
                 nvdsosd ! \
                 nvvideoconvert ! \
                 ximagesink sync=false",
                device, output_width, output_height, final_config
            )
        } else {
            format!(
                "nvurisrcbin uri={} ! \
                 nvvideoconvert interpolation-method=5 ! \
                 m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
                 nvinfer config-file-path={} ! \
                 nvvideoconvert ! \
                 nvdsosd ! \
                 fakesink sync=false",
                device, output_width, output_height, final_config
            )
        }
    } else if device.ends_with(".mp4") || device.ends_with(".avi") || device.ends_with(".mkv") {
        // Video file with object detection
        if show_display {
            format!(
                "nvurisrcbin uri=file://{} ! \
                 nvvideoconvert interpolation-method=5 ! \
                 m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
                 nvinfer config-file-path={} ! \
                 nvvideoconvert ! \
                 nvdsosd ! \
                 nvvideoconvert ! \
                 ximagesink sync=false",
                device, output_width, output_height, final_config
            )
        } else {
            format!(
                "nvurisrcbin uri=file://{} ! \
                 nvvideoconvert interpolation-method=5 ! \
                 m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
                 nvinfer config-file-path={} ! \
                 nvvideoconvert ! \
                 nvdsosd ! \
                 fakesink sync=false",
                device, output_width, output_height, final_config
            )
        }
    } else if Path::new(&device).exists() && device.starts_with("/dev/video") {
        // Local camera with object detection
        if show_display {
            format!(
                "v4l2src device={} ! \
                 nvvideoconvert interpolation-method=5 ! \
                 m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
                 nvinfer config-file-path={} ! \
                 nvvideoconvert ! \
                 nvdsosd ! \
                 nvvideoconvert ! \
                 ximagesink sync=false",
                device, output_width, output_height, final_config
            )
        } else {
            format!(
                "v4l2src device={} ! \
                 nvvideoconvert interpolation-method=5 ! \
                 m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
                 nvinfer config-file-path={} ! \
                 nvvideoconvert ! \
                 nvdsosd ! \
                 fakesink sync=false",
                device, output_width, output_height, final_config
            )
        }
    } else {
        // Default to test pattern
        if show_display {
            format!(
                "videotestsrc ! \
                 nvvideoconvert interpolation-method=5 ! \
                 m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
                 nvinfer config-file-path={} ! \
                 nvvideoconvert ! \
                 nvdsosd ! \
                 nvvideoconvert ! \
                 ximagesink sync=false",
                output_width, output_height, final_config
            )
        } else {
            format!(
                "videotestsrc ! \
                 nvvideoconvert interpolation-method=5 ! \
                 m.sink_0 nvstreammux name=m width={} height={} batch-size=1 ! \
                 nvinfer config-file-path={} ! \
                 nvdsosd ! \
                 fakesink",
                output_width, output_height, final_config
            )
        }
    };

    println!("  Pipeline: {}", pipeline_str);
    println!("\nNote: This uses DeepStream's nvinfer element for GPU-accelerated inference");
    println!("      nvdsosd draws bounding boxes and labels on detected objects");
    println!("      You can customize the model by setting MODEL_CONFIG environment variable");

    // Parse and create the pipeline
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
