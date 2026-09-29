# M16: Graphical scenario editor

Goal: a GUI in which a user opens a scenario JSON, sees it rendered exactly as the
simulation would build it, adds, edits and removes **every option the format supports**
(colonies, food, obstacles, ground, scenery and scatters, debris, events, camera,
playback, render and presentation settings, and the output frame), previews it running,
and saves it back to JSON. From the editor the user can also **run** the scenario
interactively (the `main.tscn` player) and **record** it with chosen recording settings.
Scenarios are no longer tied to a 1080×1920 portrait frame: each scenario (or run, or
recording) can choose its output size, e.g. 1920×1080 landscape or 1080×1080 square.
Files the editor saves are the same format `ScenarioLoader` reads, load the same run
(same state hash) as a hand-written file with the same content, and stay readable and
diffable.

Status: not started; next M16a. (M17 is complete. M15l, founding frame budget and PNG
finals, is still open and independent of M16; finish it first or in between phases.)

## Where things stand (before M16)

- Scenarios are hand-written JSON in `scenarios/`. The format is documented in the
  README "Scenarios" section and in header comments (`sim/scenario_loader.gd`,
  `sim/scenario_events.gd`, `sim/scenery/*.gd`, `render/camera_director.gd`,
  `render/split_layout.gd`, `render/presentation.gd`).
- **There is no schema.** Options are read ad hoc with `dict.get("key", default)`
  (about 80 places over `sim/`, `sim/nests/`, `sim/food/`, `sim/scenery/`,
  `species/*/`, `render/` and `scenes/scenario_player.gd`: nest params, food params,
  prop params, scatter options, events, render/presentation options).
  Per-colony `params` are `SimConfig` exports (27) plus species tunables;
  `nest_params` defaults live in each `SpeciesDef.nest_params` (`.tres`).
- M17 added keys this plan must cover: `render.captions`, `render.fades`,
  `render.grade`, `render.story_marker`, `render.layout.modes`, the prologue/finale
  nest params (`founding`, `landing`, `alates`/`flight`, `gyne`/`male`, ...), phorid
  flies (`phorids`), `tpf`/time jumps in the speed schedule. The M16a coverage test
  (below) is what makes sure none is missed; this list is only a reminder.
- `ScenarioLoader.build(data, registry, config, seed)` builds a `Simulation` from a
  Dictionary, `ScenarioLoader.path_for` already accepts a `res://` path or any path
  ending in `.json`, and `ScenarioPlayer.setup_data(data, ...)` already exists (M17);
  `setup(name)` is load + `setup_data`. `WorldView` renders a sim without stepping it.
- `scenes/main.gd` (interactive player) has some editing (drag walls, right-click
  food, tuning panel that saves colony params), all on the running sim, not on the
  JSON. Its args: `--scenario= --seed= --ticks= --at= --ants= --zoom= --center=
  --safe= --debug= --pheromones= --tuning= --captions= --layout= --screenshot=`.
- Recording: `tools/record.sh <scenario> [seed] [seconds]` with env `FORMAT=png|avi`,
  `MJPEG_QUALITY`, `CAPTIONS=0`; it only accepts a name in `scenarios/`, writes a
  temporary `override.cfg` forcing a 1080×1920 window, runs `record.tscn` under Movie
  Maker at a fixed 60 fps, then `tools/encode.sh` → `renders/<name>_seed<N>_<time>.mp4`.
- **The output frame is hard-coded to 1080×1920**: `project.godot` (viewport
  1080×1920, window 540×960, `canvas_items` stretch), `const FRAME` in
  `render/overlays.gd` (TikTok/Reels safe zones), `render/presentation.gd`,
  `render/split_layout.gd`, the "frame pixels" helpers in `scenes/scenario_player.gd`,
  the tuning panel placement in `scenes/main.gd`, and the `override.cfg` written by
  `tools/record.sh` and `tools/stills.sh`. The world size (`SimConfig.world_size`,
  also 1080×1920 by default, and the `world_size` uniforms of the ground, obstacle and
  rain shaders) is a separate thing and is **not** changed by this milestone.
- `Registry` knows the ids of species, food source types, nest types, scenery types,
  refuse kinds and renderers, so dropdowns can be filled without hard-coding species.
- Godot's `JSON.parse_string` turns every number into a float, and `JSON.stringify`
  uses one indentation style for everything (every array on many lines). Saving
  through it as-is would reformat the hand-written files (and may write whole numbers
  as floats; check in M16a), so the shipped files would produce huge diffs.

