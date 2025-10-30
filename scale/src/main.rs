use gstreamer::prelude::*;
use std::env;
use std::path::Path;

fn main() {
    // Initialize GStreamer
    gstreamer::init().expect("Failed to initialize GStreamer");

    // Input device can be passed via env GST_DEVICE
    // Supports: /dev/videoN for Linux, RTSP URLs, or file paths
    let device = env::var("GST_DEVICE").unwrap_or_else(|_| "test".to_string());

    // Output dimensions for scaling (optional)
    let output_width = env::var("OUTPUT_WIDTH").unwrap_or_else(|_| "1920".to_string());
    let output_height = env::var("OUTPUT_HEIGHT").unwrap_or_else(|_| "1080".to_string());
    
    // UDP/RTP output port (optional)
    let rtsp_port = env::var("RTSP_PORT").unwrap_or_else(|_| "5000".to_string());

    // Build pipeline with scaling and RTP/UDP output
    // All pipelines use DeepStream's hardware-accelerated elements for GPU processing
    // Using multicast udpsink for network-accessible streaming
    let pipeline_str = if device.starts_with("rtsp://") || device.starts_with("http://") {
        // Network stream (RTSP, HTTP) - scale video and output via RTP/UDP multicast
        // Note: nvvideoconvert doesn't maintain aspect ratio, so we just scale to exact dimensions
        // The video will be stretched/squished to fit the target resolution
        // Using interpolation-method=5 (Lanczos) for better quality scaling
        format!(
            "nvurisrcbin uri={} ! \
             nvvideoconvert interpolation-method=5 ! \
             capsfilter caps=\"video/x-raw(memory:NVMM),width={},height={},pixel-aspect-ratio=1/1\" ! \
             nvv4l2h264enc bitrate=4000000 insert-vui=true insert-aud=true ! \
             capsfilter caps=\"video/x-h264,stream-format=byte-stream,alignment=au\" ! \
             h264parse config-interval=-1 ! \
             tee name=t \
             t. ! queue ! rtph264pay name=pay0 pt=96 config-interval=1 ! \
             udpsink host=224.1.1.1 port={} auto-multicast=true sync=false \
             t. ! queue ! h264parse ! nvv4l2decoder ! nvvideoconvert interpolation-method=5 ! ximagesink sync=false",
            device, output_width, output_height, rtsp_port
        )
    } else if device.ends_with(".mp4") || device.ends_with(".avi") || device.ends_with(".mkv") {
        // Video file with hardware decoding and scaling
        format!(
            "nvurisrcbin uri=file://{} ! \
             nvvideoconvert interpolation-method=5 ! capsfilter caps=\"video/x-raw(memory:NVMM),width={},height={}\" ! \
             nvv4l2h264enc bitrate=4000000 insert-vui=true insert-aud=true ! \
             h264parse config-interval=-1 ! \
             tee name=t \
             t. ! queue ! rtph264pay name=pay0 pt=96 config-interval=1 ! \
             udpsink host=224.1.1.1 port={} auto-multicast=true sync=false \
             t. ! queue ! h264parse ! nvv4l2decoder ! nvvideoconvert interpolation-method=5 ! ximagesink sync=false",
            device, output_width, output_height, rtsp_port
        )
    } else if Path::new(&device).exists() && device.starts_with("/dev/video") {
        // Local camera device with hardware processing and scaling
        format!(
            "v4l2src device={} ! nvvideoconvert interpolation-method=5 ! capsfilter caps=\"video/x-raw(memory:NVMM),width={},height={}\" ! \
             nvv4l2h264enc bitrate=4000000 insert-vui=true insert-aud=true ! \
             h264parse config-interval=-1 ! \
             tee name=t \
             t. ! queue ! rtph264pay name=pay0 pt=96 config-interval=1 ! \
             udpsink host=224.1.1.1 port={} auto-multicast=true sync=false \
             t. ! queue ! h264parse ! nvv4l2decoder ! nvvideoconvert interpolation-method=5 ! ximagesink sync=false",
            device, output_width, output_height, rtsp_port
        )
    } else {
        // Fallback to test pattern with hardware processing and scaling
        println!("Using test video source (no camera/stream specified)");
        let test_pattern = "0"; // SMPTE color bars
        format!(
            "videotestsrc pattern={} ! nvvideoconvert interpolation-method=5 ! capsfilter caps=\"video/x-raw(memory:NVMM),width={},height={}\" ! \
             nvv4l2h264enc bitrate=4000000 insert-vui=true insert-aud=true ! \
             h264parse config-interval=-1 ! \
             tee name=t \
             t. ! queue ! rtph264pay name=pay0 pt=96 config-interval=1 ! \
             udpsink host=224.1.1.1 port={} auto-multicast=true sync=false \
             t. ! queue ! h264parse ! nvv4l2decoder ! nvvideoconvert interpolation-method=5 ! ximagesink sync=false",
            test_pattern, output_width, output_height, rtsp_port
        )
    };

    println!("Starting GPU-accelerated scaling pipeline:");
    println!("  Input: {}", device);
    println!("  Output dimensions: {}x{}", output_width, output_height);
    println!("  NOTE: Video will be STRETCHED to fit {}x{} exactly", output_width, output_height);
    println!("        If source is square (1:1) and output is 4:3, video will appear distorted");
    println!("        To maintain aspect ratio, use matching dimensions (e.g., 640x640 for square source)");
    println!("  RTP/H264 multicast stream: udp://224.1.1.1:{}", rtsp_port);
    println!("  To view from VLC: Media -> Open Network Stream -> udp://@224.1.1.1:{}", rtsp_port);
    println!("  Pipeline: {}", pipeline_str);

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

