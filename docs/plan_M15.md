# M15: Surface scenery (ground, rocks, logs, plants, nest entrances, refuse)

Goal: make the surface (layer 0) look like a real patch of ground seen from above: varied
ground (soil, sand, gravel, moss, dry litter), boulders and fallen branches that ants
walk around, and plants and grass whose stems block and whose tops hang over the ants.
Nest entrances look like real holes, craters and mounds, worn by traffic, and colony
refuse becomes a proper system: middens that are placed sensibly, hold what was
actually thrown out, age and decay. Scenarios describe scenery as data, or scatter it
from a preset, and none of it breaks determinism, the native kernel or the video budget.

Status: M15a, M15b, M15c, M15d done; next M15e.

## Where things stand (before M15)

- `render/ground.gdshader`: one static soil look (patches, clods, grain, specks, shaded
  pebbles), seeded by `ground_seed`. No materials or regions.
- `render/obstacle.gdshader` + `obstacle_renderer.gd`: the 4 px obstacle grid (R wall,
  G water) sampled bicubically. Every wall looks like the same rough grey stone, whatever
  its shape; there are no props with their own look.
- `sim/items/debris.gd`: twigs and pebbles as Items (`twig_image`), slowing ants through
  `World.clutter`. Bridges reuse the twig generator.
- Scenario obstacles: polyline, rect, circle, polygon; `"kind": "water"` / `"bridge"`
  (`ScenarioEvents.add_obstacle`).
- Draw order (`render/world_view.gd`): ground, wet ground, obstacles, bridges, nests,
  pheromone glow, food, ground items, ants, carried items, rain. Nothing is drawn over
  the ants except carried items and rain.
- **Entrances** are drawn by each nest renderer as flat stacked circles: a darker disc
  and a black disc (`fungus_nest_renderer.gd` `_draw_mound`, `seed_nest_renderer.gd`,
  `basic_nest_renderer.gd`); extra entrances are smaller copies. `granary_nest_renderer.gd`
  adds a cleared sand disc. Spoil heaps (`render/spoil_heap_renderer.gd`) are round
  accreting piles at `NestType.spoil_position_of(e)`, a fixed offset from each entrance.
  No depth, no inner wall, no worn ground, and the hole doesn't change with traffic.
- **Refuse** (`sim/behaviours/carry_waste.gd`, `carry_spent.gd`, `NestType` "Waste"
  section): one dump per nest at a fixed `dump_offset` from the nest (`ColonyNest`
  default (120, 40), granary (90, 55)). A dropped load is destroyed at once and only
  the totals `dumped_items` / `dumped_mass` are kept; the species renderers draw an
  accreting disc of identical blobs (fungus nest `DumpChunk`) or husk ellipses
  (granary `_draw_midden`) from the count. So middens are growing circles next to the
  nest: they don't show what was dumped, never age, ignore trails, obstacles and
  entrances, and are the same for every species. Workers never die, so there are no
  corpses; brood deaths (`sim/nests/brood.gd`) leave nothing behind.
- Surface `TrafficMap` (`sim/traffic_map.gd`) exists but is only enabled underground
  by `Highways`; `SimLayer.enable_traffic` can turn it on for layer 0.

## Design decisions (apply to every phase)

1. **Naming / core boundary.** Scenery is core, so it lives in `sim/scenery/` and
   `render/scenery/`, and `tests/test_core_generic.gd` forbids the word "leaf" there. Use
   "plant", "blade", "frond", "litter", "canopy". Species may register extra scenery types
   later (through `Registry`, like food and items).
2. **Scenery is not sim state except its footprint.** Props are generated once at load
   from their own `RandomNumberGenerator` (seeded from the scenario seed and the prop
   index), **never `sim.rng`**, and are not hashed. The only thing that reaches the
   simulation is the blocking footprint stamped into `World.obstacles` as `Cell.WALL`,
   so steering, `near_blocked`, NavGrid and the native kernel (`obstacles[i] != 0`)
   need no changes.
3. **The renderer must know which wall cells belong to a prop**, so the stone-wall look
   is not painted over a log or a plant stem: `World` gets a render-only `prop_mask`
   (PackedByteArray, not hashed, not passed to the kernel); `ObstacleRenderer` treats
   masked cells as free (a third mask channel, B).
4. **Hashes of existing scenarios stay unchanged** (`tests/test_layers.gd`
   `SINGLE_LAYER_HASHES`, `tests/test_native.gd`). Existing scenarios only get
   non-blocking scenery (ground materials, litter, canopy that stems nothing) unless we
   decide to update the hash table deliberately in M15f (open question below).
5. **Video first.** Anything animated (sway) is slow and small, as it costs bitrate.
   Canopy over ants must keep them readable: partial alpha, thinning near its edges,
   and it never hides a nest entrance or the followed ant. Everything static is baked
   once (images / textures), not redrawn per frame.
