# M18: Performance, cleanup and bug fixing

Goal: a faster, leaner, more correct codebase, with no new features:

1. **Performance**: the simulation, the renderers, scenario loading and the test suite all
   get measurably faster, measured the same way before and after each change.
2. **Cleanup**: dead code, stale helpers and unused files are removed; GDScript and C++
   compiler warnings are made clean and kept clean.
3. **Bugs**: a systematic hunt (invariant audits over whole scenario runs, smoke runs of
   every tool and scenario, malformed input, warnings) finds bugs, which are written down
   with a repro and fixed with a regression test each.

Status: M18a done (baseline and profiling tools). Next: M18b (dead code and warnings).
M18f takes over M15l's "founding frame budget"; M15l's PNG finals stay open in M15 (better
recorded after M18f, which makes them cheaper).

## Where things stand (before M18)

Numbers from the README "Performance" section and the M15/M16 plans (same laptop: Intel
UHD integrated GPU, 2.3 GHz, 16 threads, Godot 4.7 editor build):

- Simulation, native kernel: `bench.gd basic_forage 600 3000` 2.5 ms/tick; `nest_bench.json
  900` 9.1 ms/tick (surface 2.2, underground 3.7); `colony_founding` whole run 30 min
  headless, 13–15 ms/tick at the 1,600-agent cap. What is still GDScript: species states
  (leafcutter gardening, nursing, cutting, carrying down) cost 5–12 µs per ant per tick
  against well under 1 µs for the native core states; in `colony_founding` most
  underground agents are in them, so it gains only ~1.7× from the kernel.
- Rendering: fine at 3,000 ants in single-layer scenes (GPU 7–13 ms, ≤ 900 draw calls).
  `colony_founding` late in the split layout (`--at=62 --probe=1`, ~1,400 agents): 11–14 fps,
  **~14,000 draw calls and ~35–50 ms of renderers' `_process`** per frame. This was M15l's
  open "founding frame budget" and was never started. `frame_probe.gd` only measures the
  root viewport, not the split layout's SubViewports.
  Likely contributors (not yet measured): `ItemRenderer` keeps one `ImageTexture` per item
  (no batching: a draw call per item) and each of its three passes, per layer, per view,
  walks every item in `sim.items` every frame; the GROUND pass redraws whenever
  `items_version` changes (every tick in a busy nest); midden chunks, spoil heap crumbs,
  baked stem crowns (2 draw calls each), garden and soil views.
- Loading: a scatter takes 0.3–0.4 s, rocks and logs bake at 0.1–0.7 s each
  (`meadow_forage`: scatters 1.1 s); editor full rebuilds 0.3–1.7 s (M16f log).
- Test suite: 587 tests, all passing at planning time (with the uncommitted editor changes),
  **387 s wall on 8 processes, ~2,470 s of CPU** (`.godot/test_times.txt`). The wall time is
  bounded by single long tests:
  `test_highways::test_extra_entrances_open_and_are_used` 263 s,
  `test_nurseries::test_leafcutter_nest_gets_nurseries` 166 s, then
  `test_native_matches_gdscript_nest_bench` 64 s and a dozen at 40–60 s. By file:
  test_native 349 s, test_highways 306, test_nurseries 263, test_granary_nest 175,
  test_terrain 133, test_alates 111, test_phorids 100, test_editor_rebuild 99.
- Dead code found by a reference scan at planning time (a name that appears nowhere but
  its definition, across `.gd`, `.tscn`, `.cpp`, `.sh`, `.json`):
  `EditorDefaults._pt`, `FieldSpec.is_container`, `SplitLayout.screen_to_nest`,
  `ScenarioPlayer.set_split`, `NavGrid.has_target`, `TrafficMap.at_cell`,
  `TrafficMap.sum_along`, `Travel.portal_between`, `World.clear_all`,
  `GardenGrid.add_chamber` (callers use `add_chamber_where`), `LeafSource._tissue`,
  `RecordJob.STAGE_NAMES`. Used only by tests (review, keep only real test API):
  `EditorOutline.section_of`, `ScenarioSchema.unknown_paths` / `all_key_names`,
  `CameraDirector.followed_brood` / `carried_ant`, `OutputFrame.is_landscape`,
  `NavGrid.field_id`, `Brood.lay_tick` / `emerge_tick`, `Midden.decayed_mass`,
  `NestChambers.has_loop`, `Registry.get_behaviour`, `SimConfig.grid_size`,
  `Simulation.world_of`, `World.is_prop_cell`, `PhoridFlies.active_count`. No whole file is
  unreferenced; every probe and tool is still documented in the README.
