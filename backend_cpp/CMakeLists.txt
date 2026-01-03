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
# Order matters: Dependencies first
find_package(absl CONFIG REQUIRED)        # <--- CRITICAL FIX
find_package(utf8_range CONFIG REQUIRED)  # <--- CRITICAL FIX (Protobuf dependency)
find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf CONFIG REQUIRED)
find_package(nlohmann_json CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)
find_package(cpr CONFIG REQUIRED)
find_package(OpenMP REQUIRED)
find_package(faiss CONFIG REQUIRED)

# Robust httplib
find_package(httplib CONFIG)
if(NOT httplib_FOUND)
    find_path(HTTPLIB_INCLUDE_DIR httplib.h)
    if(HTTPLIB_INCLUDE_DIR)
        add_library(httplib::httplib INTERFACE IMPORTED)
        target_include_directories(httplib::httplib INTERFACE ${HTTPLIB_INCLUDE_DIR})
        if(WIN32) 
            target_link_libraries(httplib::httplib INTERFACE ws2_32 crypt32 cryptui)
        endif()
    endif()
endif()

# Robust Tree-sitter
find_path(TREESITTER_INCLUDE_DIR tree_sitter/api.h)
find_library(TREESITTER_LIBRARY NAMES tree-sitter libtree-sitter tree-sitter.lib)

# 🚀 PROTOBUF GENERATION
get_target_property(grpc_cpp_plugin gRPC::grpc_cpp_plugin LOCATION)
set(PROTO_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/proto")
set(PROTO_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY ${PROTO_GEN_DIR})
set(PROTO_FILES "${PROTO_SRC_DIR}/agent.proto")
set(PROTO_SRCS "${PROTO_GEN_DIR}/agent.pb.cc" "${PROTO_GEN_DIR}/agent.grpc.pb.cc")

add_custom_command(
    OUTPUT ${PROTO_SRCS} "${PROTO_GEN_DIR}/agent.pb.h" "${PROTO_GEN_DIR}/agent.grpc.pb.h"
    COMMAND protobuf::protoc
    ARGS --grpc_out=${PROTO_GEN_DIR} --cpp_out=${PROTO_GEN_DIR} --plugin=protoc-gen-grpc=${grpc_cpp_plugin} -I ${PROTO_SRC_DIR} ${PROTO_FILES}
    DEPENDS ${PROTO_FILES}
)

# 🚀 AUTO-DETECT GRAMMAR SOURCES
set(GRAMMAR_SOURCES "")
macro(add_grammar_source PATH SUBPATH)
    set(BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/${PATH}/${SUBPATH}")
    if(EXISTS "${BASE_DIR}/parser.c")
        list(APPEND GRAMMAR_SOURCES "${BASE_DIR}/parser.c")
    endif()
    if(EXISTS "${BASE_DIR}/scanner.c")
        list(APPEND GRAMMAR_SOURCES "${BASE_DIR}/scanner.c")
    elseif(EXISTS "${BASE_DIR}/scanner.cc")
        list(APPEND GRAMMAR_SOURCES "${BASE_DIR}/scanner.cc")
    endif()
endmacro()

add_grammar_source("tree-sitter-cpp" "src")
add_grammar_source("tree-sitter-python" "src")
add_grammar_source("tree-sitter-typescript" "typescript/src")

# 🚀 SOURCE GROUPING
set(AGENT_SOURCES
    src/agent/AgentExecutor.cpp
    src/agent/SubAgent.cpp
    src/agent_main.cpp
    ${PROTO_SRCS}
)

set(CORE_SOURCES
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

# 🚀 EXECUTABLE: REST API SERVER
add_executable(code_assistance_server 
    src/main.cpp 
    ${CORE_SOURCES} 
    ${PROTO_SRCS} 
    ${GRAMMAR_SOURCES} 
    src/agent/AgentExecutor.cpp 
    src/agent/SubAgent.cpp
)

target_include_directories(code_assistance_server PRIVATE include ${PROTO_GEN_DIR} ${TREESITTER_INCLUDE_DIR})
target_link_libraries(code_assistance_server PRIVATE
    nlohmann_json::nlohmann_json spdlog::spdlog cpr::cpr faiss OpenMP::OpenMP_CXX 
    httplib::httplib ${TREESITTER_LIBRARY}
    protobuf::libprotobuf gRPC::grpc++ absl::base absl::strings absl::log_internal_message # Explicit linking helps
)

# 🚀 EXECUTABLE: gRPC AGENT SERVICE
add_executable(agent_service 
    ${AGENT_SOURCES} 
    ${CORE_SOURCES} 
    ${GRAMMAR_SOURCES}
)

target_include_directories(agent_service PRIVATE include ${PROTO_GEN_DIR} ${TREESITTER_INCLUDE_DIR})
target_link_libraries(agent_service PRIVATE
    gRPC::grpc++ protobuf::libprotobuf nlohmann_json::nlohmann_json spdlog::spdlog cpr::cpr 
    faiss OpenMP::OpenMP_CXX ${TREESITTER_LIBRARY}
    absl::base absl::strings absl::log_internal_message # Explicit linking helps
)

if(WIN32)
    target_link_libraries(code_assistance_server PRIVATE pdh.lib psapi.lib)
    target_link_libraries(agent_service PRIVATE pdh.lib psapi.lib)
endif()

# ASSETS
add_custom_command(TARGET code_assistance_server POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/keys.json" "$<TARGET_FILE_DIR:code_assistance_server>/keys.json")
add_custom_command(TARGET code_assistance_server POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/www" "$<TARGET_FILE_DIR:code_assistance_server>/www")