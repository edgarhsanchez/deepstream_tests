#!/usr/bin/env bash
set -euo pipefail

# build.sh - build a DeepStream-based Docker image for compiling Rust apps
# Base image: nvcr.io/nvidia/deepstream:8.0-triton-multiarch

SCRIPT_NAME=$(basename "$0")
DEFAULT_TAG="deepstream-rust-builder:latest"
DOCKERFILE_PRINT=false
NO_CACHE=false
TAG="$DEFAULT_TAG"
PROJECT_PATH=""
RUN_AFTER_BUILD=false
ENABLE_X11=false
DISPLAY_VAR=""
XAUTH_PATH=""
DEVICE_ARGS=()

resolve_abs() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$1"
  else
    readlink -f "$1"
  fi
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Options:
  -t, --tag TAG          Set the resulting image tag (default: $DEFAULT_TAG)
  --no-cache             Build the image without using cache
  --print-dockerfile     Print the Dockerfile that will be used and exit
  -p, --project PATH     Path to the Rust project to build inside the container
  --run                  After building the project, execute the produced binary
  --x11                  Enable X11 forwarding (mount /tmp/.X11-unix and set DISPLAY)
  --display DISPLAY      Set DISPLAY for the container (default: uses host $DISPLAY)
  --xauth PATH           Path to an Xauthority file to forward into the container
  --device /dev/...      Add a device to the container (can be passed multiple times)
  -h, --help             Show this help message and exit

Examples:
  # Build the image with default tag
  $SCRIPT_NAME

  # Build the image with a custom tag and no cache
  $SCRIPT_NAME --tag my-deepstream-builder:1.0 --no-cache

  # Print the Dockerfile only
  $SCRIPT_NAME --print-dockerfile

Build and run a Rust project (example):
  # Build the image and build the project in ./scale
  $SCRIPT_NAME --project scale

  # Build the image, build the project and run the binary with X11 and camera
  $SCRIPT_NAME --project scale --run --x11 --device /dev/video0

Notes:
  - This script does not push the image to a registry.
  - You need access to NVIDIA Container Registry for the base image.
EOF
}

