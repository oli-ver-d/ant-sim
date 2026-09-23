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

Keys: **Space** pause, **P** pheromone overlay, **D** debug overlay (ant states, sensors,
channel values under the cursor), **S** TikTok/Reels safe zones, **1–5** speed (1/2/4/8/16× real time),
mouse wheel zoom, middle-drag pan, **Esc** quit.

## Tools

```bash
tools/test.sh                                   # headless test suite (filter: tools/test.sh pheromones)
tools/screenshot.sh basic_forage 3600 out.png   # run 3600 ticks (2 min at 30 ticks/s), save a PNG
tools/screenshot.sh chaos_to_highway 3600 out.png -1 --zoom=3.5 --center=600,740   # close-up
tools/screenshot.sh two_species 2400 out.png -1 --safe=1 --debug=1 --pheromones=0    # overlays
godot --headless --path . -s res://tests/bench.gd -- basic_forage 600 3000   # sim timing: scenario, ticks, ants, [seed]
godot --path . -- --probe=1 --ants=3000        # in-app FPS with 3000 ants
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
- **Ticks and frames**: the sim runs at 30 ticks/s (`SimConfig.tick_rate`). `SimRunner` spreads
  each tick's ant updates over the frames it spans (identical result to `step()`), and
  renderers interpolate between the last two completed ticks (`prev_pos` -> `shown_pos`).

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

Included: `basic_forage` (core test bed with food piles), `chaos_to_highway` (one leaf,
trail self-organises), `leaf_strip` (one giant leaf stripped completely, for timelapse),
`two_species` (a leafcutter and a harvester colony foraging side by side).

JSON files in `scenarios/`: seed, colonies (species, nest position, population per
caste), food sources (type + type-specific params) and obstacles (polyline walls,
rects, circles, polygons; `"kind": "water"` for water). See `sim/scenario_loader.gd`.

## Recording

_Coming in M5._

## How to add a new species

_Written in M9, from the experience of adding harvesters._

## Species: leafcutter ants

`species/leafcutter/`:
- `leafcutter.tres`: castes (minim, media, major), channels, state wiring and tunables
  (`bite_radius`, `cut_time` per caste).
- `leaf_source.gd`: procedural leaf (elliptic/lanceolate outline, serrations, veins) stored
  as a 3 px cell mask. Each bite removes a semicircle at the edge nearest the cutter,
  sized by the caste's `carry_capacity`, and the removed cells become the carried
  fragment, so the fragment matches the hole.
- `leaf.gdshader` + `leaf_renderer.gd`: draw the mask smoothly (linear filtering + threshold)
  with procedural veins; only the small mask texture is re-uploaded per bite.
- `cut_leaf.gd`: stand at the edge sawing for the caste's cut time, then bite and carry home.

## Species: harvester ants

`species/harvester/`, added without touching the core or the leafcutter module:
- `harvester.tres`: minors (near-black) and big-headed majors (dark red); violet/teal
  trails; uses only the core's generic behaviours.
- `seed_pile.gd` + renderer: a cluster of individual seeds; foragers walk to the nearest
  one, so the pile thins out seed by seed.
- `seed_nest.gd` + renderer: a `BasicNest` that counts seeds; drawn as a cleared sandy
  disc with a growing pile of husks.

## Visual style

All drawing lives in `render/` (plus each species' own renderers):
- `ground.gdshader`: static soil (large patches, clods, grain, round specks, shaded pebbles).
  Static so it compresses well in video.
- `ant.gdshader`: one shader for every ant: lit, glossy three-segment body, bilobed head for
  big-headed castes, mandibles, antennae, six legs in a tripod gait, soft drop shadow in
  a fixed world-space light direction (`light_dir`, shared with the ground and obstacles).
  Everything comes from `CasteDef` (size, colour, head/thorax/abdomen scale, mandible size,
  leg length); see the packing notes at the top of the shader.
- `pheromone.gdshader`: additive glow (core + halo) per channel, coloured by the channel's
  `color` and scaled by its `render_intensity`.
- `obstacle.gdshader`: smooth stone walls with rim light and shadow; water with a damp bank.
- `overlays.gd`: safe zones and the debug view.

Shaders use a sine-free hash: `sin()`-based hashes show seams on some GPUs.
