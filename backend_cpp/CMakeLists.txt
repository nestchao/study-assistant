cmake_minimum_required(VERSION 3.21)
project(CodeAssistanceBackend CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 1. Dependencies (REMOVED dotenv)
find_package(cpr REQUIRED)
find_package(spdlog REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(OpenMP REQUIRED)

# 2. FAISS Setup
find_path(FAISS_INCLUDE_DIR NAMES faiss/index_io.h HINTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include")
find_library(FAISS_LIBRARY NAMES faiss HINTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib")
find_library(OPENBLAS_LIBRARY NAMES openblas HINTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib")

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party
    ${FAISS_INCLUDE_DIR}
)

add_executable(code_assistance_server
    src/main.cpp
    src/embedding_service.cpp
    src/code_graph.cpp
    src/retrieval_engine.cpp
    src/faiss_vector_store.cpp
    src/sync_service.cpp      
    src/cache_manager.cpp 
)

# 3. Linking (REMOVED dotenv::dotenv)
target_link_libraries(code_assistance_server PRIVATE
    cpr::cpr
    spdlog::spdlog
    nlohmann_json::nlohmann_json
    OpenMP::OpenMP_CXX
    ${FAISS_LIBRARY}
    ${OPENBLAS_LIBRARY}
    pdh
)

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

# 1. Find Python so we can run the script
find_package(Python3 COMPONENTS Interpreter QUIET)

# 2. AUTOMATIC COPY: Copy read_logs.py next to the executable after every build
add_custom_command(TARGET code_assistance_server POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
    "${CMAKE_CURRENT_SOURCE_DIR}/test/read_logs.py"
    "$<TARGET_FILE_DIR:code_assistance_server>/read_logs.py"
    COMMENT "📂 Copying read_logs.py to executable directory..."
)

# 3. RUN TARGET: Create a custom command to run the script easily
if (Python3_FOUND)
    add_custom_target(read_logs
        COMMAND ${Python3_EXECUTABLE} "read_logs.py"
        WORKING_DIRECTORY "$<TARGET_FILE_DIR:code_assistance_server>"
        COMMENT "📜 Reading latest interaction logs..."
        USES_TERMINAL
    )
    message(STATUS "✅ Log reader integrated. You can run: cmake --build . --target read_logs")
else()
    message(WARNING "⚠️ Python3 not found. The 'read_logs' target will not be available.")
endif()

# ==============================================================================
# INTEGRATION: FLIGHT CERTIFICATION (Quality Tests)
# ==============================================================================

# 1. AUTOMATIC COPY: Copy test_quality.py to executable directory
add_custom_command(TARGET code_assistance_server POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
    "${CMAKE_CURRENT_SOURCE_DIR}/test/test_quality.py"
    "$<TARGET_FILE_DIR:code_assistance_server>/test_quality.py"
    COMMENT "📂 Copying test_quality.py to executable directory..."
)

# 2. RUN TARGET: Create 'check_quality' command
if (Python3_FOUND)
    add_custom_target(check_quality
        COMMAND ${Python3_EXECUTABLE} "test_quality.py"
        WORKING_DIRECTORY "$<TARGET_FILE_DIR:code_assistance_server>"
        COMMENT "🧪 Running Flight Certification Suite..."
        USES_TERMINAL
    )
    message(STATUS "✅ Quality Suite integrated. You can run: cmake --build . --target check_quality")
endif()

# 3. AUTOMATIC COPY: Deploy .env to the Release folder
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/.env")
    add_custom_command(TARGET code_assistance_server POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/.env"
        "$<TARGET_FILE_DIR:code_assistance_server>/.env"
        COMMENT "🔑 Deploying .env configuration to binary directory..."
    )
else()
    message(WARNING "⚠️ .env file not found in source root. You must create it manually in the bin folder.")
endif()