- Warnings: `project.godot` only raises `untyped_declaration` to an error; the other
  GDScript warnings (unused variables and parameters, shadowing, unreachable code, integer
  division, narrowing conversions, discarded return values) are at Godot's defaults and
  never looked at in headless runs. `native/` builds without `-Wall -Wextra`.
- Known bugs carried over:
  - M16i: a colony with an unregistered species makes `ScenarioLoader`/`Simulation` assert
    (`simulation.gd:310`). The same pattern guards unknown nest types, food and item types,
    channels, params and states (about 20 `assert`s on scenario data in `sim/`). Asserts
    are stripped in release builds, so there it is a null dereference instead.
  - M17: a queen-only founding (no minims) stalls: one worker, brood stuck. `leafcutter_life`
    works round it with four minims.

## Design decisions (apply to every phase)

1. **Measure first, the same way before and after.** Every performance change states its
   before/after numbers from the M18a harness (same scenario, seed, ticks, machine;
   A/B runs side by side, never two suites or long benches alongside something else).
   A change that doesn't measurably help is reverted, not kept "just in case".
2. **Cleanup and performance changes don't change behaviour.** They keep
   `SINGLE_LAYER_HASHES` and native parity as they are; a hash that moves in a
   cleanup/perf phase is a bug in that phase. Rendering changes are checked with before/after
   stills at the same `--at` (identical, or differences explained).
3. **Bug fixes that change behaviour are grouped** (M18e), each with a regression test that
   failed before the fix, and the hash re-recording explained in the commit. Fixes in the
   GDScript hot path are mirrored in `ant_kernel.cpp` (parity).
4. **Core stays species-agnostic.** Speeding up species states happens in
   `species/<name>/`; anything moved into the native kernel must be generic (the kernel is
   core), otherwise it stays GDScript and is optimised there.
5. **Tests keep their coverage.** Shortening a slow test means reaching the same state
   faster (smaller fixture, lower thresholds checked over several seeds, shared setup), not
   dropping checks. A test that is split must still check everything the original did.
6. **Dead code is deleted, not commented out**; git history keeps it. Test-only helpers stay
   only if they are a deliberate inspection API that several tests use.

## Phases

### M18a: measurement baseline and profiling tools

Goal: one set of repeatable measurements that later phases compare against, and tools that
say *where* the time goes (by renderer, by behaviour state, by load stage).

- `tests/frame_probe.gd`: measure render CPU/GPU time over every viewport (the split
  layout's SubViewports too: `viewport_set_measure_render_time` and
  `viewport_get_measured_render_time_*` per SubViewport RID), and time each renderer's
  `_process`/`_draw` (a small opt-in timer the renderers call only when the probe is on, so
  normal runs pay nothing). Print the top renderers by ms and the draw calls per view.
- `tests/bench.gd`: `--by-state` prints µs per ant per tick for each behaviour state (native
  and GDScript), and the nest's own update (gardens, brood, roles, chambers) split by part.
  A `--from=<seconds>` option to fast-forward before timing (to bench late-colony states
  without the 30 min run, e.g. `colony_founding` from 5,000 s).
- Load timing: print `ScenarioLoader`'s staged build (M16f) per stage, including each
  scatter and prop bake (`--load-times` on bench).
- `tools/test.sh`: print the wall time and the critical path (the slowest test per
  process) at the end.
- Record the **baseline table** in this plan: bench `basic_forage 600 3000`,
  `nest_bench.json 900`, `meadow_forage 3600`, `colony_founding` (from 5,000 s, 900 ticks,
  by state), `leafcutter_life` (by state); frame probe on `colony_founding --at=62`,
  `leafcutter_life` at its busiest trunk-trail shot, `meadow_forage --at=34`; load times of
  `meadow_forage`, `leafcutter_life`, `colony_founding`; suite wall time and CPU total.
- Verify: `tests/test_bench_tools.gd` (probe timer off costs nothing / isn't called;
  `--by-state` totals match the unsplit number within 10%). Full suite; hashes unchanged.
- Hands on: the ranked hotspot lists (render, sim by state, load, tests) that M18f–M18i
  work from, in this plan's M18a section.

#### M18a: done

What was built:

- `Profiler` (`sim/profiler.gd`): static opt-in timers, `var t := Profiler.start()` …
  `Profiler.stop(key, t)`; while `Profiler.on` is false, start() returns 0 and stop()
  returns at once. Used only round per-tick/per-frame code: `Simulation.begin_step`
  sections (`step.*`, `nest.update`, `nest.update_underground`, `nest.update_refuse`),
  `ColonyNest._update_colony` parts (`nest.update: brood / alates / roles and planning /
  chambers dug`), `FungusNest` gardens, `GranaryNest` granaries, `ScenarioLoader` stages
  (`load: *`, one key per scatter), and every renderer's `_process`/`_draw` under `render/`
  and `species/*/` (`Class._process`, `Class._draw`, with the pass for ItemRenderer,
  SceneryRenderer, WingRenderer; the carried/riders instances of Brood/AntRenderer).
  Not covered: helpers drawn through signals (`SpoilHeapRenderer._draw_base`,
  `FungusNestRenderer._draw_mound`, `MiddenRenderer.View._draw_ground`,
  `SplitLayout._draw_ring/_draw_seam`).
- Per-state timing of ant updates is its own code path, not Profiler (it is per ant):
  `Simulation.set_state_profiling(true)` sends GDScript updates through `_tick_profiled()`
  (one bool check per GDScript ant update when off) and switches on the kernel's
  `set_state_profiling` (ns timers round `tick_ant`, per state id; an update handed back to
  GDScript adds its time but is counted where it finishes). `take_state_profile()` merges
  both; index `STATE_TRANSIT` (256) is portal transits. Kernel and GDScript give identical
  counts per state (tested).
- `bench.gd`: `--by-state` (states by cost, then Profiler keys), `--from=<s>` (untimed
  fast-forward), `--load-times` (stages, plus every prop baked with its painter as
  SceneryRenderer would, `bake: <type>`; registers CoreRenderers for that).