6. **Surface only for scenery.** Underground layers are untouched (the refuse phases
   may add an optional underground refuse chamber; see M15f).
7. **Entrances and middens are core, styled per species.** One core renderer draws
   every surface entrance and one core system holds every midden; species choose a
   style through data (`SpeciesDef` / nest params, e.g. `"entrance_style": "crater"`,
   `"midden_style": "ring"`) and register refuse *kinds* with their own renderers
   (`"refuse:<kind>"`), like items. Species renderers stop drawing their own crater
   circles and dump blobs.
8. **Refuse changes behaviour, so it is hash-sensitive.** Midden placement and any new
   worker behaviour use `sim.rng` only where the old code already drew from it; new
   choices (midden sites) use a separate seeded RNG or deterministic scoring. Worker
   death is opt-in (`worker_lifespan`, default 0 = never) so existing runs keep their
   hashes. Check `fungus_farm` (in `SINGLE_LAYER_HASHES`) and the `test_native` hashes
   after each refuse phase; `carry_waste` / `carry_spent` are GDScript-only states
   (not in the native kernel), so no kernel change is expected.

Draw order after M15 (surface):
ground (+ materials) → ground cover (litter, moss decals) → wet ground → obstacles
(walls/water) → **worn ground (surface traffic)** → prop bases (rocks, logs, plant
stems + their contact shadows) → bridges → **middens (aged stain, then deposits)** →
nests / **entrances (apron, crater, hole, spoil)** → pheromone glow → food → ground
items → ants → carried items → **canopy (plant tops, grass blades) + canopy shadow** →
rain.

## Scenario format (target)

```json
"ground": {
  "base": "soil",
  "regions": [
    {"material": "sand",   "shape": "circle", "center": [300, 1400], "radius": 220, "soft": 60},
    {"material": "moss",   "shape": "polygon", "points": [[...]], "soft": 40},
    {"material": "litter", "noise": {"scale": 300, "cover": 0.3}}
  ]
},
"scenery": [
  {"type": "rock",  "center": [540, 900], "radius": 60, "flat": 0.7},
  {"type": "log",   "points": [[100, 600], [420, 520]], "width": 34},
  {"type": "plant", "kind": "rosette", "center": [800, 300], "radius": 90, "stem": 10},
  {"type": "grass", "center": [200, 200], "radius": 50},
  {"scatter": {"preset": "meadow", "density": 1.0, "keep_clear": 80,
               "avoid": ["nests", "food"], "rect": [0, 0, 1080, 1920]}}
]
```

Per colony (`nest_params`, defaults from the species):

```json
"nest_params": {
  "entrance": {"style": "crater", "clear_radius": 90, "clears_plants": true},
  "midden": {"style": "pile", "distance": [110, 220], "sites": 2, "avoid_trails": true},
  "dump": [120, 40]
},
"params": {"worker_lifespan": 0}
```

Entrance styles (M15e): `hole` (plain hole with a worn rim; basic nest), `crater`
(ring of excavated grit around a funnel; harvester), `mound` (loose soil cone with the
hole on top, spoil spread on it; leafcutter), `turret` (small raised collar). Midden
styles (M15f/g): `pile` (a heap that spreads outward; leafcutter), `ring` (a band at
the edge of the cleared disc; harvester chaff), `scatter` (loose deposits along a
stretch). An explicit `"dump"` keeps today's single fixed site.

