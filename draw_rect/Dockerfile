# Dockerfile for draw_rect with zero-copy CUDA via NvBufSurface
# Based on NVIDIA DeepStream SDK 8.0

FROM deepstream-rust-builder:latest

# No additional dependencies needed - using ctypes to access NvBufSurface

WORKDIR /workdir

# Copy CUDA library and Python scripts
COPY libcuda_draw.so draw_rect_nvbuf.py draw_rect_processor.py draw_rect_server.py ./

# Set environment for DeepStream libraries
ENV LD_LIBRARY_PATH=/opt/nvidia/deepstream/deepstream/lib:${LD_LIBRARY_PATH}

# Disable Python output buffering for real-time logging
ENV PYTHONUNBUFFERED=1

# Default command
CMD ["python3", "-u", "draw_rect_nvbuf.py", "--help"]
