cmake_minimum_required(VERSION 3.21)
project(CodeAssistanceSystem CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 1. Dependency Discovery (vcpkg manifest mode)
find_package(cpr REQUIRED)
find_package(spdlog REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(OpenMP REQUIRED)
find_package(faiss CONFIG REQUIRED)
find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf CONFIG REQUIRED)

# 2. Proto & gRPC Code Generation
find_program(PROTOC_EXECUTABLE NAMES protoc HINTS ${_PROTOBUF_PROTOC_EXECUTABLE})
find_program(GRPC_CPP_PLUGIN_EXECUTABLE NAMES grpc_cpp_plugin)

set(PROTO_SRC "${CMAKE_CURRENT_SOURCE_DIR}/proto/agent.proto")
set(PROTO_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY ${PROTO_OUT_DIR})

set(GEN_PB_SRC "${PROTO_OUT_DIR}/agent.pb.cc")
set(GEN_PB_HDR "${PROTO_OUT_DIR}/agent.pb.h")
set(GEN_GRPC_SRC "${PROTO_OUT_DIR}/agent.grpc.pb.cc")
set(GEN_GRPC_HDR "${PROTO_OUT_DIR}/agent.grpc.pb.h")

set_source_files_properties(${GEN_PB_SRC} ${GEN_GRPC_SRC} PROPERTIES GENERATED TRUE)

add_custom_command(
    OUTPUT ${GEN_PB_SRC} ${GEN_PB_HDR} ${GEN_GRPC_SRC} ${GEN_GRPC_HDR}
    COMMAND ${PROTOC_EXECUTABLE}
    ARGS --cpp_out=${PROTO_OUT_DIR}
         --grpc_out=${PROTO_OUT_DIR}
         --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXECUTABLE}
         -I${CMAKE_CURRENT_SOURCE_DIR}/proto
         ${PROTO_SRC}
    DEPENDS ${PROTO_SRC}
    COMMENT "🛠️ Generating gRPC code from agent.proto..."
)

# 3. The Core Intelligence Library (Shared Logic)
add_library(core_engine STATIC
    src/embedding_service.cpp
    src/code_graph.cpp
    src/retrieval_engine.cpp
    src/faiss_vector_store.cpp
    src/sync_service.cpp
    src/cache_manager.cpp
    src/agent/SubAgent.cpp
    src/agent/AgentExecutor.cpp    # 🚀 Moved from executable to library
    src/tools/WebSearchTool.cpp    # 🚀 Moved from executable to library
    ${GEN_PB_SRC}
    ${GEN_GRPC_SRC}
)

# Ensure protos generate before engine compiles
add_custom_target(generate_protos DEPENDS ${GEN_PB_SRC} ${GEN_GRPC_SRC})
add_dependencies(core_engine generate_protos)

target_include_directories(core_engine PUBLIC 
    include 
    ${PROTO_OUT_DIR} # 🚀 This allows #include "agent.pb.h"
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party
)

target_link_libraries(core_engine PUBLIC
    cpr::cpr
    spdlog::spdlog
    nlohmann_json::nlohmann_json
    OpenMP::OpenMP_CXX
    faiss
    gRPC::grpc++
    protobuf::libprotobuf
    pdh
)

# 4. The Executables (Entry Points)
# REST Server (Mission Control Dashboard)
add_executable(code_assistance_server src/main.cpp)
target_link_libraries(code_assistance_server PRIVATE core_engine)

# gRPC Agent (The Cognitive Brain)
# 🚀 FIXED: Removed AgentExecutor.cpp from here (it's now in core_engine)
add_executable(agent_service src/agent_main.cpp)
target_link_libraries(agent_service PRIVATE core_engine)

# 5. Build Optimizations (Windows/MSVC)
if(MSVC)
    target_compile_options(core_engine PRIVATE /O2 /Oi /Ot /openmp)
    target_compile_definitions(core_engine PUBLIC _CRT_SECURE_NO_WARNINGS)
endif()

# 6. Deployment Automation (SpaceX Precision)
set(DEPLOY_DIR "$<TARGET_FILE_DIR:code_assistance_server>")

add_custom_command(TARGET code_assistance_server POST_BUILD
    # 🚀 THE FIX: Copy the entire FOLDER, not just one file
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/www" "${DEPLOY_DIR}/www"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/keys.json" "${DEPLOY_DIR}/keys.json"
    COMMENT "🛰️ Syncing www assets to binary folder..."
)