- `frame_probe.gd`: per-viewport render CPU/GPU (root and every SubViewport; the split
  layout's are now named `SurfaceViewport`/`NestViewport`), top 12 Profiler keys per frame;
  `--probe=N` (N > 1) quits after N reports. Godot's per-viewport render info reads 0 draw
  calls for 2D, so draw calls stay the global monitor (whole frame).
- `tools/test.sh`: ends with the total test time and per process its total and slowest
  test. Fixed on the way: tests with 0 ms recorded times tied at zero load in the balancer
  and could leave a process with no tests (its `--tests-file` missing → exit 1); they now
  count as 1 ms.
- `tests/test_bench_tools.gd` (6 tests): Profiler off records nothing (load, nest,
  states); on, it records load and nest parts once per tick; state profiling keeps the hash
  (single-layer and layered); kernel and GDScript count the same updates per state; the
  states' times are ≤ the ants' total and ≥ 60% of it. Changed from the plan: "totals
  match within 10%" is not testable in a parallel suite; the states measure 84–86% of the
  `ants` time in every bench (the rest is the loop, `kernel.run` calls and `native.sync`),
  and the by-state run costs ~1–3% more than a plain one (nest_bench 11.85 vs 11.86 ms).
- Hashes and parity unchanged; full suite 607 passed.

**Baseline** (dev laptop, native kernel, one run at a time, 2026-09-30). Bench numbers are
ms per tick; frame numbers per frame, windowed at the default window size.

| Case | Result |
|---|---|
| `bench.gd basic_forage 600 3000` | 3.08 ms: ants 2.39, pheromones 0.56, nests 0.10 |
| `bench.gd nest_bench.json 900` | 11.86 ms: ants 8.99 (surface 2.49, 2.9 µs/ant; underground 5.41, 8.7 µs/ant), nests 1.76, pheromones 0.95; 1,490 agents |
| `bench.gd meadow_forage 3600` | 4.52 ms: pheromones 3.65 (4 channels), ants 0.71, nests 0.09; 585 ants |
| `bench.gd colony_founding 900 0 -1 --from=5000 --by-state` | 23.3 ms: ants 17.9 (surface 6.1, 6.8 µs/ant; underground 10.0, 14.2 µs/ant), pheromones 3.4, nests 1.6; 1,600 agents + 504 abstract |
| `bench.gd leafcutter_life 1800 0 -1 --from=2100 --by-state` (trunk trail) | 5.19 ms: ants 2.48, pheromones 2.22, nests 0.31; 250 ants |
| Frame `meadow_forage --at=34` | 60 fps; root GPU 10.0 ms, render CPU 0.6; 707 draw calls; renderers ~4 ms (ItemRenderer carried shadow 1.0, carried 0.9, pheromones 0.7, ground items 0.5) |
| Frame `leafcutter_life --at=141` (trunk trail, normal layout) | 49 fps; GPU 11.9 ms; 163 draw calls; renderers ~12 ms: WingRenderer WINGS 5.5 (!), GardenRenderer 2.2, PhoridRenderer._draw 1.3, carried items 1.4 |
| Frame `colony_founding --at=62 --layout=split` | 7 fps; sim 77.6 ms; **GPU SurfaceViewport 79.8 ms, NestViewport 69.3 ms** (root 0.4), SurfaceViewport CPU 10.6; 14,758 draw calls; renderers ~34 ms (AntRenderer 6.6, carried shadow 5.4, carried 5.3, GardenRenderer 5.3, Midden 2.0, Soil 1.8) |
| Frame `colony_founding --at=62 --layout=normal` | 10 fps; sim 72.4 ms; GPU 26.0 ms, render CPU 8.8; 14,387 draw calls; renderers ~10 ms (AntRenderer 3.3, Midden 1.9, carried 3.1) |
| Load `meadow_forage` (`--load-times`) | build 1.46 s (scatters 0.48 + 0.37, registry 0.48, ground 0.12) + bakes 5.7 s (2 logs 1.47 s **each**, 15 rocks 0.11 s each, 146 plants 7.8 ms each); first tick 37 ms |
| Load `leafcutter_life` | build 1.75 s (colonies 0.81, registry 0.45, scatters 0.24 + 0.21); bakes ~0; first tick 73 ms |
| Load `colony_founding` | build 2.09 s (colonies 0.78, registry 0.44, scatters 0.34 + 0.24 + 0.23) + bakes 1.3 s (7 rocks 0.11 s each, 173 plants); first tick 97 ms |
| Suite (`tools/test.sh`, 8 processes) | 607 tests, **422 s wall**, 2,268 s test time; processes 275–297 s each, so ~125 s of the wall is import, listing and process start-up/load, not tests |

Seeking is slow: `--at=62` in `colony_founding` took 37–45 min windowed (the fast-forward
runs the whole sim to 6,033 s), `leafcutter_life --at=141` 2.7 min, `meadow_forage
--at=34` 2.2 min. Registry creation (~0.45 s) is paid by every load (and every test file).

**Ranked hotspots** (for the phases that follow):

- Render (M18f): (1) GPU of the split layout's SubViewports in late `colony_founding`,
  ~150 ms together, with ~14,700 draw calls: the dominant cost, invisible to the old probe;
  (2) AntRenderer._process at 1,600 ants (6.6 ms split, both views); (3) ItemRenderer
  CARRIED + CARRIED_SHADOW _draw (10.7 ms split; ~1.9 ms even in meadow_forage);
  (4) GardenRenderer._process (5.3 ms founding, 2.2 ms leafcutter_life); (5) WingRenderer
  WINGS _draw 5.5 ms in the leafcutter_life trunk-trail shot (alates in the nest; check
  why it costs that much); (6) MiddenRenderer._process ~2 ms, SoilRenderer 1.8 ms,
  PhoridRenderer._draw 1.3 ms.
- Sim by state (M18g), late `colony_founding` (15.5 ms of 17.9 ms ants): garden 5.0 ms
  (420 ants, 12.0 µs each), **carry_spent 4.9 ms (249 ants, 19.6 µs each)**, cut_leaf 1.1,
  patrol_trail 0.9 (7.1 µs), nurse 0.9 (16.3 µs), dig 0.7 (21.8 µs), go_to_food 0.5; native
  core states ≤ 1.5 µs. Nest: gardens 1.1 ms of nest.update 1.3. Pheromones 3.4 ms (not a
  species state; worth a look in M18g). nest_bench: garden 2.9, cut_leaf 1.1, go_up 0.9,
  nurse 0.6; step.nav_grid 0.8 ms. leafcutter_life (trunk trail): nurse 0.56, cut_leaf
  0.24, nest_role 0.19 (16 µs), carry_down, garden, go_up ~0.18 each; pheromones 2.2 of
  5.2 ms. Every GDScript species state costs 7–27 µs per update.
- Load (M18h, worth doing): (1) log bakes 1.47 s each, rock bakes 0.11 s each, plant bakes
  3–8 ms each (meadow_forage 5.7 s of bakes); (2) colony setup 0.8 s in the leafcutter
  scenarios (underground preparation; measure inside `add_colony`); (3) registry 0.45 s per
  load; (4) scatters 0.2–0.5 s each; (5) first tick 40–100 ms.
- Tests (M18i): the critical path is still
  `test_highways::test_extra_entrances_open_and_are_used` (232 s) and
  `test_nurseries::test_leafcutter_nest_gets_nurseries` (154 s); then
  `test_native_matches_gdscript_nest_bench` 58, `test_no_nurseries_below_the_threshold` 55,
  `test_fungus_farm_colony_grows` 46. ~125 s of the 422 s wall is outside tests (import,
  listing, per-process start-up): look there too.

Bug candidates found on the way (for M18c): `bench.gd` (and `ScenarioLoader.load_simulation`)
with a scenario path that doesn't exist reports an error and then runs an empty scenario
instead of failing; every headless tool exits with "ObjectDB instances leaked" / "Pages in
use exist at exit in PagedAllocator" (the old bench did too);
`test_ground_swatches::test_image_speed` is a wall-clock threshold (< 100 ms, ~25 ms alone)
that failed once at 104 ms in a full suite run on a busy machine (the second M18a run, 562 s
wall, every test ~50% slower; the first run on the same sim code passed 607/607): flaky.

### M18b: dead code and warnings

Goal: remove what nothing uses, and turn on the warnings that catch it, so it stays clean.

- Delete the unreferenced functions and constant listed above (re-run the scan first: it is
  a text search, so check each for `call`/`has_method`/string dispatch, signals connected by
  name in `.tscn` files, and schema/registry lookups by name before deleting). Review the
  test-only list: delete helpers that exist only to poke internals from one test (and
  rewrite that test against public state), keep inspection API used by several tests.
- Orphan `.uid` files (a `.uid` without its script), unused shader uniforms, unused
  `@export`s in `.tres`, stale `.gitignore` entries, README lines about removed things.
- GDScript warnings: set, in `project.godot`, `unused_variable`, `unused_local_constant`,
  `unused_private_class_variable`, `unused_parameter`, `unused_signal`, `shadowed_variable`,
  `shadowed_variable_base_class`, `unreachable_code`, `unreachable_pattern`,
  `standalone_expression`, `integer_division`, `narrowing_conversion`,
  `incompatible_ternary`, `confusable_local_declaration` to warn, list them all from an
  `--import` run, fix them (prefix intentionally unused parameters with `_`), then raise the
  ones that come out clean to errors so tests fail on new ones. Warnings that look like
  real bugs (integer division, shadowing, narrowing in sim code) are **not** fixed here if the
  fix changes behaviour: they go to the M18c bug list.
- C++: build with `-Wall -Wextra -Wshadow -Wconversion` (or the MinGW equivalents), fix
  what is harmless, list what could be a bug for M18c; keep `-Wall -Wextra` on.
- Verify: full suite (hashes and parity unchanged), `validate_scenarios.gd`, the editor
  opens (`tools/editor.sh --screenshot=`), a still of `leafcutter_life` identical to before.
- Hands on: a count of what was removed (functions, lines), which warnings are now errors,
  and the warning-found bug candidates for M18c.

### M18c: bug hunt (audit)

Goal: find bugs systematically and write each down with a repro; fix only the trivial,
behaviour-neutral ones here.

- **Invariant audit over whole runs**: a debug script (`tests/_audit.gd`, deleted at the end
  of the phase) runs every shipped scenario to its end headless, native and GDScript,
  checking every N ticks: no ant in a wall (`SimChecks.ants_in_obstacles`), food mass
  conserved (`SimChecks.mass_error`), no NaN/inf positions or headings, packed arrays the
  same size, every carried item's carrier alive and carrying it (and vice versa), transit
  and portal state consistent, pheromone values finite and ≥ 0, brood counts consistent
  with the colony's totals, no item on an unreachable/blocked cell, agents under
  `max_agents`. Long runs go in the background, one at a time.
- **Smoke runs**: every probe and tool with short arguments (bench, nest/story/timeline/
  fingerprint/midden/scatter probes, `validate_scenarios.gd`, `record.sh` 2 s AVI,
  `screenshot.sh`, `stills.sh`, `editor.sh --screenshot`), and every shipped scenario in
  `main.tscn` at a few `--at` points (start, middle, end, each layout mode): any `SCRIPT
  ERROR`, `ERROR:` not expected, or crash is a bug.
- **Malformed input**: load each shipped scenario with keys removed, wrong types and unknown
  ids (species, nest type, food and item types, channels, states, params) through
  `ScenarioLoader` and through the editor preview: the loader must report and skip, never
  assert or crash (the M16i bug; the same for release builds, where asserts vanish).
- **Editor round trips**: open, save and reopen every shipped scenario (JSON identical, same
  hash); undo/redo of each edit kind back to the original document.
- **Reading pass**: grid edges and world borders (off-by-one on the last cell), float
  equality on times, `int`/`float` mixing, iteration over a Dictionary or array while it
  is modified, signal connections that never disconnect (editor rebuilds, play preview),
  renderers that keep state after a sim is rebuilt, the M18b warning candidates.
- Known bugs go on the list too: loader asserts on scenario data, queen-only founding stall.
- Output: a **bug list** in this plan's M18c section, one line each: id (B1, B2, ...),
  severity (crash / wrong result / cosmetic), repro (scenario, seed, time or command),
  suspected cause, whether a fix changes hashes, and the phase that fixes it (M18d or M18e).
- Verify: full suite; trivial fixes each with a test.
- Hands on: the bug list, split into behaviour-neutral (M18d) and behaviour-changing (M18e).

### M18d: fix behaviour-neutral bugs

Goal: fix every M18c bug that doesn't change a sim hash (crashes, loader and editor bugs,
render glitches, tool failures, error handling).