## Design decisions (apply to every phase)

1. **A Godot scene in this project, not a separate app.** `scenes/editor.tscn`
   (run with `godot --path . res://scenes/editor.tscn [-- --scenario=<name>]`, and
   `tools/editor.sh`). It reuses `Registry`, `ScenarioLoader`, `WorldView`, the
   scenery and ground code and `ScenarioPlayer` directly, so the preview is the
   real renderer, not an approximation. The editor code lives in `editor/`
   (outside `sim/` and `render/`). It is still kept species-agnostic: everything
   species-specific reaches it through `Registry` and schemas the species register.
2. **The JSON Dictionary is the document.** `ScenarioDoc` holds the parsed data and
   is the only thing that is edited. The preview simulation is rebuilt from it; the
   editor never edits a running `Simulation` and reads nothing back from it (except
   for display, e.g. where a scatter put its props). Keys the editor does not know
   are kept and saved unchanged (shown in a raw JSON field), so nothing is lost when
   a file is opened, edited and saved.
3. **Every edit is a command** on `ScenarioDoc` (set value at a path, insert/remove
   list item, move item), recorded with Godot's `UndoRedo`. The inspector, the
   canvas gizmos and the tests all go through the same commands.
   Paths are arrays like `["colonies", 0, "nest_params", "entrance", "style"]`.
4. **One schema describes the whole format: every option that exists today.**
   `editor/schema/` declares every section, key, type (int, float, bool, string,
   enum, vec2, size, rect, points, colour, dict, list, one-of-variants, raw), default,
   range and help text (copied from the README). "Every option" means every key the
   code reads from scenario data, not only the keys the shipped scenarios happen to
   use; the M16a coverage tests check both. Enum choices can come from the `Registry`
   (species, food types, nest types, scenery types, castes of the chosen species) or
   from core lists (materials, presets, entrance/midden styles, layout modes, frame
   presets). Species contribute schemas for what they add (`leaf`, `seed_pile`, their
   nest params) through a new `Registry.register_schema(id, schema)` call in their
   `register.gd`, like renderers. The schema is **editor metadata only**: the sim
   keeps reading with `.get(key, default)`, so no run changes. Any option added by a
   later milestone must be added to the schema in the same phase (the coverage test
   fails otherwise).
5. **Saving writes stable, hand-readable JSON.** `ScenarioJson.stringify(data)`: tabs
   as in the shipped files; keys in a fixed order per section (from the schema, then
   unknown keys in their original order); numbers that are whole written as ints;
   short arrays and small dicts (points, `[x, y]`, a food entry) on one line when
   they fit in ~100 columns. Loading keeps the original key order. Aim: loading and
   saving a shipped scenario without edits gives a small diff (ideally none).
6. **Preview = build, don't step.** The static preview is `ScenarioLoader.build(doc)`
   at t = 0 plus `warmup` if asked, drawn by `WorldView`. Rebuilding is debounced
   (~250 ms after the last edit) and done only when the edit ends (mouse release)
   while dragging; during a drag only the gizmo overlay moves. If rebuilds are slow
   (scatters, ground maps), later phases rebuild only what changed. "Play" runs the
   document through `ScenarioPlayer.setup_data`, exactly as a recording would.
7. **Determinism is untouched.** The editor never touches `sim.rng` or any sim code
   path. The output frame size (decision 10) is render-only. `tests/test_layers.gd`
   and `tests/test_native.gd` hashes must not change in any M16 phase.
8. **Landscape editor window.** The editor scene sets its own window size and turns
   off the project's content scaling at runtime (`get_window()`), without
   changing `project.godot` for the other scenes. Layout: outline tree (left),
   preview canvas (centre, with the scenario's output frame, safe zones and a split
   layout guide shown as overlays), inspector (right), timeline (bottom, M16g).
9. **Tests are headless.** Doc, schema, writer, commands, validation, gizmo hit
   testing, frame layout maths and run/record command building are plain classes with
   unit tests. The GUI is checked by a `--screenshot=` run of the editor scene (like
   `main.gd`), which needs a windowed run.
