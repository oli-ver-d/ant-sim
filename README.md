# Ant Colony Simulator

A 2D top-down ant colony simulator in Godot 4, built to produce smooth vertical
videos (1080×1920) for TikTok and Instagram Reels. Behaviour emerges from simple
agent rules (pheromone trails, foraging, cutting, carrying).

## Requirements

- Godot 4.7 (4.3+ should work) with `godot` on PATH, or set `GODOT=/path/to/godot.exe`.
- ffmpeg on PATH (for encoding recordings).
- Git Bash to run the scripts in `tools/` on Windows.

## Running

Interactive mode (default scenario `basic_forage`):

```bash
godot --path .
godot --path . -- --scenario=basic_forage --seed=42
```

Keys: **Space** pause, **P** pheromone overlay, **1–5** speed (1/2/4/8/16× real time),
mouse wheel zoom, middle-drag pan, **Esc** quit.

## Tools

```bash
tools/test.sh                                   # headless test suite (filter: tools/test.sh pheromones)
tools/screenshot.sh basic_forage 3600 out.png   # run 3600 ticks, save a PNG (opens a window briefly)
godot --headless --path . -s res://tests/bench.gd -- basic_forage 1200 3000   # timing: scenario, ticks, ants
```

Tests are scripts in `tests/` named `test_*.gd` that `extend TestCase` and have
`test_*` methods calling `check()` / `check_eq()`. Some tests exercise error paths
on purpose, so `ERROR:` lines in the output are expected; only PASS/FAIL lines
and the exit code matter.

## Project layout

```
sim/          core engine (no rendering, no species-specific code)
  simulation.gd       fixed-tick loop, seeded RNG, per-ant packed arrays
  sim_config.gd       global tunables (defaults; overrides in default_config.tres)
  species_def.gd, caste_def.gd, pheromone_channel_def.gd   species data Resources
  colony.gd           a SpeciesDef instance: nest, stats, namespaced channels, cached params
  registry.gd         string id -> behaviours, food/item/nest types, species, renderers
  core_module.gd      registers the generic pieces below
  pheromone_field.gd  named channels, lazy evaporation, banded diffusion
  steering.gd         three-sensor model, obstacle avoidance, movement
  world.gd            obstacle grid (walls, water)
  scenario_loader.gd  JSON scenario -> Simulation
  behaviours/         explore, follow_trail, go_to_food, carry_home, deliver
  food/ items/ nests/ FoodSource + FoodPile, Item, NestType + BasicNest
species/<name>/       one folder per species; register.gd is discovered automatically
render/               WorldView and renderers; they only read simulation state
scenarios/            JSON scenarios
scenes/               main.tscn (interactive)
tools/ tests/
```

### How the simulation works

- **Ants are array slots**, not nodes: `Simulation` holds `pos`, `heading`, `state`, `carried`, ...
  as packed arrays. Removed ants' slots are reused.
- **Behaviour states** (`sim/behaviours/`) are shared objects with `enter/tick/exit`;
  `tick` returns the next state id. Per-species wiring (which channel to follow or lay,
  which state comes next) lives in `SpeciesDef.state_params`, e.g.
  `"carry_home": {"follow_channel": "home", "lay_channel": "food", "on_arrive": "deliver"}`.
- **Pheromones**: each colony gets its own copy of its species' channels (`c0.home`, `c0.food`).
  A deposit sets a cell to `max(cell, amount) + reinforce * amount`, and `amount`
  halves every `deposit_half_life` seconds since the ant last touched its source (nest or
  food). That makes each trail a clean gradient pointing back to its source, while busy
  trails still grow stronger.
- **Determinism**: all randomness uses `sim.rng`; `Simulation.state_hash()` fingerprints a run.

### Core vs species

`/sim` and `/render` must contain no species-specific code. `tests/test_core_generic.gd`
fails if they mention "leaf", "fungus", "cutter", "harvester" or the name of any
folder under `/species`.

Species modules plug in through `species/<name>/register.gd`:

```gdscript
extends RefCounted

func register(registry: Registry) -> void:
	registry.register_species("my_species", preload("my_species.tres"))
	registry.register_behaviour("my_state", MyState.new())
	registry.register_food_source_type("my_food", MyFood)
	registry.register_renderer("food:my_food", MyFoodRenderer)
```

### Scenarios

JSON files in `scenarios/`: seed, colonies (species, nest position, population per
caste), food sources (type + type-specific params) and obstacles (polyline walls,
rects, circles, polygons; `"kind": "water"` for water). See `sim/scenario_loader.gd`.

## Recording

_Coming in M5._

## How to add a new species

_Written in M9, from the experience of adding harvesters._
