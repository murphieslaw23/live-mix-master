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

if(APPLE)
    enable_language(OBJCXX)
    target_sources(live_mixer_engine PRIVATE
        macos/coreaudio_device_catalog.mm
        macos/coreaudio_capture.mm
        macos/audio_input_permissions.mm
    )
    find_library(CORE_AUDIO CoreAudio REQUIRED)
    find_library(CORE_FOUNDATION CoreFoundation REQUIRED)
    find_library(AUDIO_TOOLBOX AudioToolbox REQUIRED)
    find_library(AV_FOUNDATION AVFoundation REQUIRED)
    target_link_libraries(live_mixer_engine PRIVATE
        ${CORE_AUDIO}
        ${CORE_FOUNDATION}
        ${AUDIO_TOOLBOX}
        ${AV_FOUNDATION}
    )

    add_executable(macos_device_probe tools/macos_device_probe.cpp)
    target_include_directories(macos_device_probe PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    target_link_libraries(macos_device_probe PRIVATE live_mixer_engine)
elseif(UNIX AND NOT APPLE)
    find_package(Threads REQUIRED)
    target_link_libraries(live_mixer_engine PRIVATE Threads::Threads asound)
elseif(WIN32)
    target_link_libraries(live_mixer_engine PRIVATE mfplat mfuuid ole32)
endif()

include(CTest)

if(BUILD_TESTING)
    target_compile_definitions(live_mixer_engine PRIVATE LMM_BUILD_TESTING=1)

    add_executable(native_gain_control_contract_tests tests/native_gain_control_contract_tests.cpp)
    add_dependencies(native_gain_control_contract_tests live_mixer_engine)
    if(UNIX)
        target_link_libraries(native_gain_control_contract_tests PRIVATE ${CMAKE_DL_LIBS})
    endif()
    add_test(NAME native_gain_control_contract_tests
        COMMAND native_gain_control_contract_tests $<TARGET_FILE:live_mixer_engine>)

    add_executable(engine_signal_tests tests/engine_signal_tests.cpp)
    target_include_directories(engine_signal_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    add_dependencies(engine_signal_tests live_mixer_engine)
    if(UNIX)
        target_link_libraries(engine_signal_tests PRIVATE ${CMAKE_DL_LIBS})
    endif()
    add_test(NAME engine_signal_tests
        COMMAND engine_signal_tests $<TARGET_FILE:live_mixer_engine>)

    add_executable(spsc_ring_buffer_tests tests/spsc_ring_buffer_tests.cpp)
    target_include_directories(spsc_ring_buffer_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    add_test(NAME spsc_ring_buffer_tests COMMAND spsc_ring_buffer_tests)

    add_executable(pcm_handoff_tests tests/pcm_handoff_tests.cpp)
    target_include_directories(pcm_handoff_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    add_dependencies(pcm_handoff_tests live_mixer_engine)
    if(UNIX)
        target_link_libraries(pcm_handoff_tests PRIVATE ${CMAKE_DL_LIBS})
    endif()
    add_test(NAME pcm_handoff_tests
        COMMAND pcm_handoff_tests $<TARGET_FILE:live_mixer_engine>)

    if(APPLE)
        add_executable(device_catalog_contract_tests tests/device_catalog_contract_tests.cpp)
        target_include_directories(device_catalog_contract_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
        add_dependencies(device_catalog_contract_tests live_mixer_engine)
        add_test(NAME device_catalog_contract_tests
            COMMAND device_catalog_contract_tests $<TARGET_FILE:live_mixer_engine>)

        add_executable(audio_permission_contract_tests tests/audio_permission_contract_tests.cpp)
        target_include_directories(audio_permission_contract_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
        add_dependencies(audio_permission_contract_tests live_mixer_engine)
        add_test(NAME audio_permission_contract_tests
            COMMAND audio_permission_contract_tests $<TARGET_FILE:live_mixer_engine>)

        add_executable(capture_state_tests tests/capture_state_tests.cpp)
        target_include_directories(capture_state_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
        add_dependencies(capture_state_tests live_mixer_engine)
        add_test(NAME capture_state_tests
            COMMAND capture_state_tests $<TARGET_FILE:live_mixer_engine>)

        add_executable(capture_conversion_tests tests/capture_conversion_tests.cpp)
        target_include_directories(capture_conversion_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
        add_dependencies(capture_conversion_tests live_mixer_engine)
        add_test(NAME capture_conversion_tests
            COMMAND capture_conversion_tests $<TARGET_FILE:live_mixer_engine>)

        add_executable(capture_handoff_integration_tests tests/capture_handoff_integration_tests.cpp)
        target_include_directories(capture_handoff_integration_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
        add_dependencies(capture_handoff_integration_tests live_mixer_engine)
        add_test(NAME capture_handoff_integration_tests
            COMMAND capture_handoff_integration_tests $<TARGET_FILE:live_mixer_engine>)

        add_executable(realtime_atomic_contract_tests tests/realtime_atomic_contract_tests.cpp)
        add_test(NAME realtime_atomic_contract_tests COMMAND realtime_atomic_contract_tests)
    endif()
endif()
