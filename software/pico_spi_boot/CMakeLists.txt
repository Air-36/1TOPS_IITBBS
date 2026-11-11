cmake_minimum_required(VERSION 3.13)

# Pull in pico-sdk (requires PICO_SDK_PATH environment variable or pico_sdk_import.cmake)
include(pico_sdk_import.cmake)

project(pico_spi_boot C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

add_executable(pico_spi_boot
    main.c
)

target_link_libraries(pico_spi_boot
    pico_stdlib
    hardware_spi
    hardware_dma
)

# Enable USB CDC serial output, disable UART serial output
pico_enable_stdio_usb(pico_spi_boot 1)
pico_enable_stdio_uart(pico_spi_boot 0)

# Generate .uf2, .bin, .hex, and .map files
pico_add_extra_outputs(pico_spi_boot)