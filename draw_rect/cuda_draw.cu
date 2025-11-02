/*
 * CUDA kernel for drawing rectangle outlines on NV12 frames
 * Operates directly on the Y (luma) plane
 */

#include <cuda_runtime.h>
#include <stdio.h>

extern "C" {

/**
 * CUDA kernel to draw a THICK (5-pixel) rectangle outline on Y plane of NV12 frame
 * 
 * @param y_plane Pointer to the Y (luma) plane
 * @param width Frame width in pixels
 * @param height Frame height in pixels
 * @param stride Stride (pitch) of the Y plane in bytes
 * @param x Rectangle top-left X coordinate
 * @param y Rectangle top-left Y coordinate
 * @param w Rectangle width
 * @param h Rectangle height
 * @param color Y value (0-255, typically 255 for white, 0 for black)
 */
__global__ void draw_rectangle_kernel(
    unsigned char* y_plane,
    int width,
    int height,
    int stride,
    int x,
    int y,
    int w,
    int h,
    unsigned char color
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    // Calculate which edge this thread will draw
    // 0: top edge, 1: bottom edge, 2: left edge, 3: right edge
    int edge = blockIdx.y;
    
    const int thickness = 5;  // 5-pixel thick lines for maximum visibility
    
    if (edge == 0) {
        // Top edge: thick horizontal lines
        for (int t = 0; t < thickness; t++) {
            int draw_y = y + t;
            if (idx < w && x + idx < width && draw_y >= 0 && draw_y < height) {
                y_plane[draw_y * stride + x + idx] = color;
            }
        }
    }
    else if (edge == 1) {
        // Bottom edge: thick horizontal lines
        for (int t = 0; t < thickness; t++) {
            int draw_y = y + h - 1 - t;
            if (idx < w && x + idx < width && draw_y >= 0 && draw_y < height) {
                y_plane[draw_y * stride + x + idx] = color;
            }
        }
    }
    else if (edge == 2) {
        // Left edge: thick vertical lines
        for (int t = 0; t < thickness; t++) {
            int draw_x = x + t;
            if (idx < h && y + idx < height && draw_x >= 0 && draw_x < width) {
                y_plane[(y + idx) * stride + draw_x] = color;
            }
        }
    }
    else if (edge == 3) {
        // Right edge: thick vertical lines
        for (int t = 0; t < thickness; t++) {
            int draw_x = x + w - 1 - t;
            if (idx < h && y + idx < height && draw_x >= 0 && draw_x < width) {
                y_plane[(y + idx) * stride + draw_x] = color;
            }
        }
    }
}

/**
 * Host function to launch the rectangle drawing kernel
 */
cudaError_t draw_rectangle(
    unsigned char* d_y_plane,
    int width,
    int height,
    int stride,
    int x,
    int y,
    int w,
    int h,
    unsigned char color,
    cudaStream_t stream
) {
    // Validate rectangle bounds
    if (x < 0 || y < 0 || w <= 0 || h <= 0) {
        return cudaErrorInvalidValue;
    }
    
    // Clamp rectangle to frame boundaries
    if (x >= width || y >= height) {
        return cudaSuccess; // Rectangle completely outside frame
    }
    
    // Use 256 threads per block
    int threads_per_block = 256;
    
    // Calculate blocks needed for the longest edge
    int max_edge_length = (w > h) ? w : h;
    int blocks_x = (max_edge_length + threads_per_block - 1) / threads_per_block;
    
    // 4 edges to draw
    dim3 grid(blocks_x, 4);
    dim3 block(threads_per_block);
    
    // Launch kernel
    if (stream) {
        draw_rectangle_kernel<<<grid, block, 0, stream>>>(
            d_y_plane, width, height, stride, x, y, w, h, color
        );
    } else {
        draw_rectangle_kernel<<<grid, block>>>(
            d_y_plane, width, height, stride, x, y, w, h, color
        );
    }
    
    return cudaGetLastError();
}

/**
 * Host function to draw multiple rectangles
 */
cudaError_t draw_rectangles(
    unsigned char* d_y_plane,
    int width,
    int height,
    int stride,
    int* rectangles,  // Array of [x, y, w, h] for each rectangle
    int num_rects,
    unsigned char color,
    cudaStream_t stream
) {
    for (int i = 0; i < num_rects; i++) {
        int x = rectangles[i * 4 + 0];
        int y = rectangles[i * 4 + 1];
        int w = rectangles[i * 4 + 2];
        int h = rectangles[i * 4 + 3];
        
        cudaError_t err = draw_rectangle(
            d_y_plane, width, height, stride, x, y, w, h, color, stream
        );
        
        if (err != cudaSuccess) {
            return err;
        }
    }
    
    return cudaSuccess;
}

/**
 * Host function to draw rectangles on host (CPU) memory
 * Handles the host-to-device-to-host transfers
 */
cudaError_t draw_rectangles_host(
    unsigned char* h_y_plane,
    int width,
    int height,
    int stride,
    int* rectangles,
    int num_rects,
    unsigned char color
) {
    // Allocate device memory
    unsigned char* d_y_plane;
    size_t size = stride * height;
    cudaError_t err;
    
    err = cudaMalloc(&d_y_plane, size);
    if (err != cudaSuccess) return err;
    
    // Copy host to device
    err = cudaMemcpy(d_y_plane, h_y_plane, size, cudaMemcpyHostToDevice);
    if (err != cudaSuccess) {
        cudaFree(d_y_plane);
        return err;
    }
    
    // Draw rectangles
    err = draw_rectangles(d_y_plane, width, height, stride, rectangles, num_rects, color, NULL);
    if (err != cudaSuccess) {
        cudaFree(d_y_plane);
        return err;
    }
    
    // Synchronize before copying back
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) {
        cudaFree(d_y_plane);
        return err;
    }
    
    // Copy device to host
    err = cudaMemcpy(h_y_plane, d_y_plane, size, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) {
        cudaFree(d_y_plane);
        return err;
    }
    
    // Free device memory
    cudaFree(d_y_plane);
    
    return cudaSuccess;
}

} // extern "C"
