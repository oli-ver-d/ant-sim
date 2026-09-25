# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A 2D top-down ant colony simulator in Godot 4 (GDScript, plus an optional C++ GDExtension),
built to record 1080×1920 60 fps vertical videos. `README.md` is the detailed reference for
scenario JSON, layers/digging, the native kernel and performance numbers; keep it up to date
when behaviour or tooling changes.

## Environment

- Windows; scripts in `tools/` are bash, run them from Git Bash. Godot 4.7 must be on PATH
  as `godot` (or set `GODOT=`). In a Bash session that doesn't see it:
  `export PATH="/c/Tools/Godot:$PATH"`. ffmpeg is needed for recording.
- Headless Godot has a dummy renderer: screenshots/stills need a windowed run
  (`tools/screenshot.sh`, `tools/stills.sh`).
- After adding a `class_name` or (re)building the native extension, `-s` scripts need
  `godot --headless --path . --import` first (`tools/test.sh` does this for you).

## Commands

```bash
tools/test.sh                          # full headless suite, in parallel (~2.5 min on 8 cores)
tools/test.sh --quick                  # skip tests that took over 5 s last time (~25 s)
tools/test.sh pheromones               # only tests whose "file::method" contains the filter
tools/test.sh test_native::            # one file
tools/test.sh -j 1                     # in one process (default: half the CPU count)
tools/test.sh --no-native              # GDScript ants only
tools/test.sh --long test_colony_founding_grows   # whole colony_founding run (~30 min)
tools/build_native.sh                  # build the C++ ant kernel (MinGW GCC; `clean` removes it)
godot --path . -- --scenario=basic_forage --seed=42 [--at=12.5] [--layout=split]   # interactive
godot --headless --path . -s res://tests/bench.gd -- basic_forage 600 3000 [seed] [--no-native]
godot --headless --path . -s res://tests/nest_probe.gd -- colony_founding 7200 300   # nest growth over a full run
tools/screenshot.sh <scenario> <ticks> out.png [seed] [--zoom= --center= --layout= --at=]
FORMAT=avi tools/record.sh <scenario> [seed] [seconds]   # fast draft; default PNG is for finals
```

Tests: `tests/test_*.gd` extend `TestCase` and define `test_*` methods using `check()` /
`check_eq()`. `ERROR:` lines in output are expected (some tests exercise error paths); only
PASS/FAIL lines and the exit code matter. A script error inside a test counts as a failure.
`tools/test.sh` spreads tests over processes by their last times (`.godot/test_times.txt`)
and prints only PASS/FAIL lines; each process's full output is in `.godot/test_runs/`. A
test that crashes its process is reported as a FAIL with no result.

- Use `--quick` or a filter while iterating; always run the **full** suite before a commit.
  `--quick` is not a gate: it skips the slow scenario, parity and determinism runs.
- Keep tests independent (tests of one file may run in different processes, in any order).
  Split a long test that loops over cases into one test per case so they run in parallel
  (see `test_native_matches_gdscript_*`).

## Architecture

- `sim/` — the engine, no rendering. `Simulation` stores ants as **slots in packed arrays**
  (`pos`, `heading`, `state`, `carried`, `layer`, ...), not nodes. Behaviour states in
  `sim/behaviours/` are shared stateless objects with `enter/tick/exit`; `tick` returns the next
  state id. Per-species wiring (which channel to follow/lay, next state) is data in
  `SpeciesDef.state_params`, overridable per caste and per scenario colony.
- `render/` — renderers only **read** sim state and interpolate between the last two completed
  ticks (`prev_pos` → `shown_pos`). `SimRunner` spreads each 30 Hz tick across frames.
- `species/<name>/register.gd` is auto-discovered and plugs species into `Registry` (species,
  behaviours, food/item/nest types, renderers by string id like `"food:my_food"`).
- `scenes/` — `main.tscn` (interactive, tuning panel) and `record.tscn` (Movie Maker capture);
  `scenario_player.gd` drives playback (camera keyframes, speed schedule, layouts).
- Nests with a queen build on the core `ColonyNest` (queen, `Brood`/`BroodCare`, nest roles,
  `NestChambers`, entrances); species nests (`FungusNest`, `GranaryNest`) add their food
  store and roles. A scenario colony can pick another nest type with `"nest_type"`.
- Layers: layer 0 is the surface; a nest may add an underground `SimLayer` linked by `Portal`s.
  Underground movement uses `NavGrid` distance fields, not pheromones. Digging is planned as
  jobs by `ExcavationPlan`/`DigShape`; `World.dig_log` lets caches update incrementally.

## Invariants that tests enforce

- **Core is species-agnostic**: `/sim` and `/render` must not mention "leaf", "fungus",
  "cutter", "harvester" or any `species/` folder name (`tests/test_core_generic.gd`).
  Species logic goes in `species/<name>/`.
- **Determinism**: all randomness goes through `sim.rng`; `Simulation.state_hash()`
  fingerprints runs. Single-layer runs must hash as before (`tests/test_layers.gd`). New
  behaviours must not change existing hashes (states are hashed by rank among usable states).
- **Native kernel parity**: `native/src/ant_kernel.cpp` mirrors the GDScript hot path
  (`explore`, `follow_trail`, `carry_home`, `linger`, `Steering`, `Simulation.lay`, nav-field
  steps in `Travel`, traffic sampling) at the same float/double precision. Any change to those
  must be made in both; `tests/test_native.gd` compares hashes of every scenario both ways.
  During a tick the kernel writes the Simulation's packed arrays in place, so no code may
  replace or resize those arrays mid-tick.

## Milestones: plan in phases, one session per phase

Work is organised as milestones (M0–M13 so far; big ones were split into M11a–d, M13a–d).
To keep token usage down, **split every milestone into phases small enough to finish in a
separate Claude Code session**, rather than carrying one long session through a whole
milestone.

- At the start of a milestone, write the phase plan first: each phase gets a goal, the files it
  touches, how it will be verified (which tests, probes or stills), and what it hands on to
  the next phase. Save the plan to the repo (e.g. `docs/plan_M14.md`) so a new session
  can pick it up without re-deriving context.
- A phase should be one coherent, testable change: it ends with the suite passing, a commit
  (`M14a: ...`), and the plan file updated with what was done, what changed from the plan and
  anything the next phase needs to know.
- End the session after each phase and tell the user to start a fresh one for the next.
  Don't start the next phase in the same session.
- In a new session, read the plan file and the last phase's commit, then only the files that
  phase touches. Don't re-read the whole codebase or the README end to end.
- Put long runs (full suite, `nest_probe` over 7200 s, recordings) in the background, or in
  phases of their own, instead of polling them inside a working session.

## Working practices

- Nest/digging changes: unit tests have passed while full `colony_founding` runs stalled.
  Verify with `tests/nest_probe.gd` over the whole 7200 s run (~30–40 min; run alone when
  timing, pair A/B runs side by side).
- Foraging outcomes vary a lot by seed early on; check test thresholds over several seeds.
- Shaders: avoid `sin()`-based hashes (visible seams); `TEXTURE` can't be used inside helper
  functions — pass it as a `sampler2D` parameter.
- Use the Edit/Write tools for file content with apostrophes or tabs; Bash heredocs and
  `sed a\` mangle them here.
