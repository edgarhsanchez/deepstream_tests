#!/bin/bash

# Build script for draw_rect Docker image

cd "$(dirname "$0")/draw_rect"

echo "Building draw_rect Docker image..."
docker build -t draw_rect:latest .

if [ $? -eq 0 ]; then
    echo "✓ Image built successfully: draw_rect:latest"
else
    echo "✗ Failed to build image"
    exit 1
fi
