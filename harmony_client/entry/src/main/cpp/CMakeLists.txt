cmake_minimum_required(VERSION 3.4.1)
project(nascab_webrtc)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(nascab_webrtc SHARED
    napi_init.cpp
    webrtc_bridge.cpp
)

target_link_libraries(nascab_webrtc PUBLIC libace_napi.z.so)