- Scenario data errors: `ScenarioLoader` checks species, nest type, food/item types,
  channels, params and states against the `Registry` before building, reports each with
  `push_error` naming the JSON path (matching `ScenarioValidator`'s messages), and skips the
  item; `assert`s stay only for programming errors inside the sim.
- One regression test per bug, named after it (`test_b3_...`), that failed before the fix.
- Verify: full suite, hashes unchanged, the M18c smoke runs that failed now pass.
- Hands on: the bug list with each fixed item marked, and what remains for M18e.

### M18e: fix behaviour-changing bugs

Goal: fix the M18c bugs whose fixes change simulation results (e.g. the queen-only founding
stall, anything the invariant audit found in the hot path).

- Each fix mirrored in `ant_kernel.cpp` when it touches the kernel's paths; parity tests
  pass for every scenario.
- Re-record `SINGLE_LAYER_HASHES` once, at the end of the phase, and list in the commit which
  fix moved which hash. Check test thresholds that depend on foraging over several seeds.
- Re-run the M18c invariant audit on the scenarios the fixes touch; `nest_probe.gd` over the
  whole 7200 s `colony_founding` if nest or digging code changed (background, alone),
  compared with the baseline run (population and pace within the seed spread).
- Verify: full suite; AVI drafts of the scenarios whose behaviour visibly changed (checked
  for resolution, fps and duration) for the user to look at.
- Hands on: the final bug list (all fixed or explicitly deferred with a reason).

### M18f: render frame budget

Goal: `colony_founding` late in the split layout runs at ≥ 30 fps interactively (sim
excluded) and the recording's render share drops; single-layer scenes stay at 60 fps with
lower GPU time. Work from M18a's ranked renderer list; expected candidates:

- `ItemRenderer`: one shared texture atlas (or per-type textures) instead of an
  `ImageTexture` per item, so items batch; build the carried list once per frame per layer
  and share it across the CARRIED and CARRIED_SHADOW passes and both views; keep ground
  items in a cached canvas (or a MultiMesh) redrawn only for the items that changed, not
  every `items_version` bump.
- Midden chunks, spoil heap crumbs, stem crowns: bake static parts into one texture or a
  MultiMesh; redraw on change only.
- Renderers of views that aren't visible (a split part scrolled away or a layout mode not
  shown) skip `_process`.
