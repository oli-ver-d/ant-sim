cmake_minimum_required(VERSION 3.17)
project(ant_native LANGUAGES CXX)

# godot-cpp (submodule). Built for release templates: no editor-only code.
set(GODOTCPP_TARGET "template_release" CACHE STRING "")
add_subdirectory(godot-cpp)

add_library(ant_native SHARED)
target_sources(ant_native PRIVATE src/register_types.cpp src/ant_kernel.cpp)
target_link_libraries(ant_native PRIVATE godot-cpp)
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set_target_properties(ant_native PROPERTIES
	CXX_STANDARD 17
	CXX_EXTENSIONS OFF
	POSITION_INDEPENDENT_CODE ON
	LINK_SEARCH_START_STATIC ON
	LINK_SEARCH_END_STATIC ON
	PREFIX ""
	OUTPUT_NAME "ant_native${GODOTCPP_SUFFIX}"
	LIBRARY_OUTPUT_DIRECTORY "$<1:${CMAKE_CURRENT_SOURCE_DIR}/bin>"
	RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_CURRENT_SOURCE_DIR}/bin>")
if(MINGW)
	# No libstdc++/libgcc DLLs to ship next to the extension.
	target_link_options(ant_native PRIVATE -static -static-libgcc -static-libstdc++)
endif()
