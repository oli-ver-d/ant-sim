# M18: Cleanup and refactor

Goal: remove dead code, fix the latent errors and inconsistencies found in a code review
(September 2026), and fold duplicated code into shared helpers, **without changing what any
existing scenario does**. No new features, no visual changes.

Status: planned, no phase started.

The review was a reading of `sim/`, the behaviours, the nest and digging code, the native
kernel and its wiring, parts of `species/`, `scenes/scenario_player.gd` and `tools/test.sh`.
It could not run Godot, so every finding below must be confirmed against the code (and, for
errors, with a failing test first) before it is fixed. Most of `render/` and `species/` was not
reviewed; M18g has a short sweep for them.

## Design decisions (apply to every phase)

1. **Hashes stay the same.** Every existing scenario must keep its state hash, GDScript and
   native (`tests/test_layers.gd`, `tests/test_native.gd`, determinism tests). A phase that
   finds a fix would change a hash stops and records it in the progress log. The fix then
   either becomes opt-in or is left out, and the user decides. No pinned hash is updated
   without the user agreeing.
2. **No C++ change unless a phase says so.** Only M18f touches `native/`, and only if its
   defaults table needs to reach the kernel. Otherwise the extension needs no rebuild.
3. **Tests first for errors.** Each error fix gets a test that fails before the fix (or, for
   crashes, one that would have hit the crash path). Refactors rely on the existing suite and
   the hash checks.
4. **One phase per session** (see CLAUDE.md). Each ends with the full suite passing, a commit
   `M18x: ...` and this file's progress log updated. `--quick` is not enough.
5. **Where to run it.** Needs a machine with Godot 4.7 (and MinGW for M18f if the kernel
   changes). The cloud container this plan was written in has no Godot.
6. **Core stays species-agnostic** (`tests/test_core_generic.gd`). New shared helpers go in
   `sim/`; leafcutter-only fixes stay in `species/leafcutter/`.

## Findings this milestone covers

Errors (E), dead code (D), refactors (R). Line numbers are from commit `b94eb35`.

| Id | What | Where | Phase |
|---|---|---|---|
| E1 | Queued ant dropped silently when `spawn_ant` returns -1 (sim full); agent cap ignored | `sim/nests/nest_type.gd:195-203` `release_waiting` | b |
| E2 | `dug[rng.randi() % dug.size()]` with no empty check | `sim/nests/colony_nest.gd:596` `spawn_from_pool` | b |
| E3 | Chamber with no garden cells: `_seed_new_garden` takes donor fungus, then indexes past the end; retried on every later dig. `c.cells[0]` also unguarded | `species/leafcutter/fungus_nest.gd:203-219, 538-568` | b |
| E4 | Non-care brood uses `nest.brood_reserve`; the care path uses `nest.reserve()` (overridden by `FungusNest`) | `sim/nests/brood.gd:104,110` | c |
| E5 | `carry_waste` walks to the main entrance; `is_at_nest` accepts any open one | `sim/behaviours/carry_waste.gd:28` | c |
| E6 | `_tick_transit` jumps positions but not heading snapshots (one-frame spin) | `sim/simulation.gd:291-293` | c |
| E7 | `_apply_rain` iterates every past shower every tick | `sim/simulation.gd:905` | c |
| E8 | Ctrl-C trap kills the wrapper subshells, not Godot | `tools/test.sh:91-94` | g |
| D1 | Uncalled: `World.clear_all`, `Travel.portal_between`, `TrafficMap.at_cell`/`sum_along`, `NavGrid.has_target`, `NestChambers.rim_point`/`floor_point`, `GardenGrid.add_chamber`, `LeafSource._tissue`, `SplitLayout.screen_to_nest`, `ScenarioPlayer.set_split`, `Colony.param` | see review | a |
| D2 | Unreachable `if clutter.is_empty()` | `sim/world.gd:197` | a |
| D3 | Stale docs: `SimConfig` header/`get_param` ("merged via get_param()"); `Simulation.change_state` and `Behaviour` say states change only via `tick()` | `sim/sim_config.gd:4,74`, `sim/simulation.gd:473`, `sim/behaviours/behaviour.gd:7` | a |
| R1 | Behaviour param defaults written twice (GDScript behaviours and `NativeAnts.push_colony`) | `sim/native_ants.gd:267-275` + behaviours | f |
| R2 | `carried[i] = -1; item.carrier = -1; destroy_item(...)` repeated; skips rider dismount | `sim/nests/brood_care.gd:88,121`, `species/leafcutter/garden.gd:32,105` | d |
| R3 | "Carry refuse up to a midden" leg duplicated | `sim/behaviours/carry_corpse.gd:39-49`, `carry_spent.gd:21-31` | e |
| R4 | Three `Vector2` parsers, two point-list parsers | `Simulation._vec2`, `ScenarioEvents.vec2/points`, `PropType.params_vec2/params_points` | d |
| R5 | Private functions called across classes | `NestChambers._soil_around`, `NestChambers._taper`, `DigShape._lattice` | d |
| R6 | Two "is the native kernel on" checks | `NativeAnts.available()`, `_static_ok()` | d |
| R7 | "Spawn in a chamber and take a nest role" duplicated | `ColonyNest.spawn_initial`, `spawn_from_pool` | e |