- Verify: frame probe before/after (draw calls and ms per renderer, all viewports); before/
  after stills of `colony_founding` (`--at=62`, both layouts), `leafcutter_life` (three
  shots), `meadow_forage --at=34` identical or differing only where explained; full suite.
- Hands on: the new frame numbers for the README.

### M18g: simulation CPU

Goal: cut the GDScript species-state cost that dominates late `colony_founding` and
`leafcutter_life`, without changing hashes. Work from M18a's per-state table; expected:

- The top species states (gardening, nursing, cutting, carrying down, patrol): hoist
  per-tick lookups (params dictionaries, `caste_of`, `Registry` lookups) into cached typed
  fields, avoid per-tick allocations (temporary arrays, `Vector2` arrays, lambdas),
  replace linear scans (nearest chamber, nearest item, nearest brood) with the existing
  grids or cached indices. Results must be bit-identical (same float order).
- Nest updates (`GardenGrid` slices, `Brood`, `NestChambers`, `NavGrid` field updates) by
  the same method.
- Only if a state is generic (core) and still costly: move it to the kernel (parity).
- Verify: bench by state before/after on the M18a cases; hashes and parity unchanged; full
  suite; `nest_probe.gd` whole run A/B side by side (background, alone) for the ms/tick
  over the run.