10. **The output frame size is a setting, not a constant.** A new optional top-level
    scenario section `"output": {"size": [1080, 1920], "safe_zones": "tiktok"}`
    (`size` any even width/height, presets offered by the editor: 1080×1920 portrait,
    1920×1080 landscape, 1080×1080 square, 1080×1350 4:5, 2160×3840 and 3840×2160;
    `safe_zones` one of `tiktok`, `youtube_shorts`, `none`, ...). Absent means
    1080×1920 / `tiktok`, so every existing scenario renders exactly as before.
    Every run can override it: `--size=WxH` for `main.tscn`, `record.tscn`,
    `tools/record.sh`, `tools/screenshot.sh` and `tools/stills.sh`. A single
    `OutputFrame` (render-side, e.g. `render/output_frame.gd`) owns the size, and
    every current `FRAME` constant and hard-coded 1080/1920 reads from it. The
    interactive window keeps the frame's aspect and is scaled to fit the screen (the
    current 540×960 is the portrait case). Camera `zoom` keeps its meaning (world
    units per frame pixel), so a wider frame shows more world, and `fit` keyframes
    fit the new frame. The world size is independent and unchanged.
11. **Run and record are separate processes.** The editor never records or plays the
    interactive scene in its own window: "Run" launches `main.tscn` and "Record"
    launches the recording pipeline as child processes with the document written to a
    file, so both behave exactly as when started from the command line, the editor
    stays usable, and Movie Maker gets the window size it needs at startup. The
    command lines are built by a pure class (`editor/launch_commands.gd`) so they can
    be tested headless.

## Phases

### M16a: schema, document model and JSON writer (headless, no GUI)

- `editor/scenario_doc.gd` (`ScenarioDoc`): load/save a file, data, path, dirty flag,
  `get_at(path)`, commands `set_at`, `insert_at`, `remove_at`, `move_item` with
  `UndoRedo`, a `changed(path)` signal.
- `editor/scenario_json.gd` (`ScenarioJson`): parse keeping key order; `stringify`
  per decision 5.
- `editor/schema/`: field types (`FieldSpec`), the core schema for every section of
  the format including all M17 `render` keys (captions, fades, grade, story marker,
  layout and its modes) and the new `output` section (decision 10, schema only here;
  it takes effect in M16b), and `Registry.register_schema`; schemas for `leaf`,
  `seed_pile`, fungus/granary/seed nest params (including founding, landing,
  alates/flight) and phorid flies in `species/*/register.gd`.
- Tests `tests/test_scenario_doc.gd`:
  - round trip: every `scenarios/*.json` → parse → stringify → parse is equal, and
    `ScenarioLoader.build` of both gives the same `state_hash()` after a few ticks
    (one test per scenario so they run in parallel);
  - text diff: re-saving an unedited shipped scenario gives the same file, or report
    the differences (target: none; decide in the phase whether to reformat the shipped
    files once);
  - coverage of the data: every key used in the shipped scenarios and in the
    species' `nest_params` is in the schema (walks the data against the schema);
  - **coverage of the code**: a test reads the source of every script that reads
    scenario data (`sim/`, `sim/nests/`, `sim/food/`, `sim/scenery/`, `species/*/`,
    `render/`, `scenes/scenario_player.gd`) and collects the string keys passed to
    `.get("...")` / `["..."]` on scenario dictionaries; every key must be in the schema
    or in a short, commented ignore list of dictionaries that are not scenario data.
    This catches options that exist in code but no shipped scenario uses;
  - commands: set/insert/remove/move, then undo and redo, restore the exact data.
- Hands on: the doc and schema APIs, the ignore list, and the keys found only by the
  code-coverage test (undocumented options; add them to the README format section).

### M16b: configurable output frame size (engine side, no editor)

- `render/output_frame.gd` (`OutputFrame`): size and safe-zone preset from the
  scenario's `output` section, overridden by `--size=WxH`; helpers for frame rects.
- Replace every hard-coded frame size (see "Where things stand"):
  `render/overlays.gd` (safe zones per preset; the TikTok/Reels one unchanged, others
  added, `none` draws nothing), `render/presentation.gd` (captions, fades and
  vignette placed relative to the frame; caption width and font size scale with the
  frame's short side), `render/split_layout.gd` (in a landscape frame, `surface`
  also accepts `"left"`/`"right"` for side-by-side panes; `ratio` applies along the
  split axis), `scenes/scenario_player.gd` (frame-pixel helpers), `scenes/main.gd`
  (tuning panel and HUD placed relative to the frame), `scenes/record.gd`.