Test-only helpers (`SimConfig.get_param`/`grid_size`, `Registry.get_behaviour`,
`NavGrid.field_id`, `Simulation.world_of`, `World.is_prop_cell`, `NestChambers.has_loop`,
`Brood.lay_tick`/`emerge_tick`) stay, since tests use them. Only their docs are fixed.

## Phases

### M18a: dead code and stale docs

Goal: remove D1 and D2, fix D3. No behaviour change.
- Before deleting each function, grep the whole repo again (including `tests/`, `.tscn`,
  `.tres`, JSON, `Callable`/`call("name")`/`has_method` strings) to confirm it's unused.
- `SimConfig`: header says species values are merged in `Colony.build_params`; `get_param`
  is documented as a lookup helper (tests use it).
- `change_state`/`Behaviour` docs: a tick's return value is the usual way, and nests may also
  switch ants' states (corpses, spawning, freeing callows), only between or inside ticks,
  never by resizing arrays.
- README: remove any mention of the deleted functions.
Files: `sim/world.gd`, `sim/travel.gd`, `sim/traffic_map.gd`, `sim/nav_grid.gd`,
`sim/nests/nest_chambers.gd` (also its header comment listing `rim_point`/`floor_point`),
`species/leafcutter/garden_grid.gd`, `species/leafcutter/leaf_source.gd`,
`render/split_layout.gd`, `scenes/scenario_player.gd`, `sim/colony.gd`, `sim/sim_config.gd`,
`sim/simulation.gd`, `sim/behaviours/behaviour.gd`.
Verify: full suite; hashes unchanged (no sim code path changed).
Hands on: the list actually removed (and any kept, with why).

### M18b: crash and loss fixes (E1–E3)

Goal: the three paths that can crash or lose ants/fungus are safe; existing runs are
unchanged because none of them reaches these paths today.
- E1 `release_waiting`: stop (keep the ant queued and the budget) when the surface layer is
  `layer_full(0)` or `spawn_ant` returns -1. Don't draw extra RNG on the normal path. Test:
  a tiny `max_ants` scenario with `release_per_second`; the queue keeps the ant.
- E2 `spawn_from_pool`: with no dug chamber, fall back to the royal chamber (or return -1,
  which `_pool_in` already handles). Test: call it on a layout with no dug chamber.
- E3: `_add_garden_chamber` returns early on a chamber with no cells. `_seed_new_garden`
  does nothing unless `garden.has_chamber(k)`, and takes donor fungus only once it knows
  where to put it. A chamber that can't hold a garden is noted once, so `_chambers_dug`
  doesn't retry it forever. Test: `chamber_min_radius` small enough that a chamber has no
  cell at `GARDEN_DEPTH`; total fungus is conserved and no script error.
