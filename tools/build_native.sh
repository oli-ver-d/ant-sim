#!/usr/bin/env bash
# Builds the native ant kernel (GDExtension, native/) and registers it with
# the project. Without it the simulation runs entirely in GDScript.
#   tools/build_native.sh          release build (what the game loads)
#   tools/build_native.sh clean    delete the build and the extension
# Needs git (for the godot-cpp submodule), CMake, Ninja, Python 3 and a C++17
# compiler (on Windows MinGW-w64 GCC, the toolchain Godot's own Windows
# builds use, so the maths matches GDScript's bit for bit).
# Set GODOT to override the Godot executable (default: godot on PATH).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

if [[ "${1:-}" == "clean" ]]; then
	rm -rf native/build native/bin
	"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
	echo "Removed the native build."
	exit 0
fi

if [[ ! -f native/godot-cpp/CMakeLists.txt ]]; then
	git submodule update --init native/godot-cpp
fi

generator=()
if command -v ninja >/dev/null 2>&1; then
	generator=(-G Ninja)
fi
cmake -S native -B native/build "${generator[@]}" -DCMAKE_BUILD_TYPE=Release
cmake --build native/build --parallel

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) platform=windows; ext=dll ;;
	Darwin*) platform=macos; ext=dylib ;;
	*) platform=linux; ext=so ;;
esac
lib=$(cd native/bin && ls ant_native.${platform}.template_release.*.${ext} | head -n 1)
arch=${lib#ant_native.${platform}.template_release.}
arch=${arch%.${ext}}
cat > native/bin/ant_native.gdextension <<EOF
[configuration]
entry_symbol = "ant_native_init"
compatibility_minimum = "4.5"
reloadable = false

[libraries]
${platform}.${arch} = "res://native/bin/${lib}"
EOF

# Register the extension (.godot/extension_list.cfg) for headless runs.
"$GODOT" --headless --path . --import >/dev/null 2>&1
echo "Built native/bin/${lib}"