print_dockerfile() {
  cat <<'DOCKER'
FROM nvcr.io/nvidia/deepstream:8.0-triton-multiarch

# Install common build dependencies for Rust and development
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    pkg-config \
    libssl-dev \
    cmake \
    git \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-rtsp \
    gstreamer1.0-x \
    gstreamer1.0-tools \
    libflac12 \
    libdvdnav4 \
    libdvdread8 \
    libdca0 \
    libmpg123-0 \
    libmp3lame0 \
    libvpx9 \
  && rm -rf /var/lib/apt/lists/*

# Install rustup and a recent Rust toolchain
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path && \
    rustup default stable

# Ensure non-root user for builds (optional)
ARG BUILD_USER=builder
ARG BUILD_UID=1000
ARG BUILD_GID=1000
RUN groupadd -g ${BUILD_GID} ${BUILD_USER} || true && \
    useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash ${BUILD_USER} || true

# Ensure the default user remains root to avoid runtime missing-passwd issues
USER root

WORKDIR /workdir

# No ENTRYPOINT to avoid nested bash invocation issues; callers should set entrypoint when running
DOCKER
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag)
      TAG="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE=true
      shift
      ;;
    --print-dockerfile)
      DOCKERFILE_PRINT=true
      shift
      ;;
    -p|--project)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --x11)
      ENABLE_X11=true
      shift
      ;;
    --display)
      DISPLAY_VAR="$2"
      shift 2
      ;;
    --xauth)
      XAUTH_PATH="$2"
      shift 2
      ;;
    --device)
      DEVICE_ARGS+=("--device" "$2")
      shift 2
      ;;
    --run)
      RUN_AFTER_BUILD=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [ "$DOCKERFILE_PRINT" = true ]; then
  print_dockerfile
  exit 0
fi

# Write Dockerfile to a temporary file
TMPDIR=$(mktemp -d)
DOCKERFILE_PATH="$TMPDIR/Dockerfile"
print_dockerfile > "$DOCKERFILE_PATH"

BUILD_ARGS=()
if [ "$NO_CACHE" = true ]; then
  BUILD_ARGS+=(--no-cache)
fi

# Build
echo "Building Docker image tag='$TAG' from base nvcr.io/nvidia/deepstream:8.0-triton-multiarch"

docker build "${BUILD_ARGS[@]}" -t "$TAG" -f "$DOCKERFILE_PATH" "$TMPDIR"

# Clean up
rm -rf "$TMPDIR"

echo "Build complete: $TAG"

if [ -n "$PROJECT_PATH" ]; then
  if [ ! -d "$PROJECT_PATH" ] && [ ! -f "$PROJECT_PATH/Cargo.toml" ]; then
    echo "Project path '$PROJECT_PATH' does not exist or is not a Rust project." >&2
    exit 3
  fi

  PROJECT_ABS=$(resolve_abs "$PROJECT_PATH")
  echo "Running project build inside container for: $PROJECT_ABS"

  # Build runtime args
  RUNTIME_ARGS=()
  if [ "$ENABLE_X11" = true ]; then
    if [ -z "$DISPLAY_VAR" ]; then
      DISPLAY_VAR="${DISPLAY:-:0}"
    fi
    RUNTIME_ARGS+=( -e DISPLAY="$DISPLAY_VAR" -v /tmp/.X11-unix:/tmp/.X11-unix --ipc=host --network=host )
    
    # Add GPU/DRI device access for hardware acceleration
    if [ -d /dev/dri ]; then
      RUNTIME_ARGS+=( --device /dev/dri:/dev/dri )
    fi
    
    # Add video group access for GPU rendering
    VIDEO_GID=$(getent group video | cut -d: -f3 || echo "44")
    RENDER_GID=$(getent group render | cut -d: -f3 || echo "109")
    RUNTIME_ARGS+=( --group-add "$VIDEO_GID" --group-add "$RENDER_GID" )
    
    # Add MESA/OpenGL environment variables for software rendering fallback
    RUNTIME_ARGS+=( -e LIBGL_ALWAYS_SOFTWARE=1 )
    RUNTIME_ARGS+=( -e MESA_GL_VERSION_OVERRIDE=3.3 )
    RUNTIME_ARGS+=( -e GALLIUM_DRIVER=llvmpipe )
    
    if [ -n "$XAUTH_PATH" ]; then
      RUNTIME_ARGS+=( -v "$XAUTH_PATH":/tmp/.Xauthority -e XAUTHORITY=/tmp/.Xauthority )
    fi
  fi
  if [ ${#DEVICE_ARGS[@]} -gt 0 ]; then
    RUNTIME_ARGS+=( "${DEVICE_ARGS[@]}" )
  fi

  # Validate provided device paths exist on the host before running docker
  if [ ${#DEVICE_ARGS[@]} -gt 0 ]; then
    for ((i=0; i<${#DEVICE_ARGS[@]}; i+=2)); do
      devpath="${DEVICE_ARGS[i+1]}"
      if [ ! -e "$devpath" ]; then
        echo "Error: device '$devpath' not found on host. Check /dev and pass a valid device with --device." >&2
        echo "Example: ls -l /dev | grep video" >&2
        exit 127
      fi
    done
  fi

  docker run --rm -it \
    --entrypoint /bin/bash \
    --gpus all \
    "${RUNTIME_ARGS[@]}" \
    -v "$PROJECT_ABS":/workdir \
    -w /workdir \
    "$TAG" -lc \
      "source /usr/local/cargo/env || true; cargo build --release"

  if [ "$RUN_AFTER_BUILD" = true ]; then
    PKG_NAME=""
    if [ -f "$PROJECT_ABS/Cargo.toml" ]; then
      PKG_NAME=$(sed -n '/^\[package\]/,/^\[/{/^[[:space:]]*name[[:space:]]*=/p}' "$PROJECT_ABS/Cargo.toml" | head -n1 | sed -E 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/' | tr -d '\r' || true)
    fi

    BIN_PATH="$PROJECT_ABS/target/release"
    if [ -n "$PKG_NAME" ] && [ -x "$BIN_PATH/$PKG_NAME" ]; then
      EXEC_PATH="/workdir/target/release/$PKG_NAME"
    else
      FIRST_BIN=$(docker run --rm -v "$PROJECT_ABS":/workdir -w /workdir "$TAG" bash -lc "ls -1 target/release 2>/dev/null || true" | grep -v '\.\(d\|rlib\)$' | head -n1 || true)
      if [ -n "$FIRST_BIN" ]; then
        EXEC_PATH="/workdir/target/release/$FIRST_BIN"
      else
        echo "Could not find built binary in target/release to execute." >&2
        exit 4
      fi
    fi

    echo "Executing built binary: $EXEC_PATH"
    
    # Pass through environment variables if set
    GST_ARGS=()
    if [ -n "${GST_DEVICE:-}" ]; then
      GST_ARGS+=( -e "GST_DEVICE=$GST_DEVICE" )
    fi
    if [ -n "${OUTPUT_WIDTH:-}" ]; then
      GST_ARGS+=( -e "OUTPUT_WIDTH=$OUTPUT_WIDTH" )
    fi
    if [ -n "${OUTPUT_HEIGHT:-}" ]; then
      GST_ARGS+=( -e "OUTPUT_HEIGHT=$OUTPUT_HEIGHT" )
    fi
    if [ -n "${RTSP_PORT:-}" ]; then
      GST_ARGS+=( -e "RTSP_PORT=$RTSP_PORT" )
    fi
    if [ -n "${RTSP_PATH:-}" ]; then
      GST_ARGS+=( -e "RTSP_PATH=$RTSP_PATH" )
    fi
    if [ -n "${DETECT_OBJECT:-}" ]; then
      GST_ARGS+=( -e "DETECT_OBJECT=$DETECT_OBJECT" )
    fi
    if [ -n "${MODEL_CONFIG:-}" ]; then
      GST_ARGS+=( -e "MODEL_CONFIG=$MODEL_CONFIG" )
    fi
    if [ -n "${MODEL_ENGINE:-}" ]; then
      GST_ARGS+=( -e "MODEL_ENGINE=$MODEL_ENGINE" )
    fi
    if [ -n "${SHOW_DISPLAY:-}" ]; then
      GST_ARGS+=( -e "SHOW_DISPLAY=$SHOW_DISPLAY" )
    fi
    
    # Get absolute path to models directory (sibling to project directory)
    MODELS_DIR="$(dirname "$PROJECT_ABS")/models"
    if [ -d "$MODELS_DIR" ]; then
      MODELS_VOLUME="-v $MODELS_DIR:/models"
    else
      MODELS_VOLUME=""
    fi
    
    # Get absolute path to deepstream-yolo directory (sibling to project directory)
    DEEPSTREAM_YOLO_DIR="$(dirname "$PROJECT_ABS")/deepstream-yolo"
    if [ -d "$DEEPSTREAM_YOLO_DIR" ]; then
      DEEPSTREAM_YOLO_VOLUME="-v $DEEPSTREAM_YOLO_DIR:/workspace/deepstream-yolo"
    else
      DEEPSTREAM_YOLO_VOLUME=""
    fi
    
    docker run --rm -it \
      --entrypoint /bin/bash \
      --gpus all \
      "${RUNTIME_ARGS[@]}" \
      "${GST_ARGS[@]}" \
      -e MODEL_CONFIG \
      -e MODEL_ENGINE \
      -e DETECT_OBJECT \
      -e RTSP_URL \
      -e GST_DEVICE \
      -e SHOW_DISPLAY \
      -e OUTPUT_WIDTH \
      -e OUTPUT_HEIGHT \
      -v "$PROJECT_ABS":/workdir \
      $MODELS_VOLUME \
      $DEEPSTREAM_YOLO_VOLUME \
      -w /workdir \
      "$TAG" -lc "$EXEC_PATH"
  fi
fi
