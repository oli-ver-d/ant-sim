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

The scenario plays exactly as it will be recorded (camera script and speed schedule).
Keys: **Space** pause, **P** pheromone overlay, **D** debug overlay (ant states, sensors,
channel values under the cursor), **S** TikTok/Reels safe zones, **F** follow the ant under
the cursor (again to stop), **C** back to the scenario camera, **1–5** speed (1/2/4/8/16× the
scenario's pace), mouse wheel zoom, middle-drag pan, **Esc** quit.

`--at=12.5` fast-forwards to a video time, e.g. to check a camera move:
`godot --path . -- --scenario=chaos_to_highway --at=12.5`

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
  behaviours/         explore, follow_trail, go_to_food, carry_home, deliver, linger
  food/ items/ nests/ FoodSource + FoodPile, Item + Debris, NestType + BasicNest
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
- **Castes** can override the species' state params per state (`CasteDef.state_params`),
  so e.g. soldiers return to patrolling instead of foraging.
- **Riding**: ants can ride on carried items (`Simulation.mount()`); the core keeps riders
  on their item and makes them get off when it is dropped or delivered.
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
`two_species` (a leafcutter and a harvester colony foraging side by side), `trunk_trail`
(debris falls on an established trail; majors clear it, minims ride fragments).

JSON files in `scenarios/`. Simulation content:
- `seed`
- `colonies`: species, nest position, population per caste, optional `release_per_second`
  (ants emerge gradually instead of all at once), optional `nest_params`
- `food`: type + type-specific params
- `obstacles`: polyline walls, rects, circles, polygons; `"kind": "water"` for water
- `debris`: twigs and pebbles on the ground (`{"type": "twig", "pos": [x, y]}`); ants crossing
  debris are slowed (`clutter_slowdown`) until something moves it
- `events`: timed (simulated seconds): `spawn_food`, `add_obstacle`, `remove_obstacle`,
  `add_colony`, `rain`, `drop_debris` (with `"scatter": {"on_channel": "c0.food", ...}` debris
  lands on the strongest spots of a trail, wherever it emerged); see `sim/scenario_events.gd`

Playback (video) settings:
- `duration`: video length in seconds
- `warmup`: simulated seconds to run before the first frame
- `ticks_per_frame`: a number, or `[{"t": video s, "tpf": n}, ...]` ramped linearly.
  0.5 = real time (30 ticks/s at 60 fps); 5 = 10× timelapse
- `camera`: keyframes `{"t", "pos": [x, y], "zoom", "ease"}`; `"follow": {"near": [x, y],
  "state": "carry_home"}` in place of `pos` tracks the nearest matching ant
  (see `render/camera_director.gd`)
- `render`: `{"pheromones": true, "pheromone_opacity": 0.55}`

## Recording

```bash
tools/record.sh chaos_to_highway            # scenario seed and duration
tools/record.sh chaos_to_highway 7 15       # seed 7, 15 seconds
FORMAT=avi tools/record.sh chaos_to_highway # fast draft (MJPEG capture)
```

| `FORMAT` | Capture | 20 s video takes | Notes |
|---|---|---|---|
| `png` (default) | lossless PNG frames | ~13 min | best quality, for final uploads |
| `avi` | MJPEG, `MJPEG_QUALITY=1.0` | ~2 min | very slightly softer (SSIM 0.989 vs PNG), ~70% larger MP4 |

Writes `renders/<scenario>_seed<N>_<timestamp>.mp4` (1080×1920, 60 fps, H.264 yuv420p,
CRF 18, no audio). How it works:
1. `scenes/record.tscn` runs under Godot's Movie Maker (`--write-movie`, `--fixed-fps 60`),
   so every frame advances exactly 1/60 s of video however slow the simulation is.
   The output is perfectly smooth and the same seed gives the same video.
2. Movie Maker records at the window size chosen at startup, so `record.sh` writes a
   temporary `override.cfg` (1080×1920 window) and deletes it afterwards. Godot renders
   the full frame even when the screen is smaller.
3. The capture (PNG frames or `capture.avi`) goes to `renders/capture_<name>/`;
   `tools/encode.sh` turns it into the MP4 and deletes it (`KEEP_FRAMES=1` keeps it).
   MJPEG is full-range colour, so `encode.sh` converts it to standard TV range; without
   that the MP4 is tagged `yuvj420p` and some players shift the colours.

With PNG most of the time goes into Godot writing the 1080×1920 PNGs (~0.7 s each).

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
- Castes (via `CasteDef.state_params` overrides):
  - **minims** start in `assign_role`: `hitchhiker_fraction` of them go out (`explore` ->
    `seek_ride`) and climb onto fragments leaving the leaf (`hitchhike`, using the core's
    generic riding); the rest `linger` near the nest.
  - **medias** cut and carry.
  - **majors** `patrol_trail`: walk the foraging trail, and when debris sits on strong trail
    (`debris_trail_threshold`) `clear_debris` carries it off toward weaker trail.

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
