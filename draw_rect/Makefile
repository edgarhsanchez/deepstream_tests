# Makefile for CUDA rectangle drawing library

NVCC := nvcc
CUDA_ARCH := sm_86
CUDA_FLAGS := -arch=$(CUDA_ARCH) --compiler-options '-fPIC' -O3
CUDA_LIBS := -lcudart

# Target library
TARGET := libcuda_draw.so

# Source files
CUDA_SRC := cuda_draw.cu

# Build shared library
$(TARGET): $(CUDA_SRC)
	$(NVCC) $(CUDA_FLAGS) -shared -o $@ $^ $(CUDA_LIBS)

# Clean build artifacts
clean:
	rm -f $(TARGET)

# Test build
test: $(TARGET)
	@echo "Library built successfully: $(TARGET)"
	@ls -lh $(TARGET)

.PHONY: clean test
