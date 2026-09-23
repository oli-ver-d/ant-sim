#!/usr/bin/env bash
# Runs the headless test suite.
#   tools/test.sh               run everything
#   tools/test.sh determinism   run only tests whose "file::method" contains the filter
# Set GODOT to override the Godot executable (default: godot on PATH).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

# Scripts run with -s don't trigger a filesystem scan, so refresh the import
# cache (which holds the class_name table) first. Output is only shown on failure.
if ! import_log=$("$GODOT" --headless --path . --import 2>&1); then
	echo "$import_log"
	echo "Godot import failed" >&2
	exit 1
fi

"$GODOT" --headless --path . -s res://tests/run_tests.gd -- "$@"