Materials (M15b): `soil` (today's look), `sand`, `gravel`, `moss`, `litter`,
`dry` (cracked clay). Props (M15c/d): `rock`, `log`, `plant` (`rosette`, `clover`,
`fern`, `seedling`), `grass`. Each prop type declares: footprint (circle/polyline/
polygon or none), whether it blocks, and which passes it draws (base, canopy).

## Phases

### M15a: scenery model, loader and footprints (no new visuals yet)

Goal: props exist as data, are generated deterministically, stamp their footprints and
render as placeholders (flat outlines) so later phases only add looks.

- New `sim/scenery/scenery.gd` (`Scenery`: list of `Prop` records: type id, position,
  rotation, scale, params dict, footprint, blocks, own seed), `sim/scenery/prop_type.gd`
  (base class: `build(prop, rng)` fills geometry; `stamp(world, prop)`).
- `Registry.register_scenery_type(id, script)`; core types registered in
  `sim/core_module.gd`.
- `World.prop_mask` + stamping helpers (reuse `fill_circle` / `draw_polyline` /
  `fill_polygon` with a mask write); `ObstacleRenderer` uploads B = prop.
- `ScenarioLoader`: `"scenery"` list (explicit props only; `scatter` comes in M15h);
  `ScenarioEvents`: `add_scenery` / `remove_scenery` events (useful for a falling
  branch later), bumping `world.version`.
- `render/scenery/scenery_renderer.gd`: placeholder outlines, base and canopy nodes
  wired into `world_view.gd` at the draw-order slots above.
- Tests (`tests/test_scenery.gd`): same seed → same props; props don't touch `sim.rng`
  (state hash with and without a non-blocking prop is equal); a blocking prop blocks
  ants (no ant inside it after N ticks, GDScript and native); `prop_mask` cells render
  as free in the obstacle mask; `test_core_generic` passes.
- Verify: `tools/test.sh` (full suite, background); a still of a test scenario.
- Hands on: the `PropType` API and where each renderer pass plugs in.

### M15b: ground materials and ground cover

Goal: the ground stops being uniform brown.

- `sim/scenery/ground_map.gd`: builds a low-res material-weight texture (e.g. 8 world
  units per texel, RGBA = sand, gravel, moss, litter; `dry` as a second texture or a
  packed channel) from `"ground"` regions + noise, soft edges.
- `render/ground.gdshader`: blend per-material looks: sand (fine light grain, ripples),
  gravel (dense small pebbles, reuse the pebble loop at a smaller spacing), moss
  (green cushion bumps with self-shadow), litter (dried fragments: baked sprite atlas
  in a pass below, the shader only tints), dry clay (Voronoi cracks, sine-free hash).
  Keep everything a function of world position (static, compresses well).
- `render/scenery/ground_cover_renderer.gd`: scattered flat decals (litter fragments,
  bits of bark, seed husks) baked into a few atlas images and drawn with one
  MultiMesh; density from the material map. Not items, no clutter, no sim effect.
- Rain: check `rain.gdshader` wet darkening still reads well over sand/moss.
- Verify: stills of a scratch scenario with every material, at zoom 1 and 3; the suite
  (hashes must not change: ground is render-only).
- Hands on: the material map texture and its uniform names, for props that tint by
  what they stand on (moss on rocks near moss).

### M15c: rocks and logs

Goal: obstacles with their own shapes and looks instead of the generic stone grid.

- `sim/scenery/rock.gd`: outline as a noisy convex-ish polygon (radius, flatness,
  lumpiness); footprint = polygon. `sim/scenery/log.gd`: polyline with width taper,
  optional side branch stubs; footprint = thick polyline.
- `render/scenery/prop_baker.gd`: bakes each prop to an Image once (like
  `Debris.twig_image`), with normals-ish shading from the shared `light_dir`.
- Rocks: domed shading, facets, cracks, lichen spots, moss on the shaded side when
  standing on moss; soft contact shadow + ambient occlusion ring on the ground.
- Logs: bark ridges along the axis, cut/broken ends with rings, peeling bark patches,
  a longer cast shadow (they're taller than rocks).
- Also: let scenario walls opt into a prop look (`"look": "rock"` on existing obstacle
  shapes) so `maze` can be restyled later without moving any cell.
- Verify: stills; `tests/test_scenery.gd` additions (footprint matches the drawn
  outline within one cell, i.e. ants don't walk through drawn rock or stop short of it
  visibly); suite.
- Hands on: `PropBaker` API for plants.

### M15d: plants and grass (base + canopy)

Goal: plants whose stems block and whose tops hang over the ants.

- `sim/scenery/plant.gd`: kinds `rosette` (dandelion/plantain-like: 6–12 long blades
  from a centre), `clover` (trefoil clusters on thin stalks), `fern` (pinnate fronds),
  `seedling` (two to four small blades), `grass` (clump of long thin blades, some
  bent). Footprint: small stem circle(s) only; everything else is canopy.
- Baked in two images per plant: base (stem, the lowest bits touching the ground) and
  canopy (the rest), plus a canopy shadow image.
- `render/scenery/canopy_renderer.gd`: draws canopy above ants; `canopy.gdshader`:
  veins, translucency (light through blades), soft edge; slow wind sway as a small
  per-blade vertex offset (a global `wind` uniform so rain events can gust it); alpha
  thins toward the tips so ants underneath stay visible. Canopy shadow drawn over
  ants and ground (dappled darkening).
- Readability rules: canopy alpha lowered within a radius of nest entrances, food and
  the camera's followed ant (a small uniform array or a mask texture).
- Performance: all plants in one or two MultiMeshes/atlases; check with
  `--probe=1` (`tests/frame_probe.gd`) at 3,000 ants with ~200 plants; record the
  numbers for the README.
- Verify: stills at zoom 1 and close up; a short AVI draft (`FORMAT=avi tools/record.sh`)
  of a scratch scenario to judge sway and readability; suite.
- Hands on: prop list for presets.

### M15e: realistic nest entrances

Goal: entrances read as holes going down into the ground, shaped by the species and
worn by the traffic through them.

- `render/entrance_renderer.gd` + `render/entrance.gdshader` (core): one node per
  surface entrance of every nest (main + `extra_portals`, via `NestType.entrances()`),
  replacing the crater circles in `fungus_nest_renderer.gd`, `seed_nest_renderer.gd`,
  `granary_nest_renderer.gd` and `basic_nest_renderer.gd` (those keep only their
  species extras: cleared disc, mound body).
- The hole: an irregular (noise-warped) opening, a funnel with the inner wall lit on
  the side facing away from `light_dir` and in deep shadow on the other, the throat
  fading to black; a raised lip of packed, slightly darker soil with a highlight on
  the lit edge. Sealed: a soil plug with scuffed crumbs (as today, but in the shader).
- Styles from nest params (see format above): `hole`, `crater` (grit ring with fine
  pebbles, funnel slopes), `mound` (low cone, hole on top, radial erosion runnels),
  `turret` (raised collar with its own shadow). Size grows with the traffic through
  the entrance (portal use count) rather than chambers only; extra entrances start
  small and widen as they're used.
- Spoil heaps: `spoil_heap_renderer.gd` shapes the heap as a fan or crescent on the
  outward side of its entrance (from `spoil_position_of`), drawn with the ground-
  material palette of M15b, and for `crater` / `mound` styles blends into the rim so
  heap and entrance read as one piece of excavation.
- Worn ground: enable the surface `TrafficMap` (render use only, not hashed, no RNG;
  check `state_hash` doesn't include it) and draw packed, darker, smoother soil where
  ants walk: an apron round each entrance and faint paths out along the busiest
  routes. Uploaded as a low-res float texture like `soil_renderer.gd` does underground.
- Scenery interaction: `clears_plants` fades canopy and ground cover inside the
  cleared disc as the colony grows (harvester discs); new entrances are placed off
  prop cells (check the entrance choice in `ColonyNest` / `NestChambers`; must stay
  deterministic and not change hashes for scenarios without scenery).
- Ants entering: in `ant.gdshader`, ants within the funnel darken and shrink slightly
  toward the hole before the existing portal fade (render only).
- Verify: close-up stills of each style open and sealed, and of `colony_founding` /
  `harvester_founding` late (several entrances); a short AVI draft of ants streaming
  in; suite (hashes unchanged).
- Hands on: entrance positions/radii API that middens and scatter keep clear of.

### M15f: refuse system (simulation)

Goal: middens become real places holding real deposits, sited like ants site them.

- `sim/nests/midden.gd` (core): a midden site (position, style, radius) and its
  deposits: small records (position, kind id, mass, time dropped), kept in packed
  arrays per midden, not Items (cheap at thousands). `NestType` gets `middens` and
  `midden_for(at)` / `drop_refuse(sim, item, at)` in place of `receive_waste`
  (which stays as the fallback that keeps totals).
- Siting (when the first refuse is ready, then when a midden is "full"): score
  candidate points on a ring `distance` from the nest by distance from food trails
  (lowest outgoing food/trail pheromone, sampled), from entrances, spoil heaps and
  props, preferring downhill/low ground if the material map says so; deterministic
  scoring, no new `sim.rng` draws. `"dump"` given explicitly = today's single site.
- Where loads land: `carry_waste` / `carry_spent` drop on the edge of the pile facing
  the nest (piles grow outward, away from the entrance), or along the ring for
  `ring`, instead of a random point in a disc. Keep their `sim.rng` draw count the
  same so hashes only move where the site moves.
- Refuse kinds: registered by id with a mass → size rule and a renderer
  (`registry.register_refuse_kind`); core kinds `soil_clump`, `husk`, `corpse`,
  `brood_corpse`, `remnant` (inedible food leftovers); species map their waste items
  to kinds (leafcutter spent substrate, harvester husks) in `register.gd`.
- Corpses (opt-in): `worker_lifespan` (seconds, default 0 = immortal) and brood deaths
  in `Brood` leave a `corpse` / `brood_corpse` item where they happened; a
  `carry_corpse` behaviour (core, reuses `carry_spent` travel) takes it to a midden.
  Wire the state into both species' `state_params`; off in every existing scenario.
- Decay: deposits compact and lose mass with a half-life per kind; fully decayed ones
  are merged into the midden's `stain` (a per-midden low-res grid of accumulated
  matter), so the deposit count stays bounded however long the run.
- Optional (only if time allows): midden workers who stay at the midden and push
  deposits outward, as leafcutters do.
- Tests (`tests/test_midden.gd`): mass conservation (carried out = deposits + stain +
  decayed); midden sites avoid trails and entrances; deterministic; `worker_lifespan`
  0 leaves hashes of every scenario unchanged (`test_layers`, `test_native`); with
  lifespan > 0 corpses end up on a midden; deposit count stays under its cap over a
  long run.
- Verify: the suite; `fungus_farm` and `harvester_founding` probes of midden count,
  deposits and mass over a full run (background).
- Hands on: the deposit arrays and stain grid the renderer reads, with a version
  counter for incremental redraws.

### M15g: refuse rendering

Goal: a midden shows what's in it and how old it is.

- `render/midden_renderer.gd` (core) replaces the dump drawing in
  `fungus_nest_renderer.gd` (`DumpChunk`) and `granary_nest_renderer.gd`
  (`_draw_midden`): per kind a baked sprite atlas (drawn with MultiMesh, chunked like
  `SpoilHeapRenderer` so only new deposits redraw): soil clumps, husks (split seed
  coats, species-coloured), curled dead ants (legs folded, caste colours and size from
  `CasteDef`, reusing the ant look), brood corpses, crumbs of spent material.
- Age: deposits darken, flatten and lose saturation as they decay; the stain grid is
  drawn under them as a dark, humus-rich patch with a soft irregular edge, so an old
  midden is a dark stain with a fresh layer on top.
- Height: piles get a soft self-shadow and a raised rim from deposit density (like the
  spoil heap), so a big pile reads as a mound, not a disc.
- Species extras through registered renderers: leafcutter spent substrate greys with
  white mould fuzz and a faint grey-green tint; harvester chaff ring bleaches in sun.
- Rain: wet middens darken more and deposits look glossy (read the existing wet mask).
- Verify: close-up stills early and late in `fungus_farm` and `harvester_founding`,
  and a corpse test scenario; frame probe with a full midden; suite.

### M15h: scatter presets and keep-clear rules

Goal: scenarios can say "meadow here" instead of placing 200 props by hand.

- `sim/scenery/scatter.gd`: Poisson-disc placement per preset (`meadow`, `forest_floor`,
  `rocky`, `sandy`), with per-type weights, size ranges and the ground materials they
  prefer (driven by the M15b map, e.g. moss under ferns, sand gets few plants).
- Keep-clear: nests (radius + all current and planned entrances, spoil heaps, cleared
  discs from M15e), midden sites and their growth room (M15f), food, portals, explicit
  `"keep_clear"` shapes/paths, world edges.
- Connectivity: after placing blocking footprints, flood-fill the surface grid from each
  nest and drop the most recent blocking prop that disconnects a food source (or the
  world edge for digging colonies); only non-blocking canopy is kept there.
- Dynamic entrances and middens appear later in a run: reserve a clear ring around
  each nest sized for its expected entrances and middens (M15e already keeps new
  entrances off prop cells; M15f midden siting already scores props).
- Tests: same seed → same scatter; every food reachable from its colony; nothing in
  keep-clear zones; entrance opening never lands inside a prop.
- Verify: stills of each preset; suite.

### M15i: scenarios, showcase and docs

Goal: use it everywhere it helps, and document it.

- Add non-blocking scenery (ground materials, litter, canopy-only grass at the edges)
  to existing scenarios so their hashes stay unchanged; confirm with
  `test_layers`/`test_native`.
- New scenario `meadow_forage` (or restyle `maze` as a rock garden and `twig_bridge` as a
  stream through moss, if we accept new hashes, see open question).
- `colony_founding` / `harvester_founding`: scatter around the nest with a keep-clear
  ring; run `tests/nest_probe.gd` over the full 7200 s in the background to confirm
  growth is not blocked by props (A/B against M14 numbers).
- Entrance and midden styles set in `leafcutter.tres` / `harvester.tres`; a corpse
  demo (short `worker_lifespan`) in the showcase scenario only.
- README: "Visual style" (ground materials, props, canopy, entrances, middens),
  "Scenarios" (`ground`, `scenery`, scatter presets, `entrance` / `midden` nest params,
  `worker_lifespan`), the refuse system under "How the simulation works", performance
  numbers from M15d/g.
- Record final PNG videos for the restyled scenarios (background, separate session if long).

## Open questions (decide before the phase that needs them)

- M15f: new midden siting moves where waste lands in `fungus_farm`,
  `colony_founding` and `harvester_founding`. If `fungus_farm`'s 300-tick hash in
  `SINGLE_LAYER_HASHES` changes (waste may not start that early), re-record it or keep
  the old site through an explicit `"dump"` in that scenario? Default: re-record, with
  a note in the commit.
- M15f: should worker death be on in the founding scenarios (corpses on the midden
  over two simulated hours), or only in a demo? Default: demo only in M15.
- M15i: may existing scenarios get blocking props (rocks, stems), with the
  `SINGLE_LAYER_HASHES` table in `tests/test_layers.gd` re-recorded? Default: no, only
  non-blocking scenery on existing scenarios; blocking scenery in new scenarios.
- Should materials change movement (sand slower, moss neutral)? Default: no in M15, it
  would need the native kernel (a per-cell speed table like `clutter`). Candidate for a
  later milestone.
- Should leafcutter leaf sources grow on plants (species registering a plant type whose
  canopy is a harvestable source)? Out of scope for M15; the `PropType` registry is meant
  to allow it later from `species/leafcutter/`.

## Progress log

(Each phase appends: what was done, what changed from the plan, notes for the next phase.)

### M15a (done)

Done:
- `sim/scenery/`: `Prop` (record: id, type_id, name, position, rotation, scale, params,
  `prop_seed`, blocks, footprint dict, `outline` (base), `canopy`, bounds, claimed `cells`),
  `PropType` (`build(prop, rng)`, `stamp(world, prop)`, `footprint_cells()`; static helpers
  `rotation_of`, `blob` (lumpy ellipse), `strip_outline` (thick polyline outline),
  `params_vec2/points`), `Scenery` (`add(data)`, `remove(prop)`, `named()`, `props_at()`,
  `version`), and core types `RockProp` (lumpy ellipse polygon), `LogProp` (tapered strip,
  footprint = polyline at full width), `PlantProp` (registered as both `plant` and `grass`;
  stem circle footprint if `stem` > 0, star-shaped canopy placeholder; grass defaults to
  stem 0 = canopy only).
- `Registry.scenery_types` / `register_scenery_type(id, script)`; `CoreModule` registers
  rock, log, plant, grass. `Simulation.scenery` is created in `_init` with the run seed.
  Prop RNG seed = `Scenery.prop_seed_for(seed, id)`; a `--seed` override therefore reshapes
  props too.
- `World`: `cells_in_circle` / `cells_in_polygon` / `cells_in_polyline` (the fill_* and
  draw_polyline now go through these; same cells as before, hashes unchanged),
  `prop_mask` (a per-cell count, so overlapping props free shared cells only when the last
  one goes), `add_prop_cells` (claims only FREE or prop cells: walls/water/soil untouched),
  `remove_prop_cells`, `is_prop_cell`.
- `ObstacleRenderer` uploads RGB8 (R wall, G water, B prop); prop cells have R = 0 so no
  stone is drawn; `ObstacleRenderer.mask_bytes(world)` is static for tests.
- `ScenarioLoader`: `"scenery"` after `"obstacles"`, before food/colonies. `ScenarioEvents`:
  `add_scenery` (one prop or a list) and `remove_scenery` (`"name"` or `"at"`); entries with
  `"scatter"` are skipped with a warning until M15h.
- `render/scenery/scenery_renderer.gd` (`SceneryRenderer`, `Pass.BASE` / `Pass.CANOPY`):
  flat fills + outlines per type. `WorldView`: base right after obstacles (before bridges);
  canopy after `_top_layer`, before rain (surface only). Redraws on `scenery.version`.
- `tests/test_scenery.gd` (10 tests) and `tests/fixtures/scenarios/scenery_demo.json`
  (one of each type; used for the still).

Changed from the plan / notes for the next phases:
- No separate "stamp helpers with a mask write": the fill_* functions were refactored onto
  `cells_in_*`, and props claim cells through `add_prop_cells`.
- Known edge: `add_obstacle` / `remove_obstacle` events over prop cells don't touch
  `prop_mask` (a wall added over a prop is drawn as the prop). Fix if a scenario needs it.
- The obstacle shader ignores B for now; M15c can use it for contact shadows / AO around
  props (sample B like R).
- Worn ground / ground cover slots are not created yet (M15b adds ground cover right after
  the ground `ColorRect`; M15e adds worn ground before the scenery base node).
- For M15c: replace `SceneryRenderer`'s placeholder with baked images per prop (keep the two
  pass nodes); `Prop.outline` is what `test_scenery` should compare the footprint against.

### M15b (done)

Done:
- `sim/scenery/ground_map.gd` (`GroundMap`): 8-unit texel grid of weights per material
  (`MATERIALS` = soil, sand, gravel, moss, litter, dry; each cell sums to 1). Built by
  `GroundMap.from_data(scenario["ground"], world_size, seed)`: `"base"` then `"regions"`
  painted in order (circle / rect / polygon / none = whole world; `soft`, `ragged` edge noise,
  `strength`, `noise: {scale, cover, soft}` for patches; the cover fraction is exact, from the
  noise quantile). Noise is `FastNoiseLite` seeded from the scenario seed + region index (never
  `sim.rng`). `weight_at(material, at)`, `weights_at(at)`, `version`.
- `Simulation.ground` (null = no `"ground"` entry = plain soil, exactly as before);
  `ScenarioLoader` builds it after obstacles, before scenery.
- `render/ground.gdshader`: `use_materials`, `material_a` (RGBA8: sand, gravel, moss, litter),
  `material_b` (R8: dry); soil = 1 - the rest. Looks as planned; edges jittered by ~8 units of
  fbm and height-blended (per-material noise, blend width 0.1), so edges are ragged and fairly
  crisp. Soil unchanged except a fix: pebbles were lit on the side *away* from `light_dir`
  (the direction light comes FROM); now lit toward it like walls and ants.
- `render/scenery/ground_cover_renderer.gd` (`GroundCoverRenderer`, MultiMeshInstance2D) +
  `ground_cover.gdshader`: 16 procedurally baked sprites in one 192 px atlas (fragments,
  torn pieces, bark flakes, husks, twiglets, straws, crumbs); static `scatter(ground)` on a
  5-unit jittered grid, density and kind odds per material (`DENSITY`, `KIND_ODDS`); contact
  shadow in the shader from the sprite's own alpha. Own RNG from the ground seed. Added by
  `WorldView` right after the ground rect (only when `sim.ground` exists).
- `tests/test_ground.gd` (9 tests); `tests/fixtures/scenarios/ground_demo.json` (every
  material, a noise-patch region, a shower) for stills.

Changed from the plan / notes for the next phases:
- The material map is uploaded once in `WorldView.setup`; `GroundMap.version` is only watched
  by the cover renderer. Nothing changes the map at runtime yet (no events); if M15e/M15i need
  it (cleared discs), re-upload the textures when `version` changes.
- Rain: `rain.gdshader` unchanged; wet sand turns a flat grey-brown and moss darkens, both
  still readable. A multiplicative wet darkening would keep sand's hue better if wanted later.
- For M15c (rocks near moss): read `sim.ground.weight_at("moss", at)` when baking, or bind the
  same `material_a` texture (world UV = position / world_size) in a prop shader.
- Existing scenarios have no `"ground"`, so they look as before (and hash as before).

### M15c (done)

Done:
- `RockProp`: lumpy ellipse as before, plus a look `detail` (`half`, `height`, `stone` granite /
  sandstone / basalt, `lichen`, optional `moss`). `LogProp`: `detail.axes` (trunk + 0-2 side
  stubs, `"stubs"` param; each `{points, widths}`), `height`, `peel`, `tint`; footprint is now
  `{"shape": "multi", "parts": [...]}`: a quad per segment (flat, tapered ends) and a disc at each
  bend, for trunk and stubs, so it matches the drawn log (the old full-width polyline did not).
- `PropType`: footprint shapes `rect` and `multi`; static `shape_cells`, `footprint_contains`
  (same membership rule as the cells: cell centre inside; polylines use width/2 plus the
  half-cell slack of `World._stamp`), `footprint_bounds`, `obstacle_footprint`. `Prop.detail`
  (type-specific look geometry); `Prop.contains` also checks the footprint (log stubs);
  `Scenery` bounds include the footprint.
- Wall looks: `ScenarioEvents.place_obstacle(sim, ob)` (used by the loader and the
  `add_obstacle` event) adds a rock prop `{"type": "rock", "wall": ob, ...}` for walls with
  `"look": "rock"`; `PropType.stamp` then calls the new `World.mark_prop_cells` (counts WALL cells
  in `prop_mask`, obstacles untouched, so hashes are unchanged); `Scenery.remove` of such a
  prop keeps the wall (`remove_prop_cells(cells, false)`). `World.cells_in_rect` = fill_rect's cells.
- `render/scenery/prop_baker.gd` (`PropBaker`): `bake(prop, painter, cell_size, ground)` ->
  body image (RES 2 px/unit, mipmapped) + shadow image (1 px/unit) and their world rects.
  `rasterize()` gives a `PropBaker.Canvas` (coverage with a 1-unit noise wobble and
  supersampled edges, chamfer `depth` inside, `rgb`, optional per-pixel `heights`); the painter
  fills it; the shadow is cast from the heights along `-LIGHT_DIR` (length 0.75 x height),
  blurred, plus a contact ring. Painter helpers: `noise`, `cells` (Voronoi), `hash01`, `light3`.
- Painters are registered as renderers `"prop:rock"` (`RockLook`) and `"prop:log"` (`LogLook`) in
  `CoreRenderers`. `SceneryRenderer` bakes new props when `scenery.version` changes (cached by
  prop id), draws all shadows then all bodies; props without a painter keep the placeholder.
- Tests (`tests/test_scenery.gd`, +6): drawn body vs blocked cells agree within one cell for
  rocks, logs with stubs and every wall-look shape; wall looks keep cells, RNG and state hash;
  bakes are deterministic. Fixture `tests/fixtures/scenarios/rocks_logs_demo.json` for stills.

Changed from the plan / notes for the next phases:
- The obstacle shader still ignores B: baked shadows do the contact shadow/AO.
- `"look"` supports `"rock"` only (a warning otherwise); a log look on polylines would need
  capsule ends. `remove_obstacle` over a dressed wall frees the cells but leaves `prop_mask`
  set (drawn as rock until the prop is removed) - same known edge as M15a.
- Baking is GDScript per pixel: ~0.2 s for a 50-unit rock, ~0.7 s for a 300 x 30 diagonal log
  (its whole bounding box is rasterized). Fine for tens of props; for M15h's scatter (hundreds)
  either keep blocking props few/small, rasterize only near the footprint, or bake lazily over
  frames. Plants (M15d) should bake smaller images.
- For M15d: a plant painter is a `"prop:plant"` renderer with `paint(canvas, prop, ground)`; the
  canvas covers only the footprint (stem), so the canopy needs its own images (add a second
  bake entry point in `PropBaker`, e.g. `bake_image(size, fn)`, reusing `noise`/`light3`). The
  base pass already draws shadows first; the canopy shadow can be drawn by the canopy node.

### M15d (done)

Done:
- `PlantProp` builds blade geometry per kind into `prop.detail`: `kind`, `reach`, `height` (stem
  crown) and `blades`, a list of `{style, points (SEGMENTS + 1 = 9 spine points, base to tip),
  widths, heights (above ground), tint, phase, teeth}` drawn in order (lowest first). Styles
  (`PlantProp.Style`): GRASS, BROAD, LOBE, PINNA, STALK. Kinds: `rosette` (two whorls; lobed
  dandelion-like or broad plantain-like, round-tipped), `clover` (stalks + three heart lobes,
  lobes share their stalk's sway phase), `fern` (rachis + pinna pairs, shared phase),
  `seedling`, `grass` (tight tuft, 16-28 blades, ~30% bent at a kink and falling, some straw).
  Per-kind defaults in `PlantProp.DEFAULTS` (radius, stem, blade count range). `prop.canopy` is
  the convex hull of every blade. Footprint unchanged: one stem circle.
- `render/scenery/canopy_renderer.gd` (`CanopyRenderer`, added by `WorldView` after the canopy
  placeholder pass): `build_mesh(props, shadow)` makes one ArrayMesh of all blades (UV across /
  along, COLOR tint, CUSTOM0 = plant centre, phase, sway per distance^2; CUSTOM1 = style, teeth,
  length, light side). The shadow mesh is the same blades widened and shifted by
  `-LIGHT_DIR * 0.75 * height`, drawn first. Rebuilt when `scenery.version` changes.
  `canopy.gdshader`: shading and sway as planned; `wind` uniform eased up by up to +1.6 while
  it rains. `clear_spots(sim, follow_ant)`: followed ant (from the Camera2D's `follow_ant`),
  entrances (nest radius + 22), food (45), max 16; canopy and shadow alpha drop to 0.18 inside.
- `render/scenery/plant_look.gd` (`PlantLook`, `"prop:plant"` / `"prop:grass"`): the stem crown
  baked by `PropBaker` like rocks (ridged blade bases, pale sheaths, dark soil line).
  `SceneryRenderer`'s canopy pass skips props with `detail.blades`.
- Tests: `tests/test_plants.gd` (7: kinds, counts, determinism, only the stem blocks, mesh and
  shadow geometry, clear spots, canopy-only plants keep the run's hash) and
  `test_scenery::test_plant_stem_drawn_where_it_blocks`. Fixtures
  `tests/fixtures/scenarios/plants_demo.json` (every kind, stills) and `plants_bench.json`
  (202 plants, frame probe).
- Frame probe (3,000 ants, native): with plants GPU 10.6 ms, render CPU 0.5 ms, ~800 draw calls;
  without 6.8-10.3 ms, 0.3 ms, ~520. 60 fps both. In the README.

Changed from the plan / notes for the next phases:
- No baked canopy images or atlases: the canopy is a vector mesh with procedural shading, so
  it is crisp at any zoom, costs no bake time, and sways per blade in the vertex shader (the
  plan's "per-blade vertex offset"). The "canopy shadow image" is a second mesh.
- Draw calls: each baked prop (rock, log, stem crown) is 2 draw calls (own textures). Fine at
  ~200 props; for M15h's scatter consider packing baked bodies/shadows into an atlas.
- Sway uses shader `TIME` (video time under Movie Maker, so deterministic in recordings, and
  independent of the sim speed schedule).
- Clear spots use the nest's current `entrances()`; M15e's entrance renderer may want the same
  list (and `clears_plants` could scale canopy alpha by distance the same way).
- For M15h (presets): kinds and sensible radii: grass 30-65, rosette 35-70, clover 35-50, fern
  60-100 (stem 6), seedling 10-18 (stem 2). Stems block, so dense scatter needs the
  connectivity check; `"stem": 0` gives canopy-only plants for existing scenarios (M15i).
