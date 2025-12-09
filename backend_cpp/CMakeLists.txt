# backend_cpp/CMakeLists.txt
cmake_minimum_required(VERSION 3.21)
project(CodeAssistanceBackend CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Find Dependencies (vcpkg) ---
# We still use find_package for the simple libraries
find_package(cpr REQUIRED)
find_package(spdlog REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(OpenMP REQUIRED)

# --- Manually Find FAISS and its Dependencies ---
# This is the robust workaround. We tell CMake to find the header files
# and the actual library files directly.
find_path(FAISS_INCLUDE_DIR NAMES faiss/index_io.h HINTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include")
find_library(FAISS_LIBRARY NAMES faiss HINTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib")
find_library(OPENBLAS_LIBRARY NAMES openblas HINTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib")

if(NOT FAISS_INCLUDE_DIR OR NOT FAISS_LIBRARY)
    message(FATAL_ERROR "Could not find FAISS headers or library files. Please check vcpkg installation.")
endif()
message(STATUS "Found FAISS Include Dir: ${FAISS_INCLUDE_DIR}")
message(STATUS "Found FAISS Library: ${FAISS_LIBRARY}")
if(OPENBLAS_LIBRARY)
    message(STATUS "Found OpenBLAS Library: ${OPENBLAS_LIBRARY}")
endif()


# --- Include Directories ---
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party
    ${FAISS_INCLUDE_DIR}  # Manually add the FAISS include path
)

# --- Define the Executable ---
add_executable(code_assistance_server
    src/main.cpp
    src/embedding_service.cpp
    src/code_graph.cpp
    src/retrieval_engine.cpp
    src/faiss_vector_store.cpp
)

# --- Link All Libraries ---
target_link_libraries(code_assistance_server PRIVATE
    # Vcpkg packages via find_package
    cpr::cpr
    spdlog::spdlog
    nlohmann_json::nlohmann_json
    OpenMP::OpenMP_CXX

    # Manually found libraries
    ${FAISS_LIBRARY}
    ${OPENBLAS_LIBRARY}
)

# --- Include Paths for our own headers ---
target_include_directories(code_assistance_server PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# --- Set compiler flags for performance ---
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    message(STATUS "Release build: Enabling optimizations")
    target_compile_options(code_assistance_server PRIVATE /O2)
endif()

# --- Installation (Optional) ---
install(TARGETS code_assistance_server DESTINATION bin)