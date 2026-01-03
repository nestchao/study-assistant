# backend_cpp/CMakeLists.txt
cmake_minimum_required(VERSION 3.24)
project(synapse_flow_backend VERSION 2.1.0 LANGUAGES C CXX)

# 🚀 SETTINGS
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# 🚀 VCPKG INTEGRATION
if(DEFINED ENV{VCPKG_ROOT})
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
endif()

# 🚀 FIND PACKAGES
find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf CONFIG REQUIRED)
find_package(nlohmann_json CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)
find_package(cpr CONFIG REQUIRED)
find_package(OpenMP REQUIRED)
find_package(faiss CONFIG REQUIRED)

# --- FIX: Add httplib find_package ---
# httplib is header-only, so find_package mostly just sets include directories.
# Make sure 'httplib' is listed in your vcpkg.json or is otherwise available.
find_package(httplib CONFIG) # Assuming vcpkg provides a CONFIG file for it.
# If httplib is not found via CONFIG, you might need:
# find_path(HTTPLIB_INCLUDE_DIR httplib.h HINTS "${VCPKG_ROOT}/installed/x64-windows/include")
# set(HTTPLIB_FOUND TRUE)
# set(HTTPLIB_INCLUDE_DIRS ${HTTPLIB_INCLUDE_DIR})

# 🚀 PROTOBUF GENERATION
get_target_property(grpc_cpp_plugin gRPC::grpc_cpp_plugin LOCATION)

# --- FIX: Pointing to the correct source directory (proto/, not include/proto/) ---
set(PROTO_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/proto")
set(PROTO_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")

file(MAKE_DIRECTORY ${PROTO_GEN_DIR})

set(PROTO_FILES "${PROTO_SRC_DIR}/agent.proto")
set(PROTO_HDRS "${PROTO_GEN_DIR}/agent.pb.h" "${PROTO_GEN_DIR}/agent.grpc.pb.h")
set(PROTO_SRCS "${PROTO_GEN_DIR}/agent.pb.cc" "${PROTO_GEN_DIR}/agent.grpc.pb.cc")

message(STATUS "🛰️  Proto Source: ${PROTO_FILES}")
message(STATUS "🛰️  Proto Output: ${PROTO_GEN_DIR}")

add_custom_command(
    OUTPUT ${PROTO_SRCS} ${PROTO_HDRS}
    COMMAND protobuf::protoc
    ARGS --grpc_out=${PROTO_GEN_DIR}
         --cpp_out=${PROTO_GEN_DIR}
         --plugin=protoc-gen-grpc=${grpc_cpp_plugin}
         -I ${PROTO_SRC_DIR}
         ${PROTO_FILES}
    DEPENDS ${PROTO_FILES}
)

# 🚀 SOURCE FILES
set(AGENT_SOURCES
    src/agent/AgentExecutor.cpp
    src/agent/AgentService.cpp
    src/agent/SubAgent.cpp
    src/agent_main.cpp
    ${PROTO_SRCS}
)

set(CORE_SOURCES
    src/main.cpp
    src/embedding_service.cpp
    src/retrieval_engine.cpp
    src/faiss_vector_store.cpp
    src/code_graph.cpp
    src/cache_manager.cpp
    src/sync_service.cpp
    src/parser_elite.cpp
    src/tools/FileSystemTools.cpp
    src/tools/WebSearchTool.cpp
    src/tools/VisionTool.cpp
)

# Tree-sitter Bridges
set(TS_SOURCES
    src/ts_cpp_bridge.cpp
    src/ts_typescript_bridge.cpp
)

# 🚀 EXECUTABLE: REST API SERVER (Port 5002)
add_executable(code_assistance_server ${CORE_SOURCES} ${PROTO_SRCS} src/agent/AgentExecutor.cpp src/agent/SubAgent.cpp)
target_include_directories(code_assistance_server PRIVATE include ${PROTO_GEN_DIR})
target_link_libraries(code_assistance_server PRIVATE
    nlohmann_json::nlohmann_json
    spdlog::spdlog
    cpr::cpr
    faiss
    OpenMP::OpenMP_CXX
    tree-sitter
)

# 🚀 EXECUTABLE: gRPC AGENT SERVICE (Port 50051)
add_executable(agent_service ${AGENT_SOURCES} ${CORE_SOURCES}) 
target_include_directories(agent_service PRIVATE include ${PROTO_GEN_DIR})
target_link_libraries(agent_service PRIVATE
    gRPC::grpc++
    protobuf::libprotobuf
    nlohmann_json::nlohmann_json
    spdlog::spdlog
    cpr::cpr
    faiss
    OpenMP::OpenMP_CXX
    tree-sitter
)

# 🚀 PLATFORM SPECIFICS
if(WIN32)
    # Using the standardized SystemMonitor now, we still need psapi. 
    # pdh.lib is gated inside the cpp file, but linking it is harmless.
    target_link_libraries(code_assistance_server PRIVATE pdh.lib psapi.lib)
    target_link_libraries(agent_service PRIVATE pdh.lib psapi.lib)
endif()

# 🚀 ASSET DEPLOYMENT
add_custom_command(TARGET code_assistance_server POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/keys.json"
    "$<TARGET_FILE_DIR:code_assistance_server>/keys.json"
)

add_custom_command(TARGET code_assistance_server POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${CMAKE_CURRENT_SOURCE_DIR}/www"
    "$<TARGET_FILE_DIR:code_assistance_server>/www"
)