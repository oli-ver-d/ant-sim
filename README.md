# Ant Colony Simulator

A 2D top-down ant colony simulator in Godot 4, built to produce smooth vertical
videos (1080×1920) for TikTok and Instagram Reels. Behaviour emerges from simple
agent rules (pheromone trails, foraging, cutting, carrying).

## Requirements

- Godot 4.7 (4.3+ should work) with `godot` on PATH, or set `GODOT=/path/to/godot.exe`.
- ffmpeg on PATH (for encoding recordings).
- Git Bash to run the scripts in `tools/` on Windows.
- Optional, for the native ant kernel (several times faster, same results; see "Native ant
  kernel" below): CMake, Ninja, Python 3 and a C++17 compiler, then `tools/build_native.sh`
  (it fetches the `native/godot-cpp` submodule if needed). On Windows use MinGW-w64 GCC,
  which Godot's own Windows builds use: `winget install BrechtSanders.WinLibs.POSIX.MSVCRT`
  (includes CMake and Ninja) and `winget install Python.Python.3.13`.

## Running

Interactive mode (default scenario `basic_forage`):

```bash
godot --path .
godot --path . -- --scenario=basic_forage --seed=42
```

The scenario plays exactly as it will be recorded (camera script and speed schedule).
Keys: **Space** pause, **P** pheromone overlay, **D** debug overlay (ant states, sensors, traffic heat,
channel values under the cursor), **S** TikTok/Reels safe zones,
**L** layout: cycles surface / split (surface on top, the nest underground below) / nest
(the underground full screen); only for nests that dig their own, see `render.layout`,
**T** tuning panel, **F** follow the ant under the cursor (again to stop), **C** back to the
scenario camera, **1–5** speed (1/2/4/8/16× the scenario's pace), **Esc** quit.

Mouse: **left-drag** draws a wall (**Shift**+left-drag erases; ants under a new wall are
moved out), **right-click** places food of the type selected in the tuning panel, wheel zooms,
middle-drag pans. The HUD shows FPS and, per colony, ants, items delivered and deliveries
in the last minute.

The tuning panel (**T**, never shown in recordings) has a colony selector (which species to
tune and whose food right-click places), live sliders for every `SimConfig` value that can
change while running and for the selected species' numeric tunables and pheromone channels,
**Save** (writes `sim/default_config.tres` and the species' `.tres`) and **Reset**.
Scenario per-colony overrides still take precedence over the sliders.

`--at=12.5` fast-forwards to a video time, e.g. to check a camera move:
`godot --path . -- --scenario=chaos_to_highway --at=12.5`

`--layout=split` (or `normal`, or `nest`) overrides the scenario's layout:
`godot --path . -- --scenario=colony_founding --layout=nest`. In the split layout the mouse
(walls, food, zoom, **F**, the debug readout) works on the surface part. The HUD counts every
ant of a colony, including its abstract population (see "Scale" below).

## Tools

```bash
tools/build_native.sh                           # build the native ant kernel (tools/build_native.sh clean removes it)
tools/test.sh                                   # headless test suite (filter: tools/test.sh pheromones)
tools/screenshot.sh basic_forage 3600 out.png   # run 3600 ticks (2 min at 30 ticks/s), save a PNG
tools/screenshot.sh chaos_to_highway 3600 out.png -1 --zoom=3.5 --center=600,740   # close-up
tools/screenshot.sh two_species 2400 out.png -1 --safe=1 --debug=1 --pheromones=0    # overlays
tools/screenshot.sh colony_founding 0 out.png -1 --layout=split --at=3    # split layout, 3 s in
godot --headless --path . -s res://tests/bench.gd -- basic_forage 600 3000   # sim timing: scenario, ticks, ants, [seed]
godot --headless --path . -s res://tests/bench.gd -- res://tests/fixtures/scenarios/nest_bench.json 900   # per layer
godot --path . -- --probe=1 --ants=3000        # in-app FPS with 3000 ants
godot --headless --path . -s res://tests/bench.gd -- basic_forage 600 3000 -1 --no-native   # GDScript ants only
godot --headless --path . -s res://tests/nest_probe.gd -- colony_founding 7200 300    # a nest's growth: chambers, highways, entrances, ms/tick
godot --headless --path . -s res://tests/nest_probe.gd -- colony_founding 7200 300 2  # the same with 2-unit underground cells
tools/stills.sh colony_founding 12,35,72 renders/stills   # full-res stills: layout, whole nest, close-up of the digging face
tools/test.sh --long test_colony_founding_grows            # the whole colony_founding run as a test (~30 min)
tools/test.sh --long test_harvester_founding_grows         # the whole harvester_founding run as a test
godot --headless --path . -s res://tests/fingerprint_probe.gd -- colony_founding 9000   # a run's fingerprint by state names (refactors)
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
  steering.gd         three-sensor model, obstacle avoidance, movement (and move_to for tunnels)
  world.gd            obstacle grid (walls, water, diggable soil with clay, roots, stones)
  layer.gd            SimLayer: one layer's World, PheromoneField, NavGrid, traffic, lanes
  portal.gd           a way between two layers (a nest entrance and its shaft)
  nav_grid.gd         distance fields over free cells toward named targets
  travel.gd           getting to a point on any layer (portals, nav fields, lanes)
  router.gd           A* routes for new tunnels through soil (SimLayer.route)
  traffic_map.gd      decaying per-cell count of the ants passing
  scenario_loader.gd  JSON scenario -> Simulation
  behaviours/         explore, follow_trail, go_to_food, carry_home, deliver, linger, carry_waste,
                      dig, carry_spoil, go_up; for nests with a queen: queen, nest_role, nurse,
                      tend_queen, carry_spent
  food/ items/ nests/ FoodSource + FoodPile, Item + Debris, NestType + BasicNest,
                      ColonyNest (a queen, brood, roles, chambers: base for species nests),
                      Brood + BroodCare (egg to worker, nursing), NestChambers (chambers and
                      galleries), ExcavationPlan (digging jobs), DigShape (job shapes),
                      Highways (widening busy tunnels)
  native_ants.gd      drives the native ant kernel (optional; see "Native ant kernel")
native/       the native ant kernel (GDExtension, C++): src/ant_kernel.cpp, godot-cpp submodule
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
- **Nests** (`NestType`): receive delivered items, grow the colony in `update()`, and may
  produce waste that `carry_waste` workers take to `dump_position()`. A nest type can have a
  surface renderer (`"nest:<type>"`), and a nest that digs its own underground layer
  renderers for it (`"underground:<type>"`, `"underground_top:<type>"`).
- **Colony nests** (`ColonyNest`, a `NestType`): what nests with a queen share, so a species
  nest adds only what its colony lives on. The queen, brood that develops egg to worker and
  needs nurses (`Brood`, `BroodCare`), nest roles, chambers and galleries dug as the nest runs
  short of room (`NestChambers`), founding sealed in, more entrances as the colony grows. The
  species nest provides the food store (`food_stock()`, `food_point()`, `take_food_at()`,
  `make_brood_food()`...), `space_pressure()` and any roles of its own. `FungusNest`
  (leafcutter gardens) and `GranaryNest` (harvester granaries) are both built on it.
- **Riding**: ants can ride on carried items (`Simulation.mount()`); the core keeps riders
  on their item and makes them get off when it is dropped or delivered.
- **Obstacles**: ants probe ahead and to both sides near obstacles and turn away; with walls on
  both sides but a clear way ahead (a bridge, a gap) they keep going. Homing ants combine the
  home trail with path integration (a sense of where the nest is), but for
  `obstacle_memory` seconds after steering around an obstacle they trust the trail alone, so
  they can follow a detour (along a bank to a bridge, sideways to a gap in a wall).
- **Exploring**: with `avoid_channel` (e.g. their own home trail) explorers that have nothing
  to follow steer toward the least-walked side, so the search keeps pushing into new ground.
- **Determinism**: all randomness uses `sim.rng`; `Simulation.state_hash()` fingerprints a run.
  States are hashed by their rank among the states the sim's colonies can use, so registering
  a new behaviour doesn't change the hashes of existing runs; runs with one layer hash exactly
  as they did before layers existed (`tests/test_layers.gd` checks every scenario).
- **Ticks and frames**: the sim runs at 30 ticks/s (`SimConfig.tick_rate`). `SimRunner` spreads
  each tick's ant updates over the frames it spans (identical result to `step()`), and
  renderers interpolate between the last two completed ticks (`prev_pos` -> `shown_pos`).


### Layers, portals and digging

- **Layers** (`SimLayer`): layer 0 is the surface (`sim.world`, `sim.pheromones`); a nest may add
  its own underground (`nest_params.underground`, see below). Each layer has its own `World`,
  `PheromoneField` (the same channels at the same indices), size and cell size. Every ant is on
  one layer (`sim.layer[i]`) and moves, senses and lays pheromone there, in that layer's
  coordinates. Food sources are on the surface.
- **Portals** (`Portal`) link two layers: an ant at one end calls `sim.enter_portal()`, walks into
  the hole for `transit_time` and comes out at the other end; renderers fade it out and in
  (`sim.portal_fade()`). A closed portal (a sealed founding nest, `has_entrance()` false) can't
  be used from either side. `Travel.go()` gets an ant to a point on any layer, through portals.
- **Diggable soil**: `World.Cell.SOIL` cells hold the work left in them and block movement until
  `World.dig()` frees them. Digging only frees cells, so caches follow it incrementally through
  `World.dig_log` (renderers upload just the touched cells, nav fields relax just around them);
  any other change bumps `World.edit_version` and rebuilds.
- **Navigation fields** (`NavGrid`): underground, pheromone trails are unreliable in narrow
  tunnels (the maze lesson), so ants follow distance fields over free cells toward named
  targets (the shaft `portal:<id>`, each chamber, each digging job). `Steering.move_to` follows
  them downhill and slides along walls instead of probing.
- **Digging** (`ExcavationPlan`, `NestType.excavation_plan()`): the nest plans jobs, each a
  shape to dig out from a point in space already open. Diggers (`dig`) take the open job with
  the lowest priority that has room, walk to it and then to its face, and bite (`dig_time`),
  clearing `cells_per_bite` cells of the face; the soil comes out as a pellet they carry up
  (`carry_spoil`) through the nearest entrance to that entrance's spoil heap. While the nest is
  sealed the soil is pressed into the walls instead. A job can open a portal when it is
  finished (an entrance shaft). Work per cell and cells per bite scale with the cell area, so a
  nest digs the same volume at any cell size.
- **Digging stays connected**: a job opens only once a cell around its origin is free *and*
  reachable from the nest (`reach_field`, a nav field from the first carved space); a bite's
  extra cells must share an edge with a cell the bite opened, and nothing is bitten across a
  soil corner, so digging never opens a pocket ants can't walk into. A job that diggers keep
  giving up on without progress (`report_stall`, 4 in a row) is abandoned, so one unreachable
  cell can't hold up the nest; an abandoned job never opens its portal. A job's nav field is
  made when it is first taken.
- **Job shapes** (`DigShape`): a *path* (a polyline with a radius per point: curving, tapering
  tunnels), a *blob* of ellipses (irregular chambers), a polar outline r(θ), or any cell set.
  Each cell has a rank (progress along a path; closeness to where a blob is entered), and
  `add_job()` still plans the old capsule. With `overdig` the outline wanders a little out
  (and a third of that in) with seeded noise, so walls come out rough.
- **Ragged digging**: `bite_cell()` is a weighted random pick (`sim.rng`) among the job's cells
  beside the digger, favouring the highest ranked and softer soil (`ragged` sets how uneven),
  so faces advance unevenly. **Soil texture** (`World.add_soil_texture`, nest param
  `texture`): clay patches and roots take 2–3× the work, stones (`Cell.WALL`) can't be dug:
  jobs leave them (a pillar), routes go around them.
- **Routes** (`SimLayer.route(from, to, params)`, `Router`): A* over the soil's cells, costing
  hardness, closeness to open space and to planned digging (so a new tunnel doesn't break
  into a chamber), and a seeded meander noise, so tunnels wind; smoothed into a path.
- **Traffic** (`TrafficMap`, `SimLayer.traffic`): a decaying count of ant-seconds per cell,
  sampled every 3 ticks (natively when the kernel runs), halving every 60 s; enabled per
  layer by whoever needs it (the nest's highways, on the nest layer and the surface).
- **Highways** (`Highways`, underground param `highways`): tunnels are watched in ~50-unit
  sections; one whose traffic per unit length stays over `threshold` for `sustain` checks is
  widened (a smoothed path job, `grow`× the radius, up to `max_radius`), and one at full width
  still over `bypass`× the threshold gets a routed bypass alongside.
- **Lanes** (`SimLayer.lanes`, from `highways.lanes`): an ant following a nav field in a
  corridor at least 14 units wide (not in chambers) keeps to the right of its way
  (`Travel.lane_aim`), so ants going out and coming back pass in two streams.
- **Several entrances**: `NestType.add_entrance()` adds a closed portal that a job opens;
  `entrances()`, `nearest_entrance()` and `is_at_nest()` cover every open one. Homing ants head
  for the nearest, `Travel.best_portal` picks the portal that makes an ant's way shortest.
- **Castes and params for nests that dig**: `CasteDef.underground_states` are extra states a
  caste may use only when its nest has an underground, and `SpeciesDef.underground_state_params`
  are merged over the state wiring only then, so the same species plays exactly as before in
  scenarios without one.
- **Scale**: `"max_agents": {"surface": n, "nest": n}` caps how many ants a layer simulates one by
  one. Beyond it a colony grows as an **abstract population** (`Colony.abstract_by_caste`): brood
  emerging into a full layer joins it, and every second `Simulation.balance_pools()` moves idle
  agents (the species' `pool_states`) out of layers over their cap, brings abstract ants back
  into layers with room (`NestType.spawn_from_pool`), and swaps a few so the agents stay a
  representative sample of the castes. Abstract ants count in the colony's size, upkeep and
  the HUD; the agents do the work. Renderers draw filler ants in proportion (render-only).

### Native ant kernel (GDExtension)

The per-ant hot path also exists in C++ (`native/`, class `AntKernel`, built by
`tools/build_native.sh`). It is optional: without the built extension (or with `--no-native`
after `--`) everything runs in GDScript, and **either way a run is identical**, state hash for
state hash. `tests/test_native.gd` runs every scenario and test fixture both ways and compares
their hashes.

- **What runs natively**: whole ticks of the core behaviours `explore`, `follow_trail`,
  `carry_home` and `linger`, plus the pieces every other behaviour uses: `Steering.move`,
  `move_to`, `sense_turn`, `sense_away`, `Simulation.lay`, the nav-field step in `Travel` (with
  its clear-line check and lanes), traffic sampling, and a few generic queries
  (`carriers_near`, `NativeAnts.mask_edges`, `NativeAnts.nearest_point`). Nests with several
  entrances send the kernel the open ones.
  Like `/sim`, the kernel knows no species.
- **How ticks are shared**: `Simulation.step_ants` calls `kernel.run(i, end)`, which updates ants
  in index order until it reaches one it can't handle: a state that isn't native, an ant in a
  portal, or a tick that needs GDScript. A tick needs GDScript when the ant changes state, when
  explore's food check might find food (it is inside some source's `FoodSource.sense_bound()`),
  or when it arrives at the nest. That ant runs its GDScript behaviour, then the kernel carries
  on. The order of ants, and of every random number, is exactly the GDScript order.
- **Same maths**: GDScript floats are doubles and `Vector2` is float32; the kernel repeats the
  engine's own code at the same precision for each step (`from_angle` and `angle()` in float,
  `cos`, `wrapf` and `angle_difference` in double...). Random numbers come from the Simulation's
  own `RandomNumberGenerator`. It is built with the compiler family Godot's Windows builds use
  (MinGW-w64 GCC), so the libm functions return the same bits.
- **Shared arrays**: the kernel owns no data. Each tick `NativeAnts.begin_tick()` hands it the
  Simulation's packed arrays (and each layer's grids) and it reads and writes their buffers in
  place. Packed arrays are copy-on-write, so first every array gets a buffer of its own (the
  render snapshots `shown_pos = pos` share one until written). During a tick no code may replace
  or resize those arrays; `end_tick()` checks, and if one moved it reports which and switches
  that Simulation to GDScript.
- **Keeping it in step**: a change to one of the native behaviours or to `Steering` must be made
  in `native/src/ant_kernel.cpp` too; `tests/test_native.gd` fails until both agree. Nest
  entrances (`Portal.open`), food sources added mid-tick and live tuning are sent to the kernel
  as they change.

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
(debris falls on an established trail; majors clear it, minims ride fragments), `rain_reset`
(a downpour washes an established trail away and the colony rebuilds it), `twig_bridge` (a
leaf across a stream; one fallen twig is the only way over), `maze` (a leaf behind rows of
stone walls; explorers find the gaps and a trail settles on one route),
`fungus_farm` (a young colony over ~17 minutes: the garden grows chamber by chamber, the
colony grows from 150 to ~850 ants, waste piles up outside),
`colony_founding` (about 80 s, split view over a nest that digs its own underground: a queen
and four minims sealed in a founding chamber dig a ragged tunnel up to the surface, foraging
begins, and over about two simulated hours the colony grows to thousands: galleries branch,
gardens fill lobed chambers hanging off them, busy tunnels widen into highways with two-way
traffic, and a second and third entrance open, each with its own heap of dug soil),
`harvester_founding` (the same story for harvester ants, about 80 s over ~110 simulated
minutes: a queen, four minors and her cache of seeds sealed in dig up to the surface; foragers
carry seeds down into granaries that fill heap by heap, husks of eaten seeds go out to a
midden, and the nest grows chamber by chamber with more entrances).

JSON files in `scenarios/`. Simulation content:
- `seed`
- `colonies`: species, nest position, population per caste, optional `nest_type` (instead of
  the species' own, e.g. `"granary_nest"`), optional `release_per_second`
  (ants emerge gradually instead of all at once), optional `nest_params`
  and per-colony tweaks: `params` (SimConfig keys and species tunables), `state_params`
  (merged over the species' state wiring) and `channels` (`{"home": {"half_life": 60}}`)
- `food`: type + type-specific params
- `obstacles`: polyline walls, rects, circles, polygons; `"kind": "water"` for water;
  `"kind": "bridge"` on a polyline lays a walkable strip over water or walls, drawn as a twig
- `debris`: twigs and pebbles on the ground (`{"type": "twig", "pos": [x, y]}`); ants crossing
  debris are slowed (`clutter_slowdown`) until something moves it
- `max_agents`: `{"surface": n, "nest": n}` agents per layer, beyond which colonies grow as
  an abstract population (see "Layers, portals and digging")
- `events`: timed (simulated seconds): `spawn_food`, `add_obstacle`, `remove_obstacle`,
  `add_colony`, `rain` (`area` rect or circle, whole world if omitted; `wash_half_life` makes
  trails fade over a moment instead of vanishing), `drop_debris` (with `"scatter": {"on_channel": "c0.food", ...}` debris
  lands on the strongest spots of a trail, wherever it emerged); see `sim/scenario_events.gd`

Playback (video) settings:
- `duration`: video length in seconds
- `warmup`: simulated seconds to run before the first frame
- `ticks_per_frame`: a number, or `[{"t": video s, "tpf": n}, ...]` ramped linearly.
  0.5 = real time (30 ticks/s at 60 fps); 5 = 10× timelapse
- `camera`: keyframes `{"t", "pos": [x, y], "zoom", "ease"}`; `"follow": {"near": [x, y],
  "state": "carry_home"}` in place of `pos` tracks the nearest matching ant;
  `"fit": "excavation"` (with `margin`, `min_zoom`, `max_zoom`) frames everything dug so far,
  easing as the nest grows. For a nest that digs, `"camera": {"surface": [...], "nest": [...]}`
  gives each part of the layout its own keyframes (see `render/camera_director.gd`)
- `render.layout`: `{"mode": "split", "colony": 0, "surface": "top", "ratio": 0.45}` splits
  the frame: the surface (the world, in a 1080×(1920×ratio) SubViewport, so camera keyframes, clamping and follow work against
  that part) and, full width below it, the colony's nest: its underground layer, top-down and
  fully simulated, with its own camera, for a nest that digs (the nest's size and brood are
  shown top left). `"mode": "nest"` shows the underground full screen, and
  `"modes": [{"t": 0, "mode": "nest"}, {"t": 13, "mode": "split"}]` switches mode at video
  times. Nests without an underground layer play full screen. See `render/split_layout.gd`
- `render.pheromones` (default true) and `render.pheromone_opacity` (e.g. 0.55): the pheromone
  overlay

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

## Performance

Measured on this project's dev laptop (Intel UHD integrated GPU, CPU at 2.3 GHz, Godot 4.7
editor build). `--probe=1` prints FPS, sim cost per frame and GPU time every 2 s;
`tests/bench.gd` times the simulation headless.

| Case | Result |
|---|---|
| 3,000 ants, real time, interactive (`--probe=1 --ants=3000`) | 60 fps while exploring; settles around 27 fps once foraging is busy |
| Simulation cost | about 7.5–9 µs per ant per tick (GDScript); 25 ms per tick at 3,000 ants |
| Pheromones (2 channels) | 0.4–1.7 ms per tick (only rows holding pheromone are diffused) |
| GPU | 7–12 ms per frame at 3,000 ants |
| 15,000 ants offline (`bench.gd basic_forage 300 15000`) | 135 ms per tick; recording works at any speed |
| M11, one layer (`bench.gd basic_forage 300 3000`) | 26.4 ms per tick (M10 on the same run: 24.0; the layer checks cost up to ~10%) |
| A nest that digs, ~1,500 ants (`bench.gd res://tests/fixtures/scenarios/nest_bench.json 900`) | 24.9 ms per tick: surface ants 14.4 ms (752 agents, 16.5 µs each), underground ants 7.6 ms (721 agents, 12.8 µs each), nest (gardens, brood, roles) 1.4 ms, pheromones 1.1 ms |
| `colony_founding`, headless | about 2 ms per tick at 100 ants, 10 ms at 650, 16 ms at 1,000, 22–26 ms at the 1,600 agent cap (the rest abstract) |
| `FORMAT=avi tools/record.sh colony_founding` | 79 min for the 80 s video (4,800 frames, ~7,200 simulated seconds, ~215,000 ticks; most of it the last 50 s at 70–80 ticks per frame with 1,600 agents); ends at ~3,500 ants. With the native kernel and M13: 49 min (47 min capture, 2 min encode), ends at ~3,800 ants |
| **Native ant kernel** (M12, same machine) | |
| 3,000 ants, real time, interactive, busy foraging | 60 fps; the simulation takes ~2.5 ms per frame (GDScript: ~27 fps) |
| `bench.gd basic_forage 600 3000` | 2.5 ms per tick (GDScript: 24.0) |
| `bench.gd basic_forage 300 15000` | 12.8 ms per tick (GDScript: 135) |
| nest that digs, ~1,500 ants (`nest_bench.json 900`) | 9.1 ms per tick: surface 2.2 ms (2.5 µs per ant), underground 3.7 ms (6.2 µs per ant) (GDScript: 20.9) |
| `colony_founding` headless, whole run (216,000 ticks) | 30 min; 13–15 ms per tick at the 1,600 agent cap (GDScript: 22–26), ends at the same 3,529 ants |

| **Organic nests** (M13, same machine; both runs side by side so they share the load) | |
| `colony_founding` headless, whole run (`nest_probe.gd`) | 13.66 ms per tick (M12: 13.42, +2%); ends at 3,857 ants (M12: 3,529); 76 MB (M12: 70) |
| the same, late stage (1,500–3,800 ants) | 18–25 ms per tick (M12 at the same sizes: 18–24); underground ants about 15% dearer per ant (walls to slide along, lanes, portal choice) |
| the same, 2-unit underground cells | 11.26 ms per tick over the run against 9.63 at 4 in a paired run, while growing slower (3,682 against 4,057 ants); 135 MB against 81. Over the 15% budget, so cells stay 4 units and the finer look comes from the shader's edge noise |

- At 30 ticks/s and 60 fps each frame runs half a tick, so 3,000 ants need about 12.5 ms of
  every 16.7 ms frame for the simulation alone. That fits while ants explore, but busy
  foraging (more states, carried items to draw) tips it over. The ant logic is the limit, not
  pheromones or rendering. With the native ant kernel (M12) 3,000 ants run at a steady 60 fps.
- If a frame runs long, the interactive app advances at most 1/30 s per frame, so a heavy
  scene runs slower rather than spiralling into ever longer frames. Recordings always advance
  exactly 1/60 s per frame and are unaffected.
- Recording is offline, so timelapses and large colonies are fine; they only take longer to
  record.
- With the kernel, what is left is behaviours that are still GDScript: species states
  (leafcutter gardening, nursing, cutting, carrying down) cost 5–12 µs per ant per tick, the core
  ones well under 1 µs. In `colony_founding` most agents underground are in species states, so
  it gains less (about 1.7×) than scenarios of core behaviours (up to 10×).
- Underground ants cost less than busy surface ants (no pheromone sensing; they follow nav
  fields) but share the same GDScript limit. The agent caps (`max_agents`) bound the cost of a
  big colony: beyond them the colony grows as an abstract population. The garden grid updates a
  slice of cells per tick, and nav fields and the soil texture follow digging cell by cell, so
  a sprawling nest adds little per tick.

## How to add a new species

Harvester ants (`species/harvester/`) were added this way in M3, as a test of the design:
six new files (plus a scenario and a test) and **no changes to `/sim`, `/render` or the
leafcutter module**. What it took, in order:

### 1. Make the folder and the species data

Create `species/<name>/` with a `SpeciesDef` resource (`<name>.tres`). Copying
`harvester.tres` is the quickest start: it's the minimal complete species. It holds:

- **castes** (`CasteDef`): size, speed, turn rate, colour, body proportions (head /
  thorax / abdomen scale, mandibles, leg length; the shared ant shader draws them),
  `spawn_ratio`, `carry_capacity`, the list of behaviour `states` the caste may use and its
  `initial_state`. Optional per-caste `state_params` override the species' wiring for that
  caste (leafcutter majors use this to go back to patrolling instead of foraging).
- **channels** (`PheromoneChannelDef`): name, half-life, diffusion, cap, reinforce, overlay
  colour. Each colony gets its own copy (`c0.home`, `c1.home`), so species never read each
  other's trails unless a behaviour does so on purpose.
- **state_params**: the wiring. For each state, which channel to follow and lay and which
  state comes next, e.g. `"carry_home": {"follow_channel": "home", "lay_channel": "food",
  "on_arrive": "deliver"}`. Keys ending in `_channel` are channel names and get resolved to
  field indices for you. The core behaviours document their params at the top of each file in
  `sim/behaviours/`.
- **nest_type / nest_params**, **food_source_types**, **item_types**, and **tunables**
  (species-only values, plus overrides of any `SimConfig` value).

Harvesters needed no new behaviours at all: `explore`, `follow_trail`, `go_to_food`,
`carry_home` and `deliver` wired with harvester channels are enough for a foraging species.
Start there, then add behaviours only for what's really new.

### 2. Add what's new, as small classes

Only what the species really has that the core doesn't:

| Piece | Base class | Harvester example | Leafcutter example |
|---|---|---|---|
| Behaviour state | `Behaviour` (`tick()` returns the next state id or `""`) | none | `cut_leaf`, `hitchhike`, `patrol_trail` |
| Food source | `FoodSource` (`take()`, `nearest_access_point()`, `is_sensed_at()`, ...) | `seed_pile.gd` | `leaf_source.gd` |
| Nest | `NestType` or `BasicNest` (`receive_item()`, `update()`, optional waste); `ColonyNest` for a queen, brood and a dug nest | `seed_nest.gd`, `granary_nest.gd` | `fungus_nest.gd` |
| Renderer | any `Node2D` with `bind(sim, target)` | `seed_pile_renderer.gd`, `seed_nest_renderer.gd` | `leaf_renderer.gd`, `fungus_nest_renderer.gd` |
| Underground renderer | a `Node2D` with `bind(sim, nest)` on the nest's layer view | none | `fungus_underground.gd` |

Behaviours work on ant indices and the `Simulation` arrays (`sim.pos[i]`, `sim.heading[i]`,
...), never on per-ant nodes. Use `Steering.move()` to move (it handles wandering, obstacle
avoidance and walls) and `sim.lay(i, channel)` to deposit. Put per-state memory in the generic
scratch slots (`scratch_f0/f1/i`, `target`) and all randomness through `sim.rng`, so runs stay
deterministic. Renderers only read the simulation.

### 3. Register it

`species/<name>/register.gd` is found automatically (the Registry scans `species/*/register.gd`):

```gdscript
extends RefCounted

func register(registry: Registry) -> void:
	registry.register_species("harvester", preload("res://species/harvester/harvester.tres"))
	registry.register_food_source_type("seed_pile", SeedPile)
	registry.register_item_type("seed", Item)
	registry.register_nest_type("seed_nest", SeedNest)
	registry.register_renderer("food:seed_pile", SeedPileRenderer)
	registry.register_renderer("nest:seed_nest", SeedNestRenderer)
	# registry.register_behaviour("my_state", MyState.new())
	# registry.register_renderer("underground:my_nest", MyUnderground)
```

### 4. Put it in a scenario and test it

Add a colony to a scenario (`"species": "<name>"`, nest, population per caste) and run it
with **D** on to see every ant's state. Then add a test like `tests/test_two_species.gd`: the
colony forages successfully, food mass is conserved, no ant is ever inside an obstacle.
`tests/test_core_generic.gd` automatically checks that the new species' name never appears
in `/sim` or `/render`.

### Lessons (what went wrong along the way)

- **Every reachable state must be in the caste's `states` list.** Defaults count too:
  `follow_trail` goes to `explore` on timeout unless `on_timeout` says otherwise. Leafcutter
  majors, which have no `explore`, hit this in M7 (an assertion caught it). When a caste
  leaves out a core state, override every transition that leads to it.
- **"Would a second species plausibly need this?"** If yes, it belongs in the core, made
  generic: riding on items, debris, waste carrying, digging and bridges all started
  as leafcutter needs. If no, it stays in the species folder.
- **New `class_name` scripts** need the class cache refreshed (`tools/test.sh` does it;
  otherwise run `godot --headless --path . --import` once) before other scripts can use them.
- **Packed arrays are values.** Writing through a copy (a local variable, or an element of
  an `Array`) silently changes nothing. Write through the owning object (`sim.pos[i] = p`).
- **Tune with the panel** (**T**): the species' numeric tunables and pheromone channels get
  live sliders, and **Save** writes them back into the species' `.tres`.

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
    generic riding); the rest `linger` near the nest and take turns at midden work
    (`carry_waste`: carry a load of waste from the nest to the dump).
  - **medias** cut and carry.
  - **majors** `patrol_trail`: walk the foraging trail, and when debris sits on strong trail
    (`debris_trail_threshold`) `clear_debris` carries it off toward weaker trail.
- `fungus_nest.gd`: leafcutters farm fungus. Delivered leaf becomes substrate, the garden
  digests it (faster the bigger it is) into fungus and waste, the colony eats the fungus,
  and surplus fungus becomes brood: more garden, more ants. Starved, the garden shrinks and
  growth stops. The garden fills chambers, and a new one is dug when they're nearly full.
  Waste goes to a dump beside the entrance (`dump` offset). All rates are `nest_params`.
- `fungus_nest_renderer.gd`: the soil mound (grows with chambers) and the waste dump pile
  (grows with every load).
- `Brood` (core, `sim/nests/brood.gd`): the optional brood model (`nest_params.brood`). Without it new
  workers appear at the entrance at once, as before. With it the queen lays eggs that develop
  egg → larva → pupa → callow → worker:
  ```json
  "brood": {"lay_interval": 4, "egg": 40, "larva": 90, "pupa": 60, "callow": 8,
            "initial": {"egg": 6, "larva": 8, "pupa": 5}, "max_brood": 80}
  ```
  Stage durations are simulated seconds, tuned for video (real development takes weeks).
  The queen lays at most one egg every `lay_interval` seconds, paced by the same budget as
  before (`brood_rate` × fungus), while fungus is above `brood_reserve`, population + brood
  is under `max_population` and brood under `max_brood`. Eggs cost nothing; each larva eats
  `ant_cost` fungus over its stage. With fungus at or below the reserve, larvae stop growing
  (none die) and the queen stops laying. A callow ends with a real ant of the caste chosen
  at laying, spawned at the entrance, so `population` and `ants_raised` only rise at
  emergence. Records are packed arrays (id, stage, age, growth, caste; with care on
  also where each lies, see below). Laying and emergence are logged with their ticks (ring buffers), and
  the brood is part of `state_hash()` (runs without it keep their old hashes).


### Leafcutter nests that dig their own underground

The queen, brood care, nest roles, chamber architecture and extra entrances below are the
core's `ColonyNest` (harvester granary nests use them too); the gardens, the leaf line and the
founding queen's manuring are the leafcutter's own.

With `nest_params.underground` a `FungusNest` is a fully simulated underground, seen from above
in the split layout's nest part (or full screen). Every ant there is an agent doing real work:
- **Architecture** (`NestChambers` in the core, shared with harvesters; from the seed with its own RNG):
  - *Chambers* are slightly flattened blobs of 2–5 overlapping lobes, about half with a side
    alcove (a niche for brood); later chambers skew larger. The royal chamber is larger and
    bean-shaped, with a niche for the queen and her retinue and an alcove for pupae.
  - *Galleries*: up to three wide main galleries out of the royal chamber, secondary tunnels
    branching off galleries (tunnels branch off tunnels), and narrow capillaries from a
    junction on a gallery to a single chamber, so chambers hang off galleries like grapes on
    a stem. Short dead-end stubs (their ends are favoured chamber sites later) and
    cross-links between chambers that are near each other but far apart along the tunnels
    give the nest loops. Widths taper; every tunnel is routed (`SimLayer.route`).
  - Digging follows need: when the gardens fill, `plan_chamber()` plans a chamber at a free
    junction, first a gallery if few junctions are left and fewer than two are being dug
    (dug ahead of its chambers). Sites near the middle go first, so the nest fills in as a
    web and spreads outward. When nothing fits the nest waits 30 s before trying again.
    Every minute `rescue()` reconnects work whose way in will never open (a gallery
    abandoned partway): such galleries are dropped as hosts and their chambers get a new
    capillary from the nearest dug tunnel. Diggers are wanted at one per 6 cells of open
    work.
  - Everything that needs a place in a chamber uses its cells: `chamber_at()` is a cell map,
    and `random_point`, `floor_point` (away from walls), `rim_point`, `point_in` work for any
    shape. Stones inside a chamber's outline are dug out with it.
- **Busy tunnels become highways** (core `Highways`, on by default here), with lanes. Past each
  of `entrances.at` (population steps) the nest digs another entrance: a shaft facing the
  richest food, spaced from the others, reached by a routed gallery; it gets its own spoil
  heap and surface trail, and ants use whichever entrance is nearest.
- **The queen** (caste `queen`, only in these nests): a real ant resting at her spot in the royal
  chamber, laying each egg at the tip of her abdomen. Her retinue (`tend_queen`) grooms her; left
  ungroomed she lays at half pace. Laying is paced by the garden (as in M10) and limited to what
  the workers can care for (`brood_per_worker`).
- **Brood that needs care** (`Brood`, care mode): each egg, larva, pupa and callow
  lies somewhere (a pile, or carried) and gets dirty; neglected brood stops developing, larvae
  get hungry and only grow when fed, and starve after `starve_time`. Nurses (`nurse`, the shared
  `BroodCare` tasks) carry eggs from the queen to the egg pile, larvae into the garden and pupae
  to a drier spot, fetch gongylidia from the garden to feed larvae, groom, and free callows,
  which become real workers where they lie and take a role or walk up. Brood needs (dirt,
  hunger) are data the brood renderer shows.
- **Founding** (`"open": false`): the queen starts sealed in with a pellet of fungus, manures her
  garden from her reserves (`queen_reserve`) until the first leaf arrives, and tends her first
  brood herself (all minims: `first_caste`, `first_workers`). Once there are `open_entrance_at`
  workers they dig up to the surface (the extra-hard shaft job opens the entrance), and foraging
  begins.
- **Roles** (`nest_role`): workers take the role most short of hands relative to its need
  (weighted: nurses first, then the retinue, digging, gardening); idle nurses and gardeners move
  on when another role is short; surplus minims garden, and medias go out to forage. Diggers get
  more hands the fuller the gardens are.
- **Gardens cell by cell** (`garden_grid.gd`): a 2-unit grid (the nav grid is 4) over the gardens.
  Each cell has fungus, fresh pulp, spent material, age, gongylidia and mould. It is the M8 model:
  the gardens digest their pulp at `digest_rate` × fungus, each cell by its share of the pulp,
  the new fungus growing where the pulp was (spilling into a neighbour when a cell is full), so
  `FungusNest.fungus/substrate/waste` are the grid's totals. Old or mouldy cells turn spent; the
  colony's upkeep eats from every cell alike. A chamber's garden fills to its capacity, and when
  the gardens and the pulp waiting on them near capacity a new chamber is planned. New gardens
  are seeded with a little fungus carried from the fullest one.
- **The leaf line**: medias bring fragments down (`carry_down`) and drop them at the edge of the
  garden where fungus grows with room to spare; gardeners (`garden`) cut them into pulp a bite at
  a time (the fragment shrinks), plant it on the garden, weed spent material and mould, and carry
  it out to the dump beside the entrance (`carry_spent`). A delivery counts when a fragment
  arrives underground; leaf mass counts as delivered as it is planted (food mass stays conserved).
- nest params for this: `underground` (NestType's, plus `royal_radius`, `chamber_min_radius`,
  `chamber_max_radius`, `tunnel_radius`, `shaft_distance`, `shaft_hardness`, `garden_life`,
  `mould_rate`; here `texture` defaults to `{}` (on), `overdig` to 4.5 and `highways` to `{}`
  (on; `false` turns it off): `{"threshold": 45, "sustain": 3, "check_every": 20, "grow": 1.35,
  "max_radius": 14, "section": 50, "bypass": 1.8, "max_bypasses": 6, "half_life": 60,
  "lanes": 0.8}`), `entrances` (`{"at": [900, 2200], "spacing": 150}`), `initial_chambers`,
  `open_entrance_at`, `queen_reserve`, `queen_feed_rate`,
  `brood_per_nurse`, `retinue_max`, `dig_fraction`, `inside_share`, `queen_groom_time`,
  `garden_reserve` (0: use `brood_reserve`; else a share of garden capacity); in `brood`:
  `dirt_rate`, `hunger_rate`, `starve_time`, `brood_per_worker`, `first_caste`, `first_workers`.
- Rendering: `FungusUnderground` ("underground:fungus_nest") draws the gardens
  (`garden.gdshader`) and the brood (`brood.gdshader`); `CarriedBroodRenderer`
  ("underground_top:fungus_nest") the brood in nurses' jaws.

## Species: harvester ants

`species/harvester/`, added (M3) without touching the core or the leafcutter module:
- `harvester.tres`: minors (near-black) and big-headed majors (dark red), and a queen for
  nests that dig; violet/teal trails. On the surface they use only the core's generic
  behaviours.
- `seed_pile.gd` + renderer: a cluster of individual seeds; foragers walk to the nearest
  one, so the pile thins out seed by seed.
- `seed_nest.gd` + renderer: a `BasicNest` that counts seeds; drawn as a cleared sandy
  disc with a growing pile of husks. The species' default nest.

### Harvester nests that dig their own granaries

A scenario colony with `"nest_type": "granary_nest"` and `nest_params.underground` gets a
`GranaryNest` (`granary_nest.gd`), built on the core's `ColonyNest` like the leafcutter nest:
the queen in the royal chamber, brood that nurses care for, nest roles, chambers and galleries
dug as the nest needs room, founding sealed in, busy tunnels widening, more entrances. What is
the harvester's own:
- **Seeds are stored, one by one**: a forager home with a seed carries it down (`store_seed`)
  and drops it on the heap in a granary, the first with room (the first chamber dug is the
  brood chamber; every other one is a granary). Each stored seed is a record (where it lies,
  its mass, its look) and is drawn where it was put, so heaps grow seed by seed.
- **Founding**: the queen starts sealed in with a cache of seeds (`initial_seeds`) in the royal
  chamber, and feeds her first brood from it until the first forager comes home.
- **Eating**: the colony eats `upkeep_per_ant` per ant per second from the fullest granary,
  seed by seed (a seed shrinks as it is eaten); nurses chew seed meal off the heaps for the
  larvae (`ant_cost` per larva). The queen lays paced by `brood_rate` × the seed stored.
- **Chaff**: every seed eaten leaves `husk` × its mass as chaff by its heap; workers keeping the
  granaries (`tend_granary`) gather it in loads (`chaff_load`) and carry it out (`carry_spent`)
  to the midden beside the entrance. With nothing to carry they sort the heaps; up to
  `inside_share` (0.15) of the minors stay in for this, everyone else forages.
- **Room**: a new chamber is planned when the granaries are nearly full (`granary_capacity`
  per chamber of radius 40, by area) or the colony has outgrown its chambers
  (`ants_per_chamber`).
- Rendering: `GranaryUnderground` ("underground:granary_nest") draws each chamber's heap of
  seeds and the chaff around it, plus the core brood renderer; `GranaryNestRenderer` the
  cleared disc round each open entrance (wider as the colony grows) and the husk midden.
- nest params: ColonyNest's (see the leafcutter section) and `initial_seeds`, `seed_mass`,
  `upkeep_per_ant`, `granary_capacity`, `ants_per_chamber`, `husk`, `chaff_load`, `disc_radius`.

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
- `obstacle.gdshader`: stone walls with rim light and shadow; water with drifting ripples and
  a damp bank. The 4 px obstacle grid is sampled bicubically with a little noise, so outlines
  are smooth and natural.
- `bridge_renderer.gd`: bridges as big twigs (same generator as twig debris) with a shadow on
  the water.
- `rain.gdshader` + `rain_renderer.gd`: per shower, wet darkened soil with splash rings under
  everything, and overcast dimming with falling drops over everything. The ground stays wet
  and dries slowly after the rain.
- `split_layout.gd`: the split surface/underground layout (see `render.layout`), with a
  thin seam between the parts and a ring on a surface ant the nest names (a new worker).
- `soil.gdshader` + `soil_renderer.gd`: an underground layer from above: undug soil as a lit,
  raised mass (warped strata, grain, round grit, pebbles, fine roots, crumbly micro-relief,
  and where the soil has them redder clay, dark root fibres and grey knobbly stones) and the
  dug space as a packed floor with ambient occlusion near the walls, a shadow under a crumbly,
  overhanging rim scalloped by bites, and loose crumbs at the digging face and on fresh floor.
  Fresh digging is paler and moist and darkens as it dries (the mask's A channel: dig time,
  aged over 1,200 simulated seconds); busy floors (the layer's traffic map, uploaded as a
  float texture) are worn smooth and dark with a polished line down the middle. Only changed
  cells are re-uploaded.
- `portal_renderer.gd`: the bottom of a shaft (daylight falling in), or a soil plug while sealed;
  `spoil_heap_renderer.gd`: the heap of dug soil beside an entrance, crumb by crumb.
- Ants going through a portal fade out and in (`ant.gdshader`); filler ants stand in for an
  abstract population.
- Leafcutter: `garden.gdshader` (a raised spongy mass: cellular bumps and pores, strands,
  self-shadowing, a lumpy cottony edge with a floor shadow, green pulp flecks, browning with
  age and mould, gongylidia bead clusters; fine detail fades with zoom), `brood.gdshader`
  (glossy eggs, curled segmented larvae, pupae with folded legs whose eyes darken first,
  callows in split casings, dirt as a grey fuzz).
- `overlays.gd`: safe zones and the debug view (**D**; on the surface and in the nest view),
  which also shows the layer's traffic as a heat map (amber to red) where it is counted.

Shaders use a sine-free hash: `sin()`-based hashes show seams on some GPUs.
