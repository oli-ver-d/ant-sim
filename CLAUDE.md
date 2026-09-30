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
godot --headless --path . -s res://tests/bench.gd -- <scenario> <ticks> [ants_per_colony] [seed] [--no-native]
                                       # --by-state (µs per state, nest parts) --from=<s> --load-times
godot --path . -- --scenario=<name> --at=<s> --probe=6   # frame probe: per viewport, slowest renderers; quits after 6 reports
godot --headless --path . -s res://tests/nest_probe.gd -- colony_founding <seconds> <every> [cell_size]   # nest growth
tools/screenshot.sh <scenario> <ticks> out.png [seed] [--zoom= --center= --layout= --at=]
tools/editor.sh [--scenario=<name|path> | --new] [--screenshot=out.png --select=colonies/0]   # scenario editor (M16); no args reopens the last file
godot --headless --path . -s res://tests/validate_scenarios.gd -- [name]   # validate scenarios as the editor does
FORMAT=avi tools/record.sh <scenario|path.json> [seed] [seconds]   # fast draft; default PNG is for finals
                                       # (wraps tools/record.gd, the GDScript pipeline the editor's Record uses)
                                       # SIZE=1920x1080 (record/stills/screenshot) or --size= overrides output.size
```

Tests: `tests/test_*.gd` extend `TestCase` and define `test_*` methods using `check()` /
`check_eq()`. `ERROR:` lines in output are expected (some tests exercise error paths); only
PASS/FAIL lines and the exit code matter. A script error inside a test counts as a failure.
`tools/test.sh` spreads tests over processes by their last times (`.godot/test_times.txt`)
and prints only PASS/FAIL lines; each process's full output is in `.godot/test_runs/`. A
test that crashes its process is reported as a FAIL with no result. Other headless
diagnostics are `tests/*_probe.gd` (story, timeline, frame, fingerprint, midden, scatter, nest); each
documents its args in its header.

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
  A hash that moves unintentionally is a bug. If a change is meant to alter behaviour,
  re-record `SINGLE_LAYER_HASHES` in `tests/test_layers.gd` and say why in the commit.
- **Native kernel parity**: `native/src/ant_kernel.cpp` mirrors the GDScript hot path
  (`explore`, `follow_trail`, `carry_home`, `linger`, `Steering`, `Simulation.lay`, nav-field
  steps in `Travel`, traffic sampling) at the same float/double precision. Any change to those
  must be made in both; `tests/test_native.gd` compares hashes of every scenario both ways.
  During a tick the kernel writes the Simulation's packed arrays in place, so no code may
  replace or resize those arrays mid-tick.

## Milestones: plan in phases, one session per phase

Work is organised as milestones, each with a plan in `docs/plan_M<n>.md`; the highest one is
current, and its Status line says which phase is next. To keep token usage down, **split
every milestone into phases small enough to finish in a separate Claude Code session**,
rather than carrying one long session through a whole milestone.

- At the start of a milestone, write the phase plan first: each phase gets a goal, the files it
  touches, how it will be verified (which tests, probes or stills), and what it hands on to
  the next phase, so a new session can pick it up without re-deriving context.
- A phase should be one coherent, testable change. It is done when:
  1. the **full** suite passes (hash and parity changes handled as under Invariants);
  2. the README is updated if behaviour or tooling changed;
  3. the plan's phase section says what was done, what changed from the plan and what the
     next phase needs (no placeholders left), and its Status line names the real next phase;
  4. any draft videos are `FORMAT=avi`, checked for resolution, fps and duration (PNG only
     for a phase that makes the final videos);
  5. debug scripts (`tests/_*.gd`) are deleted, and the phase is committed (`M17d: ...`).
- Commit only with the suite passing. If a phase can't be finished in one session, commit
  the part that passes, move the rest to a new lettered sub-phase in the plan and say what
  is failing there; don't leave work uncommitted.
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
  functions — pass it as a `sampler2D` parameter. Never name shader variables after Godot
  built-ins (`LIGHT`, `COLOR`, `NORMAL`, `TIME`...): it renders black or neon.
- Probe scripts: type loop variables; an untyped one gave a parse error that hung a headless
  run with no output. Run long probe/bench runs with `timeout`, and don't move files while a
  benchmark is running.
- Use the Edit/Write tools for all file changes. Never modify files with sed, awk or Bash
  heredocs; here they have silently lost edits and injected stray lines.
- Never run a command that waits on stdin; write scripts to a file and run them.

