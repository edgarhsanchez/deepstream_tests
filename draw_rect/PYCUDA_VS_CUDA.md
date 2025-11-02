# CUDA in Python: PyCUDA vs C++/CUDA Comparison

## Overview

This project demonstrates two approaches to writing CUDA kernels for video processing:

1. **PyCUDA**: Write CUDA kernels in Python strings, compiled at runtime
2. **C++/CUDA**: Traditional approach with separate `.cu` files and compilation

## Comparison

| Feature | PyCUDA | C++/CUDA |
|---------|--------|----------|
| **Build Step** | ❌ None | ✅ Required (nvcc) |
| **Development Speed** | ⚡ Fast (edit & run) | 🐌 Slower (compile each time) |
| **Deployment** | ✅ Simple (just Python) | ⚠️ Need compiled .so file |
| **Debugging** | ⚠️ Runtime errors | ✅ Compile-time checking |
| **Performance** | ✅ Same (JIT compiled) | ✅ Same |
| **Code Location** | ✅ All in one file | ⚠️ Split across files |
| **Dependencies** | `pycuda` package | CUDA toolkit (nvcc) |
| **Learning Curve** | ✅ Python developers | ⚠️ C++/CUDA knowledge |

## When to Use Each

### Use PyCUDA When:
- ✅ Rapid prototyping and experimentation
- ✅ Python-centric workflow
- ✅ Simple to moderate CUDA kernels
- ✅ Want minimal setup and dependencies
- ✅ Deploying in Python environments

### Use C++/CUDA When:
- ✅ Complex CUDA optimizations needed
- ✅ Large existing CUDA codebase
- ✅ Maximum compile-time error checking
- ✅ Sharing kernels across multiple languages
- ✅ Pre-compilation for deployment

## Code Comparison

### PyCUDA Version (draw_rect_pycuda.py)

```python
import pycuda.autoinit
from pycuda.compiler import SourceModule

# Kernel defined as Python string
CUDA_KERNEL_CODE = """
__global__ void draw_rectangle_kernel(
    unsigned char* y_plane,
    int width, int height, int stride,
    int x, int y, int w, int h,
    unsigned char color
) {
    // CUDA kernel code here...
}
"""

class PyCUDADrawRect:
    def __init__(self):
        # Compile kernel at runtime
        self.mod = SourceModule(CUDA_KERNEL_CODE)
        self.draw_kernel = self.mod.get_function("draw_rectangle_kernel")
    
    def draw_rectangle(self, d_y_plane_ptr, width, height, ...):
        # Launch kernel
        self.draw_kernel(
            np.intp(d_y_plane_ptr),
            np.int32(width),
            # ...
            block=(256, 1, 1),
            grid=(blocks_x, 4, 1)
        )
```

**Advantages:**
- ✅ No separate build step
- ✅ Kernel and Python code together
- ✅ Easy to modify and test
- ✅ Automatic GPU initialization

### C++/CUDA Version (cuda_draw.cu + draw_rect.py)

**cuda_draw.cu:**
```c++
extern "C" {
__global__ void draw_rectangle_kernel(
    unsigned char* y_plane,
    int width, int height, int stride,
    int x, int y, int w, int h,
    unsigned char color
) {
    // CUDA kernel code here...
}

cudaError_t draw_rectangle(...) {
    // Launch kernel
    draw_rectangle_kernel<<<grid, block>>>(...);
    return cudaGetLastError();
}
}
```

**draw_rect.py:**
```python
import ctypes

class CudaDrawRect:
    def __init__(self, lib_path='libcuda_draw.so'):
        # Load pre-compiled library
        self.lib = ctypes.CDLL(lib_path)
        # Define function signatures...
    
    def draw_rectangle(self, d_y_plane, ...):
        err = self.lib.draw_rectangle(...)
        if err != 0:
            raise RuntimeError(f"CUDA error: {err}")
```

**Build:**
```bash
nvcc -arch=sm_86 -shared -o libcuda_draw.so cuda_draw.cu
```

**Advantages:**
- ✅ Compile-time error checking
- ✅ Traditional CUDA workflow
- ✅ Can optimize compiler flags
- ✅ Familiar to CUDA developers

## Performance Comparison

Both approaches produce **identical runtime performance**:
- PyCUDA uses JIT compilation (compiled on first run)
- C++/CUDA is AOT compilation (compiled before run)
- Once compiled, the GPU code is identical

**Compilation Time:**
- PyCUDA: ~1-2 seconds on first run
- C++/CUDA: ~1-2 seconds during build
- Subsequent runs: Both instant (kernel cached)

## Best Practices

### For PyCUDA:
```python
# Cache kernel compilation
class MyKernel:
    _kernel = None
    
    @classmethod
    def get_kernel(cls):
        if cls._kernel is None:
            cls._kernel = SourceModule(KERNEL_CODE)
        return cls._kernel

# Use proper data types
self.kernel(
    np.intp(ptr),      # Pointers
    np.int32(value),   # 32-bit integers
    np.float32(val),   # 32-bit floats
    np.uint8(color),   # Unsigned bytes
    block=(...),
    grid=(...)
)

# Error handling
try:
    kernel(...)
except cuda.Error as e:
    print(f"CUDA error: {e}")
```

### For C++/CUDA:
```c++
// Always check errors
cudaError_t err = cudaGetLastError();
if (err != cudaSuccess) {
    return err;
}

// Use proper calling convention
extern "C" {
    // Functions to export
}

// Validate inputs
if (x < 0 || y < 0 || w <= 0 || h <= 0) {
    return cudaErrorInvalidValue;
}
```

## Recommendation

**Start with PyCUDA** for this project because:
1. ⚡ Faster development (no build step)
2. 🎯 Everything in Python
3. 🛠️ Easier to modify and experiment
4. 📦 Simpler deployment
5. 🚀 Same performance as C++

**Switch to C++/CUDA** if:
- You need compile-time validation
- You're building a production library
- You need to share with non-Python code
- You have complex CUDA optimizations

## References

- [PyCUDA Documentation](https://documen.tician.de/pycuda/)
- [CUDA C++ Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/)
- [PyCUDA Tutorial](https://thedatafrog.com/en/articles/cuda-kernel-python/)
