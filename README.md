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
channel values under the cursor), **S** TikTok/Reels safe zones, **N** nest cutaway inset,
**L** layout: cycles surface / split (surface on top, the nest underground below) / nest
(the underground full screen, for nests that dig their own; see `render.layout`),
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
`godot --path . -- --scenario=fungus_farm --layout=split`. In the split layout the mouse
(walls, food, zoom, **F**, the debug readout) works on the surface part. The HUD counts every
ant of a colony, including its abstract population (see "Scale" below).

## Tools

```bash
tools/test.sh                                   # headless test suite (filter: tools/test.sh pheromones)
tools/screenshot.sh basic_forage 3600 out.png   # run 3600 ticks (2 min at 30 ticks/s), save a PNG
tools/screenshot.sh chaos_to_highway 3600 out.png -1 --zoom=3.5 --center=600,740   # close-up
tools/screenshot.sh two_species 2400 out.png -1 --safe=1 --debug=1 --pheromones=0    # overlays
tools/screenshot.sh nest_life 0 out.png -1 --layout=split --at=3    # split layout, 3 s in
godot --headless --path . -s res://tests/bench.gd -- basic_forage 600 3000   # sim timing: scenario, ticks, ants, [seed]
godot --headless --path . -s res://tests/bench.gd -- res://tests/fixtures/scenarios/nest_bench.json 900   # per layer
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
  steering.gd         three-sensor model, obstacle avoidance, movement (and move_to for tunnels)
  world.gd            obstacle grid (walls, water, diggable soil)
  layer.gd            SimLayer: one layer's World, PheromoneField and NavGrid
  portal.gd           a way between two layers (a nest entrance and its shaft)
  nav_grid.gd         distance fields over free cells toward named targets
  travel.gd           getting to a point on any layer (portals, nav fields)
  scenario_loader.gd  JSON scenario -> Simulation
  behaviours/         explore, follow_trail, go_to_food, carry_home, deliver, linger, carry_waste,
                      dig, carry_spoil, go_up
  food/ items/ nests/ FoodSource + FoodPile, Item + Debris, NestType + BasicNest,
                      ExcavationPlan (digging jobs)
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
  surface renderer (`"nest:<type>"`) and a cutaway view (`"cutaway:<type>"`).
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
  tunnel or round chamber to dig out from a point in space already open. Diggers (`dig`) take
  the open job with the lowest priority that has room, walk to it and then to its face, and bite
  (`dig_time`), clearing `cells_per_bite` cells of the face; the soil comes out as a pellet they
  carry up (`carry_spoil`) to `NestType.spoil_position()`, where it builds the spoil heap. While
  the nest is sealed the soil is pressed into the walls instead. A job can open a portal when it
  is finished (the entrance shaft).
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
colony grows from 150 to ~850 ants, waste piles up outside; with the cutaway inset),
`nest_life` (split view, 30 s: foraging on top; underground the queen lays, brood grows from
egg to pupa in timelapse, and at the end a young worker climbs out and joins the trail),
`colony_founding` (about 80 s, split view over a nest that digs its own underground: a queen
and four minims sealed in a founding chamber dig up to the surface, foraging begins, and over
about two simulated hours the colony grows to thousands, gardens filling chamber
after chamber and a heap of dug soil growing on the surface).

JSON files in `scenarios/`. Simulation content:
- `seed`
- `colonies`: species, nest position, population per caste, optional `release_per_second`
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
- `render.layout`: `{"mode": "split", "colony": 0, "surface": "top", "ratio": 0.45,
  "view": {"intro_spotlight": 5}}` splits the frame: the surface (the world, in a
  1080×(1920×ratio) SubViewport, so camera keyframes, clamping and follow work against
  that part) and, full width below it, the colony's nest: its underground layer, top-down and
  fully simulated, with its own camera, for a nest that digs (the nest's size and brood are
  shown top left); otherwise its side cutaway (`"cutaway:<type>"`). `"view"` sets properties the
  cutaway view declares. `"mode": "nest"` shows the underground full screen, and
  `"modes": [{"t": 0, "mode": "nest"}, {"t": 13, "mode": "split"}]` switches mode at video
  times. Nests with neither view play full screen. See `render/split_layout.gd`
- `render`: `{"pheromones": true, "pheromone_opacity": 0.55, "cutaway": {"colony": 0,
  "rect": [x, y, w, h], "from": 2, "to": 18}}`. The cutaway is an inset (screen pixels of
  the 1080×1920 frame) showing the colony's nest from the side, for nest types that have a
  cutaway view (`render/cutaway_panel.gd`); `from`/`to` are video seconds, faded

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
| `FORMAT=avi tools/record.sh colony_founding` | 79 min for the 80 s video (4,800 frames, ~7,200 simulated seconds, ~215,000 ticks; most of it the last 50 s at 70–80 ticks per frame with 1,600 agents); ends at ~3,500 ants |

- At 30 ticks/s and 60 fps each frame runs half a tick, so 3,000 ants need about 12.5 ms of
  every 16.7 ms frame for the simulation alone. That fits while ants explore, but busy
  foraging (more states, carried items to draw) tips it over. The ant logic is the limit, not
  pheromones or rendering. Getting to a steady 60 fps at 3,000+ ants needs the ant update in
  native code (GDExtension), which hasn't been done.
- If a frame runs long, the interactive app advances at most 1/30 s per frame, so a heavy
  scene runs slower rather than spiralling into ever longer frames. Recordings always advance
  exactly 1/60 s per frame and are unaffected.
- Recording is offline, so timelapses and large colonies are fine; they only take longer to
  record.
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
| Nest | `NestType` or `BasicNest` (`receive_item()`, `update()`, optional waste) | `seed_nest.gd` | `fungus_nest.gd` |
| Renderer | any `Node2D` with `bind(sim, target)` | `seed_pile_renderer.gd`, `seed_nest_renderer.gd` | `leaf_renderer.gd`, `fungus_nest_renderer.gd` |
| Cutaway view | a `Control` with `bind(sim, nest)` | none | `fungus_cutaway.gd` |

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
	# registry.register_renderer("cutaway:my_nest", MyCutaway)
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
  generic: riding on items, debris, waste carrying, cutaway panels and bridges all started
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
- `leafcutter_brood.gd`: the optional brood model (`nest_params.brood`). Without it new
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
  emergence. Records are packed arrays (id, stage, age, chamber, slot, growth, caste): eggs
  in the royal chamber 0, larvae in chamber 1 and pupae in chamber 2 (each spilling into 3
  and 4 when full). Laying and emergence are logged with their ticks (ring buffers), and
  the brood is part of `state_hash()` (runs without it keep their old hashes).
- `fungus_nest_renderer.gd`: the soil mound (grows with chambers) and the waste dump pile
  (grows with every load).
- `fungus_cutaway.gd` + `fungus_garden.gdshader`: the cutaway: soil strata, tunnels and
  chambers (dug as they appear), the garden as soft off-white lumps filling them from the
  floor up, green flecks of undigested leaf and the colony size. Its detail depends on its
  size. As a small inset: tiny ants walk the tunnels. From 700 px wide (the underground half
  of the split layout): bigger chambers with room above the garden, the entrance lined up
  under the surface nest, labels inside the safe zone, and `nest_life_view.gd` draws:
  - the queen (side view, swollen gaster) on the garden of the royal chamber; each egg the
    simulation lays appears at her abdomen tip at that moment and a nurse carries it to the
    egg pile;
  - the brood at its chamber and slot: larvae (white grubs growing as nurses bring them
    fungus), pupae in rows (pale, legs folded, darkening, eyes first), callows (pale young
    workers) that a nurse helps out of the casing and that then walk up the tunnels timed by
    their age, so they leave the view on the tick the simulation spawns them on the surface
    (where the split layout rings them);
  - one leaf carrier coming down per fragment delivered (`leaf_items`), dropping it on the
    garden.
  Nurses and carriers (`nest_worker.gd`) are render-only agents given tasks from the brood
  state; they hurry in timelapse, and brood no nurse reaches in time fades to its place.
  `"view": {"intro_spotlight": 5}` dims everything but the queen for the first seconds.


### Leafcutter nests that dig their own underground

With `nest_params.underground` a `FungusNest` is a fully simulated underground, seen from above
in the split layout's nest part (or full screen). Every ant there is an agent doing real work:
- **Chambers** (`fungus_chambers.gd`): the royal chamber in the middle, then garden chambers
  planned procedurally from the seed (a parent chamber, more often a recent one, a direction
  away from the middle, a tunnel length; clear of other chambers and the layer's edge). The first
  chambers are small, later ones larger. Each is two digging jobs: the tunnel from its parent's
  rim, then the chamber. The shaft comes down beside the royal chamber.
- **The queen** (caste `queen`, only in these nests): a real ant resting at her spot in the royal
  chamber, laying each egg at the tip of her abdomen. Her retinue (`tend_queen`) grooms her; left
  ungroomed she lays at half pace. Laying is paced by the garden (as in M10) and limited to what
  the workers can care for (`brood_per_worker`).
- **Brood that needs care** (`leafcutter_brood.gd`, care mode): each egg, larva, pupa and callow
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
  `mould_rate`), `initial_chambers`, `open_entrance_at`, `queen_reserve`, `queen_feed_rate`,
  `brood_per_nurse`, `retinue_max`, `dig_fraction`, `inside_share`, `queen_groom_time`,
  `garden_reserve` (0: use `brood_reserve`; else a share of garden capacity); in `brood`:
  `dirt_rate`, `hunger_rate`, `starve_time`, `brood_per_worker`, `first_caste`, `first_workers`.
- Rendering: `FungusUnderground` ("underground:fungus_nest") draws the gardens
  (`garden.gdshader`) and the brood (`brood.gdshader`); `CarriedBroodRenderer`
  ("underground_top:fungus_nest") the brood in nurses' jaws. The M10 side cutaway still serves
  nests without an underground (`nest_life`, `fungus_farm`).
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
- `obstacle.gdshader`: stone walls with rim light and shadow; water with drifting ripples and
  a damp bank. The 4 px obstacle grid is sampled bicubically with a little noise, so outlines
  are smooth and natural.
- `bridge_renderer.gd`: bridges as big twigs (same generator as twig debris) with a shadow on
  the water.
- `rain.gdshader` + `rain_renderer.gd`: per shower, wet darkened soil with splash rings under
  everything, and overcast dimming with falling drops over everything. The ground stays wet
  and dries slowly after the rain.
- `side_ant.gdshader` + `side_ant_renderer.gd`: ants seen from the side, for cutaway views:
  lit segments with a dark rim, raised-knee legs in a tripod gait, antennae; legs toward
  whichever side is ground (floors, walls, ceilings); `fold` tucks legs and antennae in.
- `split_layout.gd`: the split surface/underground layout (see `render.layout`), with a
  thin seam between the parts and a ring on a surface ant the cutaway names (a new worker).
- `soil.gdshader` + `soil_renderer.gd`: an underground layer from above: undug soil as a lit,
  raised mass (warped strata, grain, round grit, pebbles, fine roots, crumbly micro-relief) and
  the dug space as a paler packed floor with ambient occlusion near the walls, a shadow under
  the soil's rim and loose crumbs at the digging face. Static; only dug cells are re-uploaded.
- `portal_renderer.gd`: the bottom of a shaft (daylight falling in), or a soil plug while sealed;
  `spoil_heap_renderer.gd`: the heap of dug soil beside an entrance, crumb by crumb.
- Ants going through a portal fade out and in (`ant.gdshader`); filler ants stand in for an
  abstract population.
- Leafcutter: `garden.gdshader` (a raised spongy mass: cellular bumps and pores, strands,
  self-shadowing, a lumpy cottony edge with a floor shadow, green pulp flecks, browning with
  age and mould, gongylidia bead clusters; fine detail fades with zoom), `brood.gdshader`
  (glossy eggs, curled segmented larvae, pupae with folded legs whose eyes darken first,
  callows in split casings, dirt as a grey fuzz).
- `overlays.gd`: safe zones and the debug view.

Shaders use a sine-free hash: `sin()`-based hashes show seams on some GPUs.
