cmake_minimum_required(VERSION 3.20)
project(live_mixer_engine VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(live_mixer_engine SHARED
    live_mixer_engine.cpp
)

target_include_directories(live_mixer_engine
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

set_target_properties(live_mixer_engine PROPERTIES
    OUTPUT_NAME "live_mixer_engine"
    PREFIX "lib"
)

# Platform-specific audio library links
if(APPLE)
    find_library(CORE_AUDIO CoreAudio REQUIRED)
    find_library(AUDIO_TOOLBOX AudioToolbox REQUIRED)
    target_link_libraries(live_mixer_engine PRIVATE ${CORE_AUDIO} ${AUDIO_TOOLBOX})
elseif(UNIX AND NOT APPLE)
    find_package(Threads REQUIRED)
    target_link_libraries(live_mixer_engine PRIVATE Threads::Threads asound)
elseif(WIN32)
    target_link_libraries(live_mixer_engine PRIVATE mfplat mfuuid ole32)
endif()

include(CTest)

if(BUILD_TESTING)
    add_executable(engine_signal_tests
        tests/engine_signal_tests.cpp
    )
    target_include_directories(engine_signal_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    add_dependencies(engine_signal_tests live_mixer_engine)
    if(UNIX AND NOT APPLE)
        target_link_libraries(engine_signal_tests PRIVATE dl)
    endif()
    add_test(
        NAME engine_signal_tests
        COMMAND engine_signal_tests $<TARGET_FILE:live_mixer_engine>
    )

    add_executable(spsc_ring_buffer_tests
        tests/spsc_ring_buffer_tests.cpp
    )
    target_include_directories(spsc_ring_buffer_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    add_test(
        NAME spsc_ring_buffer_tests
        COMMAND spsc_ring_buffer_tests
    )

    add_executable(device_catalog_contract_tests
        tests/device_catalog_contract_tests.cpp
    )
    target_include_directories(device_catalog_contract_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    add_dependencies(device_catalog_contract_tests live_mixer_engine)
    if(UNIX AND NOT APPLE)
        target_link_libraries(device_catalog_contract_tests PRIVATE dl)
    endif()
    add_test(
        NAME device_catalog_contract_tests
        COMMAND device_catalog_contract_tests $<TARGET_FILE:live_mixer_engine>
    )
endif()
