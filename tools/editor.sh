#!/usr/bin/env bash
# Opens the scenario editor (scenes/editor.tscn).
#   tools/editor.sh                                   # the last file opened (else a new scenario)
#   tools/editor.sh --new                             # a new, unsaved scenario
#   tools/editor.sh --scenario=basic_forage           # a scenario by name or .json path
#   tools/editor.sh --scenario=meadow_forage --screenshot=out.png [--select=colonies/0]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --path . res://scenes/editor.tscn -- "$@"
