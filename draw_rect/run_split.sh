#!/bin/bash
# Launcher script for the split-architecture CUDA rectangle drawing system
# Runs both the processor and RTSP server in Docker containers

set -e

# Configuration
INPUT_RTSP="${INPUT_RTSP:-rtsp://172.20.96.1:8554/live}"
PROCESSOR_PORT="${PROCESSOR_PORT:-8555}"
SERVER_PORT="${SERVER_PORT:-8556}"
WIDTH="${WIDTH:-960}"
HEIGHT="${HEIGHT:-540}"

echo "========================================="
echo "CUDA Rectangle Drawing System (Split Architecture)"
echo "========================================="
echo "Source RTSP:     $INPUT_RTSP (port 8554)"
echo "Processor RTSP:  rtsp://localhost:$PROCESSOR_PORT/processed"
echo "Final Output:    rtsp://localhost:$SERVER_PORT/live"
echo "Resolution:      ${WIDTH}x${HEIGHT}"
echo "========================================="
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "🛑 Stopping containers..."
    docker stop draw_rect_processor 2>/dev/null || true
    docker stop draw_rect_server 2>/dev/null || true
    echo "✓ Cleanup complete"
}

trap cleanup EXIT INT TERM

# Build the Docker image
echo "🔨 Building Docker image..."
docker build -t draw_rect:latest $(dirname $0)
echo "✓ Docker image built"
echo ""

# Start the processor (App 1)
echo "🚀 Starting processor (draws rectangles with CUDA)..."
docker run --rm -d \
    --name draw_rect_processor \
    --gpus all \
    --network host \
    --ipc=host \
    draw_rect:latest \
    python3 -u /workdir/draw_rect_processor.py \
        --input "$INPUT_RTSP" \
        --port "$PROCESSOR_PORT" \
        --width "$WIDTH" \
        --height "$HEIGHT"

echo "✓ Processor started (container: draw_rect_processor)"
echo "  Serving on rtsp://localhost:$PROCESSOR_PORT/processed"
echo "⏳ Waiting for processor to initialize (5 seconds)..."
sleep 5
echo ""

# Start the RTSP server (App 2)
echo "🚀 Starting re-streaming server..."
docker run --rm -d \
    --name draw_rect_server \
    --network host \
    --ipc=host \
    draw_rect:latest \
    python3 -u /workdir/draw_rect_server.py \
        --input "rtsp://localhost:$PROCESSOR_PORT/processed" \
        --port "$SERVER_PORT"

echo "✓ RTSP server started (container: draw_rect_server)"
echo "  Serving on rtsp://localhost:$SERVER_PORT/live"
echo ""

# Show status
echo "========================================="
echo "✅ System is running!"
echo "========================================="
echo ""
echo "📺 View the stream:"
echo "   ffplay rtsp://localhost:$SERVER_PORT/live"
echo "   vlc rtsp://localhost:$SERVER_PORT/live"
echo ""
echo "🔍 Check ports:"
echo "   Port 8554: Source RTSP (input)"
echo "   Port $PROCESSOR_PORT: Processor RTSP (with CUDA rectangles)"
echo "   Port $SERVER_PORT: Final RTSP (output)"
echo ""
echo "📊 View logs:"
echo "   docker logs -f draw_rect_processor"
echo "   docker logs -f draw_rect_server"
echo ""
echo "Press Ctrl+C to stop both containers"
echo ""

# Follow logs from both containers
docker logs -f draw_rect_processor 2>&1 &
PID1=$!
docker logs -f draw_rect_server 2>&1 &
PID2=$!

# Wait for user interrupt
wait $PID1 $PID2
