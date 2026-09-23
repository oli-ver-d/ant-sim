# Ant Colony Simulator

A 2D top-down ant colony simulator in Godot 4, built to produce smooth vertical
videos (1080×1920) for TikTok and Instagram Reels. Behaviour emerges from simple
agent rules (pheromone trails, foraging, cutting, carrying).

## Requirements

- Godot 4.7 (4.3+ should work) with `godot` on PATH, or set `GODOT=/path/to/godot.exe`.
- ffmpeg on PATH (for encoding recordings).
- Git Bash to run the scripts in `tools/` on Windows.

## Running

Interactive mode: open the project in the Godot editor and press F5, or run:

```bash
godot --path .
```

## Tests

```bash
tools/test.sh
```

Runs every `tests/test_*.gd` headlessly and exits non-zero on failure. Pass a
filter to run a subset, e.g. `tools/test.sh registry`. A test is a script that
`extends TestCase` with methods named `test_*` that call `check()` / `check_eq()`.

Some tests exercise error paths on purpose, so `ERROR:` lines in the output are
expected. Only the PASS/FAIL lines and the exit code matter.

## Project layout

```
sim/          core engine: simulation loop, config, registry, pheromones, steering, world
  behaviours/ generic behaviour states (Behaviour base class)
  food/       FoodSource base + generic food types
  items/      Item base
  nests/      NestType base
species/      one folder per species; each has a register.gd the core discovers
render/       renderers and shaders (read simulation state, never modify it)
scenarios/    JSON scenario definitions
scenes/       main.tscn (interactive), record.tscn (recording)
tools/        test.sh, record.sh, encode.sh
tests/        headless test runner and tests
```

### Core vs species

`/sim` and `/render` must contain no species-specific code. `tests/test_core_generic.gd`
fails if they mention "leaf", "fungus", "cutter", "harvester" or the name of any
folder under `/species`.

Species modules plug in through `species/<name>/register.gd`:

```gdscript
extends RefCounted

func register(registry: Registry) -> void:
	registry.register_behaviour("my_state", MyState.new())
	registry.register_food_source_type("my_food", preload("my_food.gd"))
	# ...
```

`Registry.discover_modules()` loads these in folder-name order.

### Tunables

Global parameters live in `sim/sim_config.gd` (defaults), with overrides saved
in `sim/default_config.tres`. Species-specific values live in the species'
SpeciesDef and are merged over the global config via `SimConfig.get_param()`.

## Recording

_Coming in M5._

## How to add a new species

_Written in M9, from the experience of adding harvesters._
