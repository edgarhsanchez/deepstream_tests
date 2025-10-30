#!/bin/bash

# Setup DeepStream-YOLO repository
# This script clones the DeepStream-YOLO repo and applies necessary patches

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEPSTREAM_YOLO_DIR="$SCRIPT_DIR/deepstream-yolo"

echo "=========================================="
echo "DeepStream-YOLO Setup"
echo "=========================================="
echo ""

# Check if directory already exists
if [ -d "$DEEPSTREAM_YOLO_DIR" ]; then
    echo "⚠️  deepstream-yolo directory already exists."
    echo ""
    read -p "Remove and re-clone? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing directory."
        exit 0
    fi
    echo "Removing existing directory..."
    rm -rf "$DEEPSTREAM_YOLO_DIR"
fi

echo "Cloning DeepStream-YOLO repository..."
git clone https://github.com/marcoslucianops/DeepStream-Yolo.git "$DEEPSTREAM_YOLO_DIR"

echo ""
echo "Applying Makefile patch for CUDA 12.8..."
cd "$DEEPSTREAM_YOLO_DIR"
patch -p1 < "$SCRIPT_DIR/deepstream-yolo-makefile.patch"

echo ""
echo "Compiling YOLO parser inside DeepStream container..."
cd "$SCRIPT_DIR"

# Check if Docker image exists
if ! docker image inspect nvcr.io/nvidia/deepstream:8.0-samples-multiarch &> /dev/null; then
    echo ""
    echo "⚠️  Warning: DeepStream Docker image not found locally."
    echo "   You may need to pull it first:"
    echo "   docker pull nvcr.io/nvidia/deepstream:8.0-samples-multiarch"
    exit 1
fi

# Compile inside the container where DeepStream headers are available
# Need to create symlinks for CUDA libraries first
docker run --rm --gpus all \
    -v "$DEEPSTREAM_YOLO_DIR":/workspace/deepstream-yolo \
    -w /workspace/deepstream-yolo/nvdsinfer_custom_impl_Yolo \
    nvcr.io/nvidia/deepstream:8.0-samples-multiarch \
    bash -c "ln -sf /usr/local/cuda-12.8/lib64/libcudart.so.12 /usr/local/cuda-12.8/lib64/libcudart.so && ln -sf /usr/local/cuda-12.8/lib64/libcublas.so.12 /usr/local/cuda-12.8/lib64/libcublas.so && ln -sf /usr/local/cuda-12.8/lib64/libcublasLt.so.12 /usr/local/cuda-12.8/lib64/libcublasLt.so && CUDA_VER=12.5 make -j\$(nproc)"

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ Setup Complete!"
    echo "=========================================="
    echo ""
    echo "DeepStream-YOLO has been:"
    echo "  ✓ Cloned to: $DEEPSTREAM_YOLO_DIR"
    echo "  ✓ Patched for CUDA 12.8 compatibility"
    echo "  ✓ Parser compiled: libnvdsinfer_custom_impl_Yolo.so"
    echo ""
    echo "Note: This directory is excluded from git (in .gitignore)"
else
    echo ""
    echo "❌ Compilation failed. Please check the error messages above."
    exit 1
fi
