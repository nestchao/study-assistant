cmake_minimum_required(VERSION 3.21)
project(CodeAssistanceSystem CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
enable_language(C)

# 1. Dependency Discovery
find_package(cpr REQUIRED)
find_package(spdlog REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(OpenMP REQUIRED)
find_package(faiss CONFIG REQUIRED)
find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf CONFIG REQUIRED)

find_path(TREE_SITTER_INCLUDE_DIR tree_sitter/api.h REQUIRED)
find_library(TREE_SITTER_LIBRARY NAMES tree-sitter REQUIRED)

# 2. Modular Grammar Compilation (Isolating Symbols)
# 2. Modular Grammar Compilation (Isolating Symbols & Linkage)

# 🛰️ CPP Module: Hybrid C/C++ assembly
add_library(ts_cpp STATIC 
    third_party/tree-sitter-cpp/src/parser.c  # Compiled as C
    src/ts_cpp_bridge.cpp                      # Compiled as C++ (Wraps scanner.c)
)
target_include_directories(ts_cpp PRIVATE 
    third_party/tree-sitter-cpp/src 
    ${TREE_SITTER_INCLUDE_DIR})

# 🛰️ Python Module: Pure C assembly
add_library(ts_python STATIC 
    third_party/tree-sitter-python/src/parser.c 
    third_party/tree-sitter-python/src/scanner.c)
target_include_directories(ts_python PRIVATE 
    third_party/tree-sitter-python/src 
    ${TREE_SITTER_INCLUDE_DIR})

# 🛰️ TypeScript Module: Hybrid C/C++ assembly
add_library(ts_typescript STATIC 
    third_party/tree-sitter-typescript/typescript/src/parser.c # Compiled as C
    src/ts_typescript_bridge.cpp                                # Compiled as C++ (Wraps scanner.c)
)
target_include_directories(ts_typescript PRIVATE 
    third_party/tree-sitter-typescript/typescript/src 
    ${TREE_SITTER_INCLUDE_DIR})

# 3. Proto & gRPC Code Generation
find_program(PROTOC_EXECUTABLE NAMES protoc HINTS ${_PROTOBUF_PROTOC_EXECUTABLE})
find_program(GRPC_CPP_PLUGIN_EXECUTABLE NAMES grpc_cpp_plugin)
set(PROTO_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY ${PROTO_OUT_DIR})
set(GEN_PB_SRC "${PROTO_OUT_DIR}/agent.pb.cc")
set(GEN_PB_HDR "${PROTO_OUT_DIR}/agent.pb.h")
set(GEN_GRPC_SRC "${PROTO_OUT_DIR}/agent.grpc.pb.cc")
set(GEN_GRPC_HDR "${PROTO_OUT_DIR}/agent.grpc.pb.h")

add_custom_command(
    OUTPUT ${GEN_PB_SRC} ${GEN_PB_HDR} ${GEN_GRPC_SRC} ${GEN_GRPC_HDR}
    COMMAND ${PROTOC_EXECUTABLE}
    ARGS --cpp_out=${PROTO_OUT_DIR} --grpc_out=${PROTO_OUT_DIR} --plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN_EXECUTABLE} -I${CMAKE_CURRENT_SOURCE_DIR}/proto ${CMAKE_CURRENT_SOURCE_DIR}/proto/agent.proto
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/proto/agent.proto
)

# 4. Core Engine Library
add_library(core_engine STATIC
    src/embedding_service.cpp
    src/code_graph.cpp
    src/retrieval_engine.cpp
    src/faiss_vector_store.cpp
    src/sync_service.cpp
    src/cache_manager.cpp
    src/agent/SubAgent.cpp
    src/agent/AgentExecutor.cpp
    src/tools/WebSearchTool.cpp
    src/parser_elite.cpp 
    src/tools/FileSystemTools.cpp
    src/tools/VisionTool.cpp
    ${GEN_PB_SRC}
    ${GEN_GRPC_SRC}
)
add_custom_target(generate_protos DEPENDS ${GEN_PB_SRC} ${GEN_GRPC_SRC})
add_dependencies(core_engine generate_protos)

target_include_directories(core_engine PUBLIC 
    include ${PROTO_OUT_DIR} ${TREE_SITTER_INCLUDE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/third_party
)

# 🚀 LINKING MODULAR SENSORS
target_link_libraries(core_engine PUBLIC
    cpr::cpr spdlog::spdlog nlohmann_json::nlohmann_json OpenMP::OpenMP_CXX
    faiss gRPC::grpc++ protobuf::libprotobuf pdh
    ${TREE_SITTER_LIBRARY}
    ts_cpp ts_python ts_typescript
)

# 5. Executables
add_executable(code_assistance_server src/main.cpp)
target_link_libraries(code_assistance_server PRIVATE core_engine)
add_executable(agent_service src/agent_main.cpp)
target_link_libraries(agent_service PRIVATE core_engine)

if(MSVC)
    target_compile_options(core_engine PRIVATE /O2 /Oi /Ot /openmp)
    target_compile_definitions(core_engine PUBLIC _CRT_SECURE_NO_WARNINGS)
endif()

# 6. Deployment
set(DEPLOY_DIR "$<TARGET_FILE_DIR:code_assistance_server>")
add_custom_command(TARGET code_assistance_server POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/www" "${DEPLOY_DIR}/www"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/keys.json" "${DEPLOY_DIR}/keys.json"
)