Files: `sim/nests/nest_type.gd`, `sim/nests/colony_nest.gd`,
`species/leafcutter/fungus_nest.gd`, tests in `tests/test_entrances.gd` (or a new
`tests/test_robustness.gd`), `tests/test_fungus_nest.gd`.
Verify: new tests fail before, pass after; full suite; hashes unchanged.
Hands on: whether any E-path was in fact reached by a scenario (it shouldn't be).

### M18c: consistency fixes (E4–E7)

Goal: behaviour matches the code's own docs. Each fix is checked for hash changes on its
own; if one changes a hash, stop and record it (design decision 1).
- E4: `Brood.update` uses `nest.reserve()`. Same value today for every nest that reaches
  the non-care path (`garden` is null there), so hashes should hold. Confirm.
- E5: `carry_waste` fetches from `nest.nearest_entrance(at)`. Could change hashes where a
  nest has extra entrances and uses `carry_waste`. Check `colony_founding`,
  `harvester_founding`, `leafcutter_life` and the native parity tests first; if hashes
  move, ask the user before going on.
- E6: `_tick_transit` also sets `prev_heading[i]`/`shown_heading[i]` (render snapshots,
  not hashed).
- E7: showers must stay in `rain` (renderers draw the ground drying), so keep an index of
  the first shower that may still be active, or a separate active list, and skip ended
  ones in `_apply_rain`. No change to `rain`'s contents or order.
Files: `sim/nests/brood.gd`, `sim/behaviours/carry_waste.gd`, `sim/simulation.gd`,
tests (`test_brood.gd`, `test_midden.gd` or `test_entrances.gd`, `test_rain*`).
Verify: full suite; hash check per fix; a still of a portal exit (`tools/screenshot.sh`
with `--layout=split`) is optional.
Hands on: which fixes changed a hash (hopefully none) and what was decided.

### M18d: small shared helpers (R2, R4, R5, R6)

Goal: one copy of each small helper.
- R2: `Simulation.consume_carried(i) -> Item` (clears `carried`, `carrier`, dismounts
  riders, destroys the item) replaces the copies in `brood_care.gd` and `garden.gd`. The
  rider dismount is new on these paths: check nothing rides pulp or brood food today, so
  hashes hold.
- R4: one parser each for `Vector2` and point lists, in a small static helper (e.g.
  `sim/json_util.gd`, `class_name JsonUtil`), accepting `Vector2` or `[x, y]`. Keep
  `ScenarioEvents.vec2`/`points` and `PropType.params_*` as thin wrappers only if many
  call sites use them, otherwise replace the calls.
- R5: make `NestChambers.soil_around`, `NestChambers.taper` and `DigShape.lattice` public
  (rename + update callers).
- R6: `NativeAnts.available()` uses the cached class check from `_static_ok()`.
Files: `sim/simulation.gd`, `sim/nests/brood_care.gd`, `species/leafcutter/garden.gd`,
`sim/scenario_events.gd`, `sim/scenery/prop_type.gd` (+ its callers), `sim/world.gd`,
`sim/nests/nest_chambers.gd`, `sim/nests/colony_nest.gd`, `sim/nests/dig_shape.gd`,
`sim/native_ants.gd`; `godot --headless --path . --import` after a new `class_name`.
Verify: full suite; hashes unchanged.
Hands on: the new helper names.

### M18e: shared behaviour legs (R3, R7)

Goal: the two larger duplicated pieces become one each.
- R3: a `NestType` (or `Travel`) helper for "carry a load up to the surface and drop it on
  a midden": underground, `Travel.go` to `dump_position()`; on the surface, choose
  `refuse_target` once (flag in a scratch slot the caller names), walk there,
  `drop_item` + `drop_refuse` + `destroy_item`. Returns true when dropped. `carry_corpse`
  and `carry_spent` call it. The RNG draws (two `randf()` for the target) must stay in the
  same order.
- R7: `ColonyNest._spawn_in_chamber(sim, caste, k, l) -> int` (random point, spawn,
  `change_state(first_state(...))`) used by `spawn_initial` and `spawn_from_pool`.
Files: `sim/nests/nest_type.gd`, `sim/behaviours/carry_corpse.gd`,
`sim/behaviours/carry_spent.gd`, `sim/nests/colony_nest.gd`.
Verify: full suite (parity and determinism especially); `tests/midden_probe.gd` output
unchanged on one scenario; hashes unchanged.
Hands on: the helper's signature.

### M18f: one table of behaviour defaults (R1)

Goal: the defaults of the params the native kernel reads (`follow/lay/avoid_channel`,
`timeout`, `home_bias`, `home_cone_deg`, `radius`, `speed_factor`, `duration`) are written
once.
- A `const DEFAULTS := {...}` per native behaviour (on its class), read by both the
  behaviour's `tick()` (`p.get("timeout", DEFAULTS.timeout)` or a small accessor) and
  `NativeAnts.push_colony`.
- Test: for each native kind, `push_colony`'s slot values for an empty params dict equal
  the behaviour's defaults, so they can't drift apart again.
- No C++ change expected (the kernel gets values, not defaults). If one turns out to be
  needed, rebuild with `tools/build_native.sh` and note it.
Files: `sim/behaviours/explore.gd`, `follow_trail.gd`, `carry_home.gd`, `linger.gd`,
`sim/native_ants.gd`, `tests/test_native.gd`.
Verify: full suite with and without native (`tools/test.sh`, `tools/test.sh --no-native`);
hashes unchanged.
Hands on: nothing, unless the kernel changed.

### M18g: tooling, unreviewed-code sweep, docs, long run

Goal: close the milestone.
- E8: `tools/test.sh` kills the Godot processes on INT/TERM (e.g. run each in its own
  process group, or trap in the subshell and kill `$!`).
- Short sweep of `render/` and `species/` (not covered by the review) with the same dead
  code scan (functions never referenced outside their definition). Remove clear cases,
  list the rest here for a later milestone rather than widening this one.
- README and CLAUDE.md: mention any new helper a contributor should reach for
  (`consume_carried`, `JsonUtil`, the refuse leg, behaviour `DEFAULTS`).
- Long check: `tests/nest_probe.gd -- colony_founding 7200 300`, run alone, compared with
  a run at `b94eb35` (CLAUDE.md: nest changes need the full run). In the background, or as
  its own session.
Verify: full suite; nest probe matches the baseline; `--long test_colony_founding_grows`.
Hands on: M18 done; the leftover list for a later milestone.

## Progress log

(none yet)
