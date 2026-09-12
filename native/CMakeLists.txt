cmake_minimum_required(VERSION 3.20)
project(live_mixer_engine VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(live_mixer_engine SHARED
    live_mixer_engine.cpp
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
    add_executable(native_gain_control_contract_tests
        tests/native_gain_control_contract_tests.cpp
    )
    add_dependencies(native_gain_control_contract_tests live_mixer_engine)
    if(UNIX)
        target_link_libraries(native_gain_control_contract_tests PRIVATE ${CMAKE_DL_LIBS})
    endif()
    add_test(
        NAME native_gain_control_contract_tests
        COMMAND native_gain_control_contract_tests $<TARGET_FILE:live_mixer_engine>
    )
endif()