- Hands on: the new sim numbers for the README.

### M18h: loading and editor rebuilds

Goal: shorter time to first frame and faster editor rebuilds, from M18a's load table.

- Cache baked props (rocks, logs, stem crowns) by their bake inputs for the session (the
  editor rebuilds and `--at` seeks bake the same props repeatedly); avoid rebaking textures
  whose inputs didn't change; look at the ground and soil texture builds.
- Only if M18a shows load time is worth it; otherwise this phase is skipped and says so.
- Verify: load table and M16f editor rebuild times before/after; `test_editor_rebuild`
  (partial = full) still passes; stills identical; full suite.

### M18i: test suite wall time

Goal: the full suite in under ~2.5 min on 8 processes (from 387 s), with the same coverage.

- Benefit first from M18g, then re-rank by `.godot/test_times.txt`.
- The critical path: `test_extra_entrances_open_and_are_used` (263 s: runs `highway_demo`
  until the second entrance opens, ~460 s of digging) and
  `test_leafcutter_nest_gets_nurseries` (166 s): reach the state faster (a fixture with a
  higher population or faster dig parameters, checked over several seeds), or split the
  checks so the setup runs in parallel.
- Tests that build the same scenario and run it the same way in one file: share the run
  where tests are independent of each other's order (a per-process cache keyed by fixture
  and ticks), keeping tests independent as CLAUDE.md requires.
- `tools/test.sh`: schedule the longest tests first (it already balances by last times;
  check the critical path is started first in its process).
- Verify: full suite passes three times in a row (no flakiness introduced); wall time and CPU
  total before/after in this plan.

### M18j: docs and final numbers

Goal: the README and CLAUDE.md say what is now true.

- README "Performance": re-measure every row with the M18a harness and replace the numbers
  (keep the history rows where they explain a decision); the frame probe and bench options
  added in M18a under "Tools".
- CLAUDE.md: new commands or options, the warnings-as-errors rule, suite time.
- This plan: final before/after table, the progress log, Status "M18 complete".
- Verify: full suite; every command in README "Tools" and CLAUDE.md "Commands" runs.

## Open questions (decide before the phase that needs them)

- M18b: raise the clean GDScript warnings to errors (tests fail on new ones), or leave them
  as warnings and check them in a test? Recommendation: errors; it's the only way they
  stay clean in headless runs, where nobody reads warnings.
- M18c: the audit of every shipped scenario to its end, both ways, is several hours of
  CPU. Recommendation: native for all, GDScript only for the shorter scenarios (parity tests
  already compare the two).
- M18e: fix the queen-only founding stall or document it as a limitation?
  Recommendation: fix it if the cause is a bug (brood care needs a second worker); if it
  needs new behaviour (the queen tending her own first brood), defer to a later milestone.
- M18g: move generic parts of species states into the native kernel? Recommendation: no,
  unless the per-state table shows a generic sub-step (e.g. nav-field following
  underground) dominating; the parity burden grows with every state in C++.
- Keep the GDScript ant path (`--no-native`)? It doubles the hot path to maintain, but the
  parity tests are one of the best bug detectors and it runs without a compiler.
  Recommendation: keep.

## Progress log

- 2026-09-30 M18a: Profiler, per-state ant timing (kernel + GDScript), bench `--by-state`
  / `--from` / `--load-times`, per-viewport frame probe with renderer timers, test.sh
  critical path; baseline table and ranked hotspots in the M18a section. Biggest finds:
  the split layout's SubViewport GPU time (~150 ms per frame late in colony_founding), log
  bakes of 1.5 s each, carry_spent at 19.6 µs per ant.
