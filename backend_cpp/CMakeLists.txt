# backend_cpp/CMakeLists.txt
cmake_minimum_required(VERSION 3.15)
project(CodeAssistanceBackend CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Find Dependencies (using vcpkg or system install) ---
# For vcpkg, you would run:
# vcpkg install faiss:x64-windows cpr:x64-windows spdlog:x64-windows nlohmann-json:x64-windows
# And then configure cmake with:
# cmake .. -DCMAKE_TOOLCHAIN_FILE=[path-to-vcpkg]/scripts/buildsystems/vcpkg.cmake
find_package(FAISS REQUIRED)
find_package(cpr REQUIRED)
find_package(spdlog REQUIRED)
find_package(nlohmann_json REQUIRED)

# --- Add our single-header libraries ---
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party # Assumes httplib.h is in here
)

# --- Define the Executable ---
add_executable(code_assistance_server
    src/main.cpp
    src/embedding_service.cpp
    src/code_graph.cpp
    src/retrieval_engine.cpp
    src/faiss_vector_store.cpp
)

# --- Link Libraries ---
target_link_libraries(code_assistance_server PRIVATE
    FAISS::faiss
    cpr::cpr
    spdlog::spdlog
    nlohmann_json::nlohmann_json
)

# --- Include Paths for our own headers ---
target_include_directories(code_assistance_server PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# --- Set compiler flags for performance ---
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    message(STATUS "Release build: Enabling optimizations")
    target_compile_options(code_assistance_server PRIVATE -O3 -DNDEBUG)
endif()

# --- Installation (Optional) ---
install(TARGETS code_assistance_server DESTINATION bin)