- Window: `main.tscn` and `record.tscn` set the viewport size to the frame at startup
  (`get_window().content_scale_size`) and size the window to fit the screen at the
  frame's aspect. `project.godot` keeps its portrait defaults. (Note: there is an
  uncommitted local change to `window/stretch/aspect` in `project.godot`; ask the
  user before committing anything in that file.)
- Tools: `tools/record.sh`, `tools/stills.sh` and `tools/screenshot.sh` take
  `SIZE=WxH` (env) or read the scenario's `output.size`, and write it into their
  `override.cfg` instead of 1080×1920 (or use Godot's `--resolution WxH` if it works
  with Movie Maker; check, and drop `override.cfg` if it does). `tools/encode.sh`
  must not assume a portrait size.
- Tests: `OutputFrame` parsing, defaults and overrides; safe-zone and split-layout
  rects for portrait, landscape and square frames (pure maths); every scenario's
  state hash unchanged (the frame is render-only); the default frame gives the
  exact same rects as before.
- Verify: full suite; stills of `basic_forage` and `leafcutter_life` (split, with
  captions) at 1080×1920 (unchanged from before, compare images), 1920×1080 and
  1080×1080; one `FORMAT=avi` draft at 1920×1080 checked with ffprobe for size, fps
  and duration.
- Hands on: `OutputFrame` API, `--size=` everywhere, the landscape split options
  (needed in the schema and the timeline's layout track).

### M16c: editor scene, file handling and static preview

- `scenes/editor.tscn`, `editor/editor_main.gd`: landscape window, panel layout
  (decision 8), menu/toolbar: New (from a minimal template), Open, Save, Save As,
  Revert, recent files (in `user://`), "unsaved changes" prompt on close/open/new.
  Godot `FileDialog` rooted at `res://scenarios` (any path allowed).
- `editor/preview.gd`: a `SubViewport` holding a `WorldView` of the built sim, with its
  own pan/zoom camera (wheel, middle drag, "fit world", "fit output frame"); the
  debounced rebuild of decision 6; a status line with build time and errors. The
  output frame overlay uses the document's `output.size` (from M16b).
- Outline tree (left): sections and their items ("Colony 0: leafcutter @ 540,1500",
  "Food 1: food_pile"), selection shared with the preview (selected item outlined).
- `--scenario=` (name or path) and `--screenshot=` arguments; `tools/editor.sh`.
- Verify: full suite; windowed screenshots of the editor with `basic_forage`,
  `meadow_forage`, `colony_founding`; open → save → `git diff` is empty (or as
  agreed in M16a).

### M16d: inspector (all options as forms)

- `editor/inspector.gd` + `editor/widgets/`: a form built from the schema for the
  selected item or section: spin boxes with ranges, sliders for 0–1, check boxes,
  enum dropdowns (registry-filled; castes follow the chosen species), vec2/rect
  fields, colour pickers, point lists, nested dicts as collapsible groups, lists
  with add/remove/reorder, one-of variants (obstacle shape, event type, scenery type
  vs scatter) as a type selector that swaps the fields.
- **Every schema key is reachable from the inspector**: there is a form section for
  every top-level section, including `render` (captions, fades, grade, story marker,
  layout, pheromones) and `output` (frame preset dropdown + custom width/height,
  safe-zone preset). A test walks the schema and fails if any key has no widget.
- "Optional" keys show their default greyed out; setting one adds it to the JSON,
  "reset" removes it again (so files stay minimal).
- `params`: fields for the `SimConfig` exports (introspected with
  `get_property_list`, values shown against the species/config defaults) and the
  species tunables; `state_params` and `channels` as dict editors.
- Raw JSON field for unknown keys and as an "edit as JSON" fallback per item.
- Add/remove from the outline: "Add colony / food / obstacle / prop / scatter /
  region / debris / event / camera key / caption" with sensible defaults at the view
  centre.
- Tests: inspector edits go through doc commands (headless, drive the widgets'
  signals); every schema field type has a widget; every schema key is shown.

### M16e: canvas editing (gizmos)

- `editor/gizmos/`: handles drawn over the preview for every positioned thing:
  nest position, food position/radius, obstacle points/rects/circles/polygons,
  debris, prop centres/radii/log points, scatter rect and `clear` shapes, ground
  region shapes (+ `soft` edge ring), camera `pos` keyframes, rain areas of events.
- Select by click (topmost), drag to move, drag handles to resize or move points,
  Alt-click to insert a point, Delete to remove, Ctrl+D duplicate, grid snap toggle.
- Place tools: pick a type in a palette, click (or click-click-… for polylines and
  polygons) to create.
- Overlays: world bounds, the output frame (document size) at the first camera key,
  safe zones of the chosen preset, nest keep-clear/reserve rings of scatters.
- Hit testing and handle geometry are pure functions (`GizmoGeometry`) with tests.
- Verify: tests + screenshots with a selected item of each kind.

### M16f: ground, scenery and scatter editing, rebuild speed

- Ground: region list with drag-to-reorder (paint order), material swatches, noise
  controls, a "show materials" overlay (flat colours per material from `GroundMap`).
- Scenery: which props each scatter placed (drawn tinted when the scatter is
  selected), "reseed" (sets the scatter `seed`), per-prop blocking outline
  (footprint cells from `World.prop_mask`) and a warning when a blocking prop was
  dropped for cutting a colony off (from `Scatter`'s report).
- Incremental rebuild: time rebuilds of each scenario (`scatter_probe` gives load
  times); if a full rebuild is over ~150 ms, rebuild only the ground for ground edits
  and only scenery for prop edits, and keep the rest of the sim.
- Verify: tests for the partial rebuild matching a full one (same hash, same prop
  list); timing numbers in the progress log.

### M16g: time: events, camera, speed, presentation and play preview

- Timeline panel (bottom): video time ruler with camera keyframes, the
  `ticks_per_frame` schedule as a curve (including time jumps), layout mode changes
  (`render.layout.modes`), captions, fades and story-marker spans; a sim-time track
  for `events` (converted with the speed schedule so both show on one ruler).
- Event editing: list + inspector (one-of by `type`), drag on the timeline to change
  `t`; area gizmos from M16e. Captions, fades, story markers and layout modes can be
  added, dragged and resized (`t`/`until`) on the timeline too.
- Camera: add a keyframe from the current preview view ("key here"), `follow` and
  `fit` variants, `ease`; separate `surface`/`nest` tracks for split scenarios.
- Play: runs the document through `ScenarioPlayer.setup_data` in the document's output
  frame (scaled), play/pause/speed, scrub = rebuild and fast-forward to that video time
  (with a progress bar; long founding runs are slow, which is expected). Editing while
  playing stops play and returns to the static preview. This is a preview inside the
  editor; the full interactive player and recording are M16h.
- Verify: tests for the video-time ↔ sim-time mapping against `ScenarioPlayer`;
  play `basic_forage` and `leafcutter_life` (split, captions) in the editor and
  screenshot.

### M16h: run and record from the editor

- **Temp copy of the document.** Run and Record work on the current document even if
  it is unsaved or has never been saved: it is written with `ScenarioJson.stringify` to
  `user://editor_runs/<name>.json` (absolute path passed on), so what runs is exactly
  what is on screen. The saved file is not touched.
- **Run (F5).** Launches the interactive player as a separate process
  (`OS.create_process(OS.get_executable_path(), ["--path", <project>,
  "res://scenes/main.tscn", "--", "--scenario=<abs path>", ...])`). A small run bar
  sets the options `main.gd` already takes: seed (scenario's / fixed / random),
  start at video time (`--at=`, "from playhead" uses the timeline position), layout
  (`--layout=`), frame size (`--size=`, defaults to the document's `output.size`),
  captions on/off, safe zones, pheromones, debug, tuning panel. "Stop" kills the
  process (`OS.kill`). The user interacts with it as with any `main.tscn` run (drag
  walls, place food, tuning panel).
- **Record…** dialog with the recording settings:
  - format: PNG (final) or AVI/MJPEG (draft), MJPEG quality;
  - frame size: preset or custom W×H (default: the document's `output.size`);
  - seed, duration override (whole run or a start/end video-time range if
    `record.tscn` supports `--at=`; add it there if not), captions on/off;
  - output folder and file name (default `renders/<name>_seed<N>_<time>.mp4`).
  It runs the same pipeline as `tools/record.sh`, so there is one way to record:
  `tools/record.sh` is extended to take a scenario **path** as well as a name, and
  `SIZE=`, `OUT=` and a start time; the editor runs it through Git Bash (`bash.exe`
  found on PATH or set in the editor's settings; show a clear error if it isn't
  found). If driving bash from Godot on Windows proves unreliable, the editor instead
  runs `record.tscn` under Movie Maker and `ffmpeg` directly with the same arguments
  (decide in the phase, keep `record.sh` and the editor producing identical files).
  While recording: a progress bar from the frame count Movie Maker reports (frames
  written / `duration × 60`), the process log, Cancel (kills the process and removes
  partial output), and when done the output path with "Open folder" / "Play".
  Only one recording at a time; the editor stays usable while it runs.
- Settings memory: the last run and record settings are kept per scenario in
  `user://editor_settings.cfg`, not in the scenario JSON (they describe a run, not
  the scenario); the frame size belongs to the scenario (`output`), so changing it in
  the dialog offers "also set as the scenario's output size".
- `main.gd` and `record.gd` accept `--scenario=<absolute path>` (`path_for` already
  handles `.json` paths; check `user://` and absolute Windows paths).
- Tests: `LaunchCommands` builds the expected argument lists and env for given
  settings (run and record, every option); `--scenario=<path>` to a temp copy gives the
  same state hash as the scenario by name; `record.sh` with a path argument (a quick
  `FORMAT=avi` run of a few seconds) produces a file of the requested size, 60 fps and
  duration (checked with ffprobe; mark it a long test).
- Verify: from the editor, Run `basic_forage` and interact with it; Record a 5 s
  `FORMAT=avi` draft of `basic_forage` at 1080×1920 and at 1920×1080 and check both
  with ffprobe; screenshot the Record dialog and the progress view.

### M16i: validation, polish and docs

- `editor/scenario_validator.gd`: schema checks (types, ranges, required keys,
  unknown enum values like a species that isn't registered, output size odd or out
  of range) and scene checks (nest, food or portal outside the world or inside a wall,
  event `t` beyond the run, camera key or caption after `duration`, colonies
  overlapping, captions outside the safe zone of the chosen preset). Errors listed in
  a panel and marked on items in the outline and preview; saving, running and
  recording with errors warn but are allowed.
- `tests/validate_scenarios.gd` (headless: `godot --headless --path . -s
  res://tests/validate_scenarios.gd -- [name]`) and a test that every shipped
  scenario validates cleanly.
- Polish: keyboard shortcuts (Ctrl+S/O/N/Z/Y, Delete, F fit, F5 run, Ctrl+R record),
  tooltips from the schema help, remember panel sizes and last file.
- Acceptance: build a new scenario from scratch in the editor only (two colonies,
  food, a scatter, a rain event, camera keys, a caption, a landscape 1920×1080 output
  frame), save it, Run it from the editor and interact with it, Record a draft from
  the editor's Record dialog (AVI), check it with ffprobe, and confirm the saved JSON
  also loads with `godot --path . -- --scenario=<name>` and `tools/record.sh`.
- README: a "Scenario editor" section (running it, panels, keys, run and record, what
  is kept of unknown keys), the `output` section and `--size=`/`SIZE=` in the format
  and tooling docs; the editor command in CLAUDE.md "Commands".

## Open questions (decide before the phase that needs them)

- M16a: if the writer can't reproduce the shipped files byte for byte, reformat all
  shipped scenarios once with it (one commit, hashes checked) or keep tweaking?
  Recommendation: reformat once if the differences are just whitespace/wrapping.
- M16a: schemas in one core file plus species registrations, or a
  `static func schema()` on each food/nest/prop type script? Recommendation:
  on the type scripts where they exist (keeps options next to the code that reads
  them), collected through `Registry`.
- M16b: should `output` also carry the frame rate? Movie Maker records at a fixed
  60 fps and the speed schedule is in ticks per video frame, so 30 fps would change
  playback speed unless `ticks_per_frame` is rescaled. Recommendation: keep 60 fps
  fixed in M16; add `fps` later only with that rescaling.
- M16b: captions and presentation in a landscape frame: scale by the short side, or
  author per-orientation positions? Recommendation: scale by the short side, check
  with stills.
- M16d: should the tuning panel in `main.tscn` be replaced by the editor's `params`
  form later? (Not in M16.)
- M16g: scrub cost for long runs. A snapshot cache of sim states would need
  Simulation serialisation, which doesn't exist; out of scope unless scrubbing
  `colony_founding` turns out unusable.
- M16h: record through `tools/record.sh` via Git Bash, or reimplement the pipeline in
  GDScript? Recommendation: Git Bash first (one pipeline); fall back only if it's
  unreliable.

## Progress log

(none yet)
