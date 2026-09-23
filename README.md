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
  behaviours/         explore, follow_trail, go_to_food, carry_home, deliver, linger, carry_waste
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
(debris falls on an established trail; majors clear it, minims ride fragments), `rain_reset`
(a downpour washes an established trail away and the colony rebuilds it), `twig_bridge` (a
leaf across a stream; one fallen twig is the only way over), `maze` (a leaf behind rows of
stone walls; explorers find the gaps and a trail settles on one route),
`fungus_farm` (a young colony over ~17 minutes: the garden grows chamber by chamber, the
colony grows from 150 to ~850 ants, waste piles up outside; with the cutaway inset).

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
  "state": "carry_home"}` in place of `pos` tracks the nearest matching ant
  (see `render/camera_director.gd`)
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
- `fungus_cutaway.gd` + `fungus_garden.gdshader`: the cutaway inset: soil strata, tunnels and
  chambers (dug as they appear), the garden as soft off-white lumps filling them from the
  floor up, green flecks of undigested leaf, tiny ants in the tunnels and the colony size.

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
- `overlays.gd`: safe zones and the debug view.

Shaders use a sine-free hash: `sin()`-based hashes show seams on some GPUs.
