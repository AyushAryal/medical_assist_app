# Builds libclinical_llm.so: the four-function shim with llama.cpp statically
# linked inside, so exactly one artefact ships per ABI and the Dart FFI layer
# has no dependency graph to get wrong.
#
# Reproduce with tool/build_llm_shim.sh, which pins the llama.cpp tag.
cmake_minimum_required(VERSION 3.22)
project(clinical_llm C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Static llama + ggml folded into our one shared library.
set(BUILD_SHARED_LIBS OFF)
set(LLAMA_BUILD_TESTS OFF)
set(LLAMA_BUILD_EXAMPLES OFF)
set(LLAMA_BUILD_TOOLS OFF)
set(LLAMA_BUILD_SERVER OFF)
set(LLAMA_CURL OFF)
# CPU only, everywhere: a clinic tablet has no CUDA, and a predictable memory
# footprint matters more than a benchmark.
set(GGML_METAL OFF)
set(GGML_CUDA OFF)
set(GGML_VULKAN OFF)
set(GGML_OPENCL OFF)

add_subdirectory(${LLAMA_CPP_DIR} llama.cpp-build)

add_library(clinical_llm SHARED clinical_llm.c)
target_link_libraries(clinical_llm PRIVATE llama)
target_include_directories(clinical_llm PRIVATE ${LLAMA_CPP_DIR}/include ${LLAMA_CPP_DIR}/ggml/include)
