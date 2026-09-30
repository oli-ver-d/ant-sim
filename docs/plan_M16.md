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

Status: M16i done; next is M16j (world size per scenario). (M17 is complete. M15l,
founding frame budget and PNG finals, is still open and independent of M16.)

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

**Done (M16a).** What exists now:

- `editor/schema/field_spec.gd` (`FieldSpec`): types `int float bool string enum vec2
  size rect points color dict map list variant any_of raw`; constructors
  `integer number boolean text choice vec2 size rect points color dict map list variant
  any_of raw resolved`, chained `req() limits(lo, hi) describe() from_registry(src)
  with_registry_variants(prefix)`; `matches(value)` picks `any_of` alternatives by JSON
  shape (dicts by their required keys, variants by their tag). Schema files use
  `const F = preload(".../field_spec.gd")` (a `const F := FieldSpec` is not constant).
- `editor/schema/scenario_schema.gd` (`ScenarioSchema.new(registry)`): `root`,
  `spec_at(data, path)` (resolved for the value there), `resolve`, `child_spec`,
  `variant_spec`/`variant_names`, `schema_for(id)`, `ids_with_prefix`,
  `choices_for(source, context)` (sources: `species food_types nest_types
  scenery_types item_types refuse_kinds states castes channels params`; castes and
  channels from `context["species"]`), `unknown_paths(data)`, `all_key_names()`,
  `params_spec(colony)` (SimConfig exports + species tunables, introspected) and
  `nest_params_spec(colony)` (`"nest:<nest_type or species' nest type>"`).
- Schema content: `CoreSchema` (root, colony, food variant + `food_common`/`food_type`,
  `food:food_pile`, ticks_per_frame incl. `jump`, camera keyframes or
  `{surface, nest}` tracks, all `render` keys, `output`, the 9 event types),
  `ScenerySchema` (obstacles, ground, scenery props `scenery:rock|log|plant|grass`,
  scatter, debris), `NestSchema` (`nest:basic_nest`, `colony_nest()`,
  `colony_underground()`, `extend(base, extra)`), `BehaviourSchema` (`state_params`:
  one union dict of every state key for all states; `channels`). Species:
  `species/<name>/schema.gd` (no class_name, preloaded by `register.gd`) register
  `nest:fungus_nest` (incl. `phorids`), `food:leaf`, `nest:seed_nest`,
  `nest:granary_nest`, `food:seed_pile` via the new `Registry.register_schema`
  (`Registry.schemas`, typed `RefCounted` so `sim/` doesn't depend on `editor/`).
- `editor/scenario_json.gd` (`ScenarioJson`): `parse`/`load_file` (key order kept),
  `stringify`/`save_file`, `inline`, `number`. Style: tabs, whole numbers as ints,
  shortest round-tripping decimals, a container on one line if it fits in 140 columns
  (tab = 4), top level one key per line, top-level lists of entries one per line.
- `editor/scenario_doc.gd` (`ScenarioDoc`): `data`, `file_path`, `schema`,
  `load_file`, `save`, `is_dirty`, `has_at`, `get_at`, commands `set_at` (creates
  missing dicts), `remove_at` (dict key or list item; this is also the inspector's
  "reset to default"), `insert_at`, `move_item`, `undo`/`redo` (`UndoRedo`),
  `changed(path)` signal.
- Tests: `tests/test_scenario_schema.gd` (code coverage per area, data coverage of
  every shipped scenario and every species' defaults, a schema for every registered
  nest/food/scenery type, ignore list still current, `spec_at` resolution) and
  `tests/test_scenario_doc.gd` (round trip per scenario: same data, same text, same
  state hash after 20 ticks; writer style; every command undone and redone exactly).
  Ignore list: `tests/fixtures/schema_ignored_keys.txt` (`<path> <keys|*>  # why`).

Changed from the plan:

- Open question 1: the writer can't reproduce the hand wrapping, so **all shipped
  scenarios were reformatted once** with `ScenarioJson` (data unchanged, checked by the
  round-trip tests and the unchanged `test_layers`/`test_native` hashes). Re-saving an
  unedited file now gives the same bytes.
- Key order: the writer keeps the document's own key order instead of sorting by the
  schema (sorting would have reordered every file); `ScenarioDoc` puts a *new* key
  after the keys the schema lists before it.
- Open question 2: schemas live in `editor/schema/` and `species/<name>/schema.gd`,
  not in `static func schema()` on the type scripts, so `sim/` stays free of editor
  classes.
- The code coverage test checks key *names* against every name in the schema (not
  paths), so a key under the wrong section would pass it; the data coverage test is
  structural. `sim/router.gd` is ignored as a whole (route params come from code).
- JSON numbers load as floats: compare saved/loaded docs as text, not with `==`
  (Dictionary `==` tells 7 from 7.0).

Next (M16b) needs: `CoreSchema.output()` already describes `output.size` /
`output.safe_zones` (`tiktok`, `youtube_shorts`, `none`); when M16b adds landscape
split options (`render.layout.surface` = `left`/`right`) or other presets, add them to
`CoreSchema.render()`/`output()` in the same phase or `test_scenario_schema` fails.

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

**Done (M16b).** What exists now:

- `render/output_frame.gd` (`OutputFrame`, RefCounted): `size` (Vector2i), `safe_zones`;
  `from_scenario(data, size_override)` (bad values push_error and keep the default /
  scenario size), `parse_size("WxH" or preset name)`, `valid_size` (even, 64–8192),
  `PRESETS` (portrait, landscape, square, 4:5, portrait_4k, landscape_4k), `SAFE_ZONES`
  (`tiktok` 150/400/right 120 as before, `youtube_shorts` 120/360/right 190, `none`),
  `scale()` (short side / 1080), `margins()`, `safe_rect()`, `unsafe_rects()`,
  `window_size(screen)` (half the frame, shrunk to fit), `apply_to_window(window, resize)`
  (sets `content_scale_size`; resizes/centres the window only for interactive runs).
- `ScenarioPlayer.frame` (built in `setup_data` from the data and `size_override`, which
  the scenes set from `--size=` before `setup`), passed to `SplitLayout.create(sim, spec,
  frame)` and `Presentation.setup(render, frame)`. The player does **not** touch the window
  (the editor will host it in a SubViewport); `main.gd` and `record.gd` call
  `apply_to_window` right after `setup` (before `--at` fast-forwarding, since camera
  clamping and `fit` read the viewport size).
- Pure static helpers (tested): `SplitLayout.split_rects(frame_size, spec)` (`surface`
  top/bottom stacked, left/right side by side with `ratio` along the width),
  `SplitLayout.seam_rect`, `SplitLayout.stats_origin(frame, nest_part)`,
  `Presentation.caption_column(frame)` (the portrait column width scaled by the short side,
  centred) and `Presentation.caption_top(frame, pos, box_h)`. Text sizes, outlines and the
  nest readout scale with `frame.scale()`. `Overlays.SafeZones.set_frame(frame)` draws the
  preset (nothing for `none`).
- `main.gd`: `--size=`; the tuning panel is placed from the frame's right edge.
  `record.gd`: `--size=`, warns if the window isn't the frame size.
- Tools: `tools/frame_size.sh` (sourced; `SIZE=` env, else the scenario file's one-line
  `"output": {"size": [w, h]}`, else 1080x1920; validates) used by `record.sh` and
  `stills.sh`, which write that size into their temporary `override.cfg` and pass
  `--size=`; `record.sh` adds `_WxH` to the file name for non-default sizes.
  `screenshot.sh` passes `SIZE=` as `--size=`. `encode.sh` needed nothing.
- Schema: `render.layout.surface` also takes `left`/`right`.
- Tests: `tests/test_output_frame.gd` (parsing, defaults, overrides, bad values; the default
  frame gives exactly the old safe-zone, split, seam, caption and readout rects; presets,
  landscape/square/4k maths; window sizing; an `output` section leaves the state hash
  unchanged).

Changed from the plan:

- `override.cfg` is kept (it is known to give an exact window larger than the screen) and now
  carries the frame size; `--resolution` was not adopted.
- Captions in landscape keep the portrait column width (scaled by the short side), centred,
  instead of spanning the frame (open question answered: scale by the short side).
- Open question on `fps`: kept at 60 (not in `output`).
- The `project.godot` note was stale: the tree was clean, nothing there changed.

Next (M16c) needs: the preview's frame overlay can use
`OutputFrame.from_scenario(doc.data)` and its `safe_rect()`/`unsafe_rects()`; the frame
presets for a dropdown are `OutputFrame.PRESETS`; `ScenarioPlayer` never resizes the
window, so it can be hosted in a SubViewport sized to `frame.size`.

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

**Done (M16c).** What exists now:

- `scenes/editor.tscn` + `editor/editor_main.gd` (`ScenarioEditor`, Control): sets its own
  window (1600×900 fitted to the screen, content scaling off) and takes over closing
  (`auto_accept_quit = false`); both only when `manage_window` (tests turn it off).
  Menu bar: File (New from a template with one colony of the first registered species,
  Open, Open Recent, Save, Save As, Revert, Quit), Edit (Undo/Redo = `doc.undo/redo`),
  View (Fit world Home, Fit output frame F) plus Fit buttons. Unsaved changes go through
  `_confirm_then(action)` (Save / Discard / Cancel). `FileDialog` (filesystem access, starts
  in `res://scenarios` or the doc's folder; project paths are localised to `res://`).
  Layout: outline `Tree` (left), `EditorPreview` (centre), a read-only JSON view of the
  selected item in a `TextEdit` (right; M16d replaces it with the inspector), status
  line (file, modified, build status). Public-ish state for tests and later phases:
  `doc`, `schema`, `registry`, `rows`, `selected` (path or null), `_select_path(path)`,
  `_open(path)`, `_save()`, `_save_to(path)`, `settings_path`, `args`.
  Args: `--scenario=<name|path>`, `--screenshot=<png>` (after the preview is built, then
  quit), `--select=colonies/0`. `tools/editor.sh` passes its args through.
- `editor/preview.gd` (`EditorPreview`, SubViewportContainer): `show_data(data, now)`,
  debounced `rebuild()` (REBUILD_DELAY 0.25 s; `ScenarioLoader.build`, no warmup, no
  steps; a new `WorldView` replaces the old), `status_changed`, `build_ms`, own `Camera2D`
  (wheel zoom about the cursor, middle/right drag pan), `fit_world/fit_frame/fit_rect`
  (refit on resize until the user pans or zooms), `to_world(local)`, `selection` (world
  rect outlined). Overlays: world bounds, the output frame (`OutputFrame.from_scenario`)
  at `frame_world_rect(data, frame, world)` (first camera keyframe's `pos` or follow
  `near`, frame size / zoom; `fit` keys show the world) with its unsafe zones shaded.
  Static helpers `fit_zoom`, `frame_world_rect` are tested.
- `editor/editor_outline.gd` (`EditorOutline`, written by a subagent): `build(data)` →
  rows `{label, path, depth}` (Scenario `[]`, Colonies, Food, Obstacles always; Ground
  regions, Scenery props/scatters, Debris, Events, Camera keyframes or Surface/Nest
  tracks, Render, Output and unknown top-level keys when present), `item_bounds(data,
  path)` (Rect2() when an item has no position), `section_of(path)`, `row_for(rows, path)`
  (deepest row containing a path). Clicking in the preview selects the smallest item
  bounds under the cursor.
- `editor/editor_recent.gd` (`EditorRecent`): 10 recent files in
  `user://editor_settings.cfg` section `recent` (other sections kept, for M16h settings).
- Tests: `tests/test_editor_outline.gd` (labels, sections, paths, bounds, recent files) and
  `tests/test_editor.gd` (frame rect and fit maths, preview build/debounce/refit/zoom,
  the editor scene headless: open, new, select + click, edit → dirty → save →
  byte-identical unedited save, revert via discard, undo/redo, missing file).
- Screenshots (windowed) of `basic_forage`, `meadow_forage` and `colony_founding` with
  colony 0 selected look right.

Changed from the plan / found on the way:

- `ScenarioDoc.changed` fires before `UndoRedo` counts the action, so `is_dirty()` is stale
  inside the signal; the editor updates its title/status deferred. (Connecting
  `undo_redo.version_changed` gave "Bad address index" script errors; not pursued.)
- `PhoridRenderer` crashed every frame (`flies` null) for fungus nests without `phorids`
  (its `set_process(false)` in `bind()` is undone on entering the tree); now guarded.
  Render only, no hash change.
- Rebuild times: `basic_forage` ~0.4 s, `meadow_forage` ~1.5 s, `colony_founding` ~2.3 s
  (scatters, ground). Well over M16f's 150 ms target: M16f's partial rebuild is needed.

Next (M16d) needs: replace the right-hand `details` TextEdit with the inspector for
`editor.selected`; edits go through `doc.set_at/remove_at/insert_at` (the editor already
rebuilds outline, selection and preview on `doc.changed`). `schema.spec_at(doc.data,
path)` gives the field spec for a selected path; "Add ..." actions belong in the outline
(rows for empty sections already exist).

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

**Done (M16d).** What exists now:

- `editor/inspector.gd` (`ScenarioInspector`, ScrollContainer; `EditorInspector` is a Godot
  class name): `setup(doc, schema)`, `show_path(path)` (`[]` = the scenario's own
  `EditorOutline.SCENARIO_KEYS`, a section, an item, or an unknown key), `rebuild()`,
  `on_doc_changed(path)` (rebuilds unless the change is the inspector's own, so a field
  being edited keeps focus), `rows` (path string → row or group header, metas `type`,
  `present`, `widget`, `reset`; `"<list or map>/+"` for add rows), `row_at(path)`,
  `expand_all`. Widgets: int SpinBox; float LineEdit (+ HSlider when both limits are
  finite, committed on drag end); bool CheckBox; string LineEdit (TextEdit for `text`,
  `description` or multi-line values); enum OptionButton (`choices` or
  `schema.choices_for`, context = the nearest enclosing dict with a `species`); vec2 /
  size / rect LineEdits (meta `edits`; `output/size` also a preset OptionButton from
  `OutputFrame.PRESETS`, meta `presets`); color ColorPickerButton (committed on popup close,
  written in the old value's form: array or "#hex"); points rows of [x, y] with add/remove;
  dict / map / list / variant as fold groups (open by default when set, depth ≤ 1 and ≤ 8
  entries; built lazily when opened); variant tag OptionButton →
  `EditorDefaults.variant_value`; any_of a form OptionButton (meta `form`, nested any_ofs
  flattened) → `EditorDefaults.value_for`; raw / unknown keys JSON TextEdit (committed on
  focus exit when it parses). Absent keys greyed with the default; reset (x) =
  `doc.remove_at`. Header: "Edit as JSON" (whole item, Apply) and Delete for list items.
- `editor/widgets/field_values.gd` (`FieldValues`): number parse (clamped, ints rounded) and
  format, colour ⇄ JSON, `tidy` (whole floats → ints), raw JSON text parse.
- `editor/editor_defaults.gd` (`EditorDefaults`, written by a subagent): `value_for(spec,
  schema, context)` (required fields only), `variant_value(spec, schema, tag, old)`,
  `add_actions(data, path)` → `{label, id, list}`, `new_item(id, data, schema, at)` (ids
  `colony food obstacle ground_region prop scatter debris event camera_key nest_camera_key
  caption`), `example(spec, schema, k)` (every key filled; k picks enum values, variants and
  any_of alternatives, so different k reach different species' params and nest params).
- `ScenarioEditor`: the right panel is the inspector; "Add..." MenuButton above the outline
  (`_fill_add_menu`, `add_item(action)`: inserts at the preview's view centre and selects
  it; a string `ground` becomes `{"base": <it>, "regions": [...]}`). `_on_doc_changed` keeps
  the selection unless its path is gone.
- Tests: `tests/test_inspector.gd` (FieldValues; scalar, absent/reset, bool/string/enum,
  castes, colour/raw, variant switch, any_of switch, list add/move/remove, points and
  nested-absent dicts, output presets, edit as JSON, every type has a widget, every key of
  `EditorDefaults.example` k = 0..3 has a row, every `schema.all_key_names()` shown for
  k = 0..5), `tests/test_editor_defaults.gd`, `test_editor.gd` (Add menu, inspector edit →
  outline/preview, undo rebuilds the inspector).

Changed from the plan / found on the way:

- Lambdas capture locals by value in GDScript: widget state that changes between signals
  lives in a small dictionary.
- Props (rock, plant, grass) are placed by `center`, logs by `points` (not `pos`).
- `params` is shown as a dict of every SimConfig export + species tunable (greyed defaults
  from the config/species), not "against the species defaults" separately.
- Add/remove of items is also in the inspector (list "+", item x, header Delete); the
  outline has only the Add menu (Delete key and duplicate come with M16e).

Next (M16e) needs: canvas edits must go through the same doc commands; the inspector then
rebuilds itself via `on_doc_changed` (not an own edit). During a drag, don't `set_at` on
every mouse move (each is an undo step and an inspector rebuild): move the gizmo overlay
and commit once on release (decision 6). `EditorDefaults.new_item` is the place-tool
factory; `EditorOutline.item_bounds` the hit test to replace with `GizmoGeometry`.

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

**Done (M16e).** What exists now:

- `editor/gizmos/gizmo_geometry.gd` (`GizmoGeometry`, pure, written by a subagent):
  `item_paths(data)` (every item in draw order), `shapes(data, item_path)` → shape dicts
  `{kind: circle|rect|polyline|polygon|point, path, role: body|area|clear, center,
  center_key, radius, radius_key ("" = not editable), rect, points, width, soft, hard}`
  for colonies, food, obstacles, ground regions, props, scatters (+ `clear`), debris, every
  positioned event type and camera keys (`pos` or `follow.near`); `shape_bounds`,
  `item_bounds`, `shape_contains(shape, p, tol)`, `hit_item(data, p, tol)` (smallest
  shape wins, later on ties), `handles(shape)` → `{role: center|radius|corner|point,
  index, pos}`, `hit_handle(data, item_path, p, tol)`, and edits that return the whole new
  item (ints, other keys and order kept): `moved`, `dragged(handle, to)`,
  `with_point_inserted`, `with_point_removed` ({} below 2/3 points), `snap`.
- `editor/gizmos/canvas_editor.gd` (`CanvasEditor`, GUI-free): `press/motion/release(at,
  tol, alt, double)`, `delete_selected`, `duplicate_selected`, `finish_poly`, `cancel`,
  `set_tool`, `set_selection(outline path)`, `item` (item path), `drag_item` (what a drag
  would write), `active_handle`, `snap`/`grid` (10), signals `select_requested(path|null)`
  and `redraw_requested`. A drag is one `doc.set_at(item_path, new_item)` on release.
  `TOOLS` (id, label, list, click|circle|rect|polyline|polygon) and `new_item(id, data,
  schema, at, extent)` for place tools; `insert_new(doc, list, value)` (also used by the
  Add menu; a plain ground material becomes `{"base", "regions"}`).
- `editor/gizmos/gizmo_layer.gd` (`GizmoLayer`, Node2D added with `EditorPreview.add_layer`):
  faint outlines of ground regions, event areas, scatter areas/clear shapes and camera
  keys; the selected item's shapes (the drag version while dragging), soft edge ring and
  handles (active one orange); a selected scatter's `Scatter.keep_clear_zones` from the
  built sim (hard red, reserve orange); a selected camera key's output frame; the item
  being placed.
- `ScenarioEditor`: tool bar over the preview (a toggle per tool, Snap), preview mouse and
  keys go to the canvas (Delete/Backspace, Ctrl+D, Enter, Esc only while the preview has
  focus, so inspector fields keep them); click selection uses `GizmoGeometry.hit_item`
  (was `EditorOutline.item_bounds` boxes).
- Tests: `tests/test_gizmo_geometry.gd` (subagent), `tests/test_canvas_editor.gd` (every
  place tool adds an item that builds, spans, polygon finish, region on a string ground,
  select/deselect, move in one undo step, click threshold, radius and point handles, snap,
  Alt insert and point delete, duplicate/delete, cancel), `test_editor.gd`
  (`test_editor_canvas_drag_place_and_keys`: mouse events through the editor, outline and
  inspector follow, Ctrl+D, Delete, tool buttons, Esc).
- Screenshots (windowed) of a selected polyline wall, scatter (clear paths and keep-clear
  rings), ground region, food, and a camera key (its frame) look right.

Changed from the plan / found on the way:

- Delete, Ctrl+D, Enter and Esc are handled only with the preview focused, not as menu
  shortcuts (Delete in an inspector field must not delete the item).
- "Topmost" = the smallest shape under the cursor (points win), later items on ties;
  big invisible areas (scatter rects, ground regions) would otherwise swallow clicks.
- Scatter `clear` shapes and the soft edge ring are edited but not created by a place tool
  (add a clear shape in the inspector; its handles then work on the canvas). The soft ring
  is drawn, not dragged. Twig rotation has no handle.
- A method named `snapped` on the canvas shadowed Godot's global `snapped()` and failed
  to parse ("too few arguments"): it is `snap_point`.
- The keep-clear zones come from the last built sim, so they lag an unbuilt edit by the
  rebuild delay.

Next (M16f) needs: `GizmoLayer` is where the "show materials" overlay and a scatter's
placed props / dropped-prop warnings go (it already draws a selected scatter's zones from
`preview.sim`). Partial rebuilds: `EditorPreview.rebuild()` builds everything
(`basic_forage` ~0.35 s); `doc.changed(path)` gives the path, so ground edits
(`["ground", ...]`) and scenery edits (`["scenery", ...]`) can be told apart there.

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

**Done (M16f).** What exists now:

- `ScenarioLoader.build` is `build_base` (obstacles, ground, hand-placed props, food,
  debris, colonies) + `add_scatters(sim, data, from = 0, marks = {})` (returns each
  scatter's `Scatter.Result` by its `scenery` index; `marks[k]` = `Scenery.mark()` just
  before scatter k) + `finish` (agent caps, events), and `set_ground(sim, data)`. Runs are
  unchanged (same calls in the same order). `Scenery.mark()` / `truncate(mark)` (removes the
  props added since, newest first, freeing their cells, and hands out the same ids again).
  `Scatter.Result.dropped_bounds` (bounds of each blocking prop dropped for connectivity).
- `EditorPreview`: `rebuild_kind(old, new)` over `SIM_KEYS` (the top-level keys the loader
  reads): `view` (no sim key changed: same sim, new WorldView), `scatter` (only `ground`
  and/or scatter entries changed, the hand-placed props list is the same) or `full`.
  `scatter_from(old, new)` (0 if the ground changed, else the first differing `scenery`
  index): a `scatter` rebuild truncates to that scatter's mark, remakes the ground if it
  changed and runs the scatters from there. State: `last_kind`, `rescattered_from`,
  `partial` (false forces full), `scatter_results`, `scatter_marks`, `scatter_mark`,
  `hand_prop(index)` (the Prop built from a hand-placed entry, matched by params), `same(a,
  b)` (typed deep equality). Status line says Built / Rebuilt ground and scenery / Redrawn,
  the prop count and "N blocking props dropped by scatters".
- `GizmoLayer`: a selected scatter's placed props tinted (outline or canopy), their blocking
  cells, and each dropped prop's bounds crossed out in red ("dropped: cut a colony off");
  a selected hand-placed prop's blocking cells; `show_materials` draws
  `GroundSwatches.image(sim.ground)` (cached per GroundMap) under the gizmos.
- `editor/ground_swatches.gd` (`GroundSwatches`, subagent): `COLORS`, `color`, `icon`,
  `image(ground)` (weight-blended flat colours, ~20 ms), `is_material_choice`. Inspector
  material dropdowns (and material-keyed map key choosers, e.g. scatter `prefer`) show the
  swatches; `ground_region.noise.scale` limits 20–2000 (slider).
- Outline drag-to-reorder (subagent): `EditorOutline.drop_move(from, onto, section)` and
  `editor/outline_drag.gd` (`OutlineDrag`, Tree drag forwarding) → `doc.move_item(...,
  "Reorder")`, then selects the moved item. Any list items of the same list.
- Inspector: **Reseed** in a scatter item's header (`reseed_scatter(path)`, editor's own RNG).
  Editor: **Materials** toggle on the tool bar, `--materials` arg (bare `--flag` args parse).
- Tests: `tests/test_editor_rebuild.gd` (`rebuild_kind`, `scatter_from`, truncate restores
  cells/mask, partial == full for basic_forage, meadow_forage, colony_founding,
  two_species, maze over four edits each (ground + all scatters, last scatter reseeded,
  first scatter removed, scatter appended: cells, prop mask, props incl. ids/seeds/cells,
  ground weights, results per scatter, then state hash after 20 ticks), view-only keeps the
  sim, hand props and results mapping), `test_ground_swatches.gd`,
  `test_editor_outline.gd` (drop_move), `test_editor.gd` (reorder drop + undo; the
  debounce test now edits the seed, since an unchanged document keeps its sim),
  `test_inspector.gd` (swatches, reseed), `test_scatter.gd` (dropped bounds).
- Screenshots (windowed): meadow_forage with a selected scatter (tinted props, zones,
  Reseed) and a selected log (blocking cells); colony_founding with Materials on.

Changed from the plan / found on the way:

- Hand-placed prop edits rebuild everything: colonies read `prop_near`/`is_blocked` when
  siting entrances and middens, so a partial rebuild could differ from a full one. Scatters
  come after the colonies, so redoing them (and the ground, which only scatters read) on the
  kept sim is exact.
- The ~150 ms target isn't reached for scatter edits: the scatter itself is the cost
  (meadow ~0.5 s). Partial rebuilds skip the colonies (~0.75 s for founding nests) and
  earlier scatters; see the progress log for numbers.
- Obstacle `look`s add props before the hand-placed ones, so `hand_prop` matches by params
  rather than by position in the list.
- Dropping an outline row onto a section row isn't supported (only between items).

Next (M16g) needs: the preview's sim is never stepped and may be patched in place by
partial rebuilds, so play must build its own sim through `ScenarioPlayer.setup_data`
(don't step `preview.sim`). A camera / render / presentation edit is a `view` rebuild
(~35 ms), so timeline edits of those keys are cheap; `events` edits are `full`.

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

**Done (M16g).** What exists now:

- `editor/timeline/timeline_model.gd` (`TimelineModel`, pure, written by a subagent):
  `time_map(data, config)` → `TimeMap` (`points`, `jumps`, `warmup`, `tick_rate`, `duration`,
  `config`; `tpf_at` = `ScenarioPlayer.ticks_per_frame_at`, `sim_time_at(video_t)` (warmup +
  exact integral of the tpf ramps + jumps), `video_time_at(sim_t)` (exact inverse; a sim time
  inside a jump maps to the jump; INF if never reached)); `tracks(data, map)` → always
  `camera` (or `camera_surface` + `camera_nest`), `speed`, `layout`, `captions`, `fades`,
  `grade`, `story_marker`, `events` (`{id, label, kind: points|spans|curve, clock, list,
  items: [{path, t (video s), until, has_until, label, sim_t}]}`); `hit(track, t, tol)` (until
  edge, then nearest t, then shortest span body); edits returning the whole new item:
  `moved` (events get the sim time of the video time; spans keep their length), `resized`,
  `new_item(track_id, data, t, map, extra)` → `{path, value, insert}` (insert=false sets a
  whole new list, e.g. a number `ticks_per_frame` becomes `[{t: 0, tpf: old}, new]`),
  `camera_key_here(center, view_world, frame, t)`, `tick_step`, `snap_time`.
- `editor/timeline/timeline_panel.gd` (`TimelinePanel`, VBoxContainer): transport bar (Play /
  Pause, Stop, speed 0.25–8x, time "video / duration (sim s)", seek progress bar, Key here,
  Fit) and a drawn canvas (gutter labels, ruler, a row per track, tpf curve and jump marks,
  spans with labels, point labels clipped to the next item, playhead). Testable input:
  `press(at, double, shift)`, `motion`, `release` (ruler = playhead; item = select + drag;
  span edge = resize; double click on empty row = `add_at(track_id, t)`), `delete_selected`,
  `set_playhead(t, seek)`, `toggle_play`, `stop`. A drag is one `doc.set_at` on release. It
  refreshes itself on `doc.changed`. Signals `select_requested(path)`, `play_view(on)`;
  `key_here` Callable (set by the editor from the preview camera).
- `editor/play_preview.gd` (`EditorPlay`, Control): a `ScenarioPlayer` (`setup_data` on a deep
  copy) in a SubViewport of the output frame size, shown with a keep-aspect TextureRect.
  `load_data`, `play`, `pause`, `speed`, `seek(t)` (forward from here, or rebuild when going
  back; `SEEK_BUDGET_MS` of whole 1/60 s frames per editor frame), `seeking`,
  `seek_progress`, `stop`, `step_until`; signals `time_changed`, `seek_done`, `stopped`.
  Always whole video frames, so it matches a recording (tested: same state hash as a
  frame-by-frame player).
- `ScenarioEditor`: a VSplit with the timeline under everything; the static preview and play
  view share the centre (`_show_play`); any doc change stops play; timeline selection goes
  through `_on_canvas_select`; `--play=<s>` opens the play view paused there (screenshots
  wait for the seek).
- `EditorOutline`: a "Speed" section (when `ticks_per_frame` is a list) with its points, and
  under Render rows for Captions, Fades, Grade, Story marker and Layout modes with their
  items, so timeline items have outline rows (selection stays on the item).
- Tests: `tests/test_timeline_model.gd` (subagent, 32: mapping incl. against a real player
  with warmup, ramp and jump, tracks, hit, edits), `tests/test_timeline.gd` (panel ruler,
  drag = one undo step, resize, event drag in video time, add incl. new lists and key here,
  delete; play matches a frame-by-frame run and seeks back; editor: play view, edit stops
  play, timeline selection), `test_editor_outline.gd` (timed rows).
- Screenshots (windowed): basic_forage static with the timeline; basic_forage playing at 30 s
  (trails); leafcutter_life playing at 20 s and 24 s (nest view, caption, dense tracks).

Changed from the plan / found on the way:

- Scrubbing while playing seeks on mouse release (dragging only moves the playhead line), so
  a drag backwards rebuilds once, not on every mouse move.
- Camera `follow`/`fit` variants and `ease` are edited in the inspector (the variant
  selector from M16d); the timeline adds `pos` keys (Key here). No new schema keys.
- Point labels overlap on dense tracks (leafcutter_life's cameras): each label is clipped to
  the gap before the next item and dropped when under 24 px; zoom the ruler to read them.
- Float equality of x positions hid labels (a point's own x recomputed differs by ~1e-5):
  compare times, not pixels.

Next (M16h) needs: the timeline's `playhead` is the "from playhead" start time for Run
(`--at=`); `EditorPlay` is independent of the run/record processes. The run bar and Record
dialog can sit in the timeline's transport bar or the menu bar.

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

**Done (M16h).** What exists now:

- The record pipeline is **GDScript** (open question answered by the user: for
  portability, no bash): `editor/launch_commands.gd` (`LaunchCommands`, pure, written by a
  subagent) builds `run_args(settings, scenario_path, project_dir, playhead, random_seed)`
  for `main.tscn` and `record_plan(settings, scenario_path, data, project_dir, stamp)` →
  `{ok, error, frame_size, format, seed, name, out_dir, out_path, capture_dir, capture,
  override_cfg, record_args, encode_args, keep_frames, expected_frames}` (the old
  `record.sh`/`encode.sh` names, `override.cfg` text and ffmpeg arguments, plus
  `-progress pipe:1 -nostats`); `RUN_DEFAULTS`, `RECORD_DEFAULTS`, `with_defaults`, `num`,
  `stamp`, `scenario_name`, `size_label`. `editor/record_job.gd` (`RecordJob`) runs a plan
  without blocking: writes `override.cfg` (refuses if one exists: one recording at a time;
  removed as soon as the recorder prints its "Recording ...: N frames" line, and always at
  the end), runs the recorder with `OS.execute_with_pipe`, reads `frame n / total`, then
  ffmpeg reading `frame=n`, removes the capture; `poll()`, `wait(timeout)`, `cancel()`
  (kills, removes capture and partial mp4), `fraction()`, `status_text()`, `log_lines`,
  signals `output(line)`, `finished(ok, message)`, `remove_tree(dir)`.
  `tools/record.gd` (SceneTree CLI: `<scenario|path> [seed] [seconds] --format= --quality=
  --size= --captions=0 --start= --out_dir= --out= --keep_frames=1 --ffmpeg=`);
  `tools/record.sh` now only maps `FORMAT MJPEG_QUALITY SIZE CAPTIONS START OUT OUT_DIR
  KEEP_FRAMES FFMPEG` onto it. A/B: the old bash pipeline and the new one give
  byte-identical MP4s (same md5, basic_forage seed 5, 1920×1080 AVI). `tools/encode.sh` and
  `tools/frame_size.sh` stay (encode by hand; `stills.sh`).
- `scenes/record.gd`: `--progress=<frames>` (progress line interval, default 300; the
  pipeline passes 10). `--scenario=` of both scenes takes an absolute `.json` path (already
  worked via `path_for`; tested, also `user://`).
- `editor/launch_settings.gd` (`LaunchSettings.load_for/save_for(cfg, "run"|"record",
  doc.file_path, ...)`): last settings per scenario in `user://editor_settings.cfg`
  (section `run`/`record`, key `by_scenario`: {file path: settings}).
- `editor/run_dialog.gd` (`RunDialog`) and `editor/record_dialog.gd` (`RecordDialog`,
  settings page with a live summary from `record_plan`, progress page with log, Cancel,
  Open folder, Play, New recording), both written by a subagent.
- `ScenarioEditor`: **Run** menu (Run F5, Stop run Shift+F5, Run options..., Record...
  Ctrl+R) and the same as buttons in the top bar; `run()` writes
  `user://editor_runs/run/<name>.json` (`write_run_copy(kind)`, `run_name()`) and launches
  `main.tscn` (`launch_process` Callable, `run_pid`, `stop_run()`); `open_record()`,
  `start_recording(settings, set_output)` (copy under `record/`, optional undoable
  `output.size` edit, a `RecordJob` polled in `_process`); status line shows the run and
  the recording; quitting with a recording running asks to cancel it. `project_dir`,
  `godot_path`, `runs_dir` are overridable (tests).
- Tests: `tests/test_launch_commands.gd` (subagent), `tests/test_launch_dialogs.gd`
  (subagent), `tests/test_launch.gd` (path = name hash for loader and player, settings
  store, job failure paths and progress parsing, editor Run with a fake launcher, editor
  Record plan + output size + settings, and two long tests, `test_record_pipeline_draft`
  (`tools/record.gd` on a path, 1920×1080 AVI) and `test_record_from_the_editor`
  (`start_recording` with an unsaved edit, 1080×1920 AVI), both checked with ffprobe for
  size, 60 fps and 120 frames; both pass).
- `--dialog=run|record|record_now` (editor) opens the dialogs / starts a 3 s AVI draft for
  screenshots (the screenshot waits for 60 recorded frames, then cancels). Screenshots of
  the Run options, Record settings and the progress page look right.
- Found on the way: after `OS.kill` on Windows the capture file stays locked for a moment,
  so `cancel()` waits for the process to exit and retries removing the capture (up to 3 s).
  The recorder's "Window is (1080, 1325) but the output frame is ..." warning on a small
  screen is old (the bash pipeline printed it too); the video is still full size.

Changed from the plan:

- No Git Bash from the editor: the editor, `tools/record.gd` and `tools/record.sh` all run
  `RecordJob`. `override.cfg` is still how the recorder gets its window size (it is removed
  once the recorder has started, so a Run started during a recording is unaffected except
  in that first second).
- Run options are a dialog (Run menu / top bar), not a bar in the timeline.

Next (M16i) needs: validation warnings before Run/Record can hook into `run()` and
`start_recording()`; the shortcuts F5, Shift+F5 and Ctrl+R exist already.

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

**Done (M16i).** What exists now:

- `editor/scenario_validator.gd` (`ScenarioValidator`): `validate(data, schema, sim)` =
  `schema_issues` + `SceneChecks.issues`; an issue is `{path, severity ("error" |
  "warning"), message}`; helpers `issue`, `count`, `under(issues, path)`, `summary`
  ("2 errors, 1 warning"), `format` (one line). Schema checks walk the schema like
  `unknown_paths`: any_of with no matching form, variant tag missing or unknown, dict not
  an object, missing required keys, unknown keys (**warning**, they are kept), map keys
  not in `keys_from` (e.g. castes), list not a list, scalars (number / whole number /
  range from `limits`, bool, string, enum incl. Registry choices, vec2, size (not
  negative), rect, points, colour), and `output.size` (`OutputFrame.valid_size`).
- `editor/scene_checks.gd` (`SceneChecks`, by a subagent): nests, food and surface portal
  ends outside the world or in a wall or water (errors; walls and portals need the built
  sim, the world size is `sim.config.world_size`, else the default config's), events whose
  sim `t` is after `time_map.sim_time_at(duration)`, video-time items (camera keys,
  captions, fades, grade, layout modes, story marker) after `duration`, nests closer than
  max(60, sum of `nest_params.radius`), caption boxes (measured as `Presentation` places
  them) outside `OutputFrame.safe_rect()` (warnings).
- Editor: `validate()` after every preview build (`status_changed`), with the preview's
  sim; **Problems** list under the inspector (errors first, click selects the item),
  outline rows (and their sections) coloured red / orange with the messages as tooltip,
  `EditorPreview.issue_marks` outlines the items in the preview. File Save / Save As, Run
  (F5) and Record... (Ctrl+R) go through `_check_then(verb, action)`: with errors a
  dialog lists them and "<verb> anyway" goes on (the API calls `run()`,
  `start_recording()`, `_save_to()` don't ask). Split offsets (outline, inspector,
  timeline) are saved in the settings file's "layout" section when dragged and restored;
  started without `--scenario=` the editor reopens the last file (`--new` for a new one).
  Shortcuts and schema tooltips already existed (M16c-h).
- `tests/validate_scenarios.gd` (CLI, exit 1 on errors); every shipped scenario is clean.
- `LaunchCommands.record_plan`: an absolute `file_name` (`--out=`, `OUT=`) is used as it is.
- Tests: `tests/test_validator.gd` (schema checks, shipped scenarios in 4 groups plus a
  test that the groups list every file, editor problems list / marks / selection / undo,
  warning before Run with a fake launcher, layout and last file), `tests/test_scene_checks.gd`
  (subagent: one test per check, malformed data, shipped scenarios).
- Acceptance (a debug script driving the editor's own place tools and commands, since
  deleted): from `--new`, Colony tool (second colony, another species), two Food drags,
  Scatter rect, Rain circle (t = 3), Camera key tool plus Add camera key, Add caption,
  output 1920×1080; no issues; saved; recorded from the editor with `start_recording`
  (AVI, 5 s): 1920×1080, 60/1 fps, 300 frames, 5.0 s. The saved JSON by path through
  `tools/record.sh` (AVI, 3 s): 1920×1080, 60 fps, 180 frames; `tools/screenshot.sh` on the
  path (main.tscn) shows it in the landscape window. An editor screenshot of a broken copy
  (odd output size, unknown species, food outside the world, radius 0, camera key at 25 s)
  shows the Problems list, red / orange outline rows and preview marks.

Changed from the plan:

- Interacting with the Run from the editor was not repeated by hand (the real launch was
  checked in M16h; here Run is tested with a fake launcher and the file with main.tscn).
- Found: a colony with an unregistered species makes `ScenarioLoader` assert (script error
  in the preview build); the editor survives and the validator reports it, but the loader
  still asserts. Left as it is.

M16i done. Next: M16j (world size per scenario).

### M16j: world size per scenario

Goal: a scenario can set the size of its surface world, e.g. a 1920×1080 landscape world
for a landscape frame, or a larger 2160×3840 world to film with a moving camera. Today
every scenario runs on `SimConfig.world_size` (1080×1920), a global setting that the
scenario format, the editor and the tuning panel can't change. The editor lets you set it
(an always-shown **World** row, like **Output**) and shows the new bounds straight away.

Format: `"world": {"size": [w, h]}`, in world units. Absent means `SimConfig.world_size`, so
every existing scenario builds exactly as before. A dictionary leaves room for more later
(e.g. `cell_size`), but only `size` goes in this phase. Limits: both sides a multiple of 8
(a whole number of 4-unit sim cells and 8-unit ground texels) and 256–4096. The output
frame is separate and unchanged. The underground nest layers keep their own
`nest_params.underground.size`.

**Hashes.** The aim is that no hash moves. A scenario without `"world"` must build the
same Simulation as now: same grids, same RNG draws, same order. Check that with the
full suite before any other change: `test_layers` `SINGLE_LAYER_HASHES`,
`test_native` parity and the determinism tests. If a hash does move and can't be avoided
(e.g. code that read `config.world_size` and now reads `sim.world.size` turns out to
differ somewhere), re-record `SINGLE_LAYER_HASHES` and any other stored hashes. Then say in
the plan and the commit message which ones moved and why. Never re-record without
finding the cause first.

Design: the size is kept on the Simulation, not by changing the config. `ScenarioPlayer`,
the editor preview and the timeline share one preloaded `default_config.tres`. The tuning
panel's Save writes `sim.config` back to that file, so neither mutating the shared
resource nor handing the sim a `duplicate()` (which has no `resource_path`) is safe.

1. `sim/simulation.gd`: `_init(config, registry, seed, world_size := Vector2i.ZERO)`
   (zero means `config.world_size`). The surface `SimLayer` uses it. `sim.world.size` (the
   surface layer's) becomes the one source of truth, e.g. the whole-world rain area at
   `simulation.gd:902`.
2. `sim/scenario_loader.gd`: a static `world_size(data, config) -> Vector2i` (the scenario's
   `world.size` or the config's). `build_base` passes it to `Simulation.new`. `set_ground`
   uses `sim.world.size`.
3. Replace every other read of `config.world_size` that means "this sim's world" with
   `sim.world.size` / `sim.layers[0].world.size`. Known places:
   - `render/world_view.gd:74,78` (ground quad and shader), `render/rain_renderer.gd:68`;
   - `editor/preview.gd:272` (`world_size()` from the document via
     `ScenarioLoader.world_size`, so the bounds follow an edit before the rebuild ends);
   - `editor/timeline/timeline_model.gd:341`, `editor/scene_checks.gd:54-58`
     (`_world_size` from `sim.world.size`, else the document, else the default).

   Then grep `sim/ render/ species/ scenes/ editor/` for `world_size`, `1080`, `1920`, `540`
   and `960` for other assumptions, e.g. default camera centre, "whole world" areas,
   `--new` template positions and shader uniform defaults (all set at runtime today;
   confirm). `native/src` takes grid width and height per layer as arguments, so it
   should need no change. Confirm this, and keep `tests/test_native.gd` parity over a
   non-default size (below).
4. Schema (`editor/schema/core_schema.gd`): `"world": F.dict({"size": F.size([1080, 1920],
   "World size in world units (multiples of 8, 256-4096)")}, "The surface world")`. Keep
   the default in step with `SimConfig.world_size` (read it, don't copy the numbers if the
   schema can).
5. Editor:
   - `EditorOutline.SECTIONS` gets `["world", "World", true]`, shown before Output. Absent
     sections are already editable in the inspector (`_absent_section`, added after
     M16i), with the first edit creating the section.
   - A `world` edit needs a **full** rebuild: check the rebuild classifier in
     `editor_main.gd` / `EditorPreview` (M16f). Fit world (Home) and the white bounds
     follow the new size.
   - A preset menu on `world.size` like the output one is optional. If added, offer the
     default, landscape 1920×1080, square 1920×1920 and large 2160×3840.
6. Validation (`editor/scenario_validator.gd`, `editor/scene_checks.gd`):
   - `world.size` must be multiples of 8 and within 256–4096 (error).
   - A world over ~4× the default area gets a warning about speed (pheromone diffusion
     and scatter cost scale with area). Set the threshold from the bench numbers below.
   - Existing checks (nest, food or portal outside the world) then catch items left
     outside after shrinking the world.
7. Player and tools: nothing new to pass. `main.tscn`, `record.tscn`, `tools/record.sh`,
   `screenshot.sh` and `bench.gd` all build through `ScenarioLoader`. The tuning panel
   already skips `STRUCTURAL` keys, and its Save must still write only
   `default_config.tres` values: check that a run with a non-default world doesn't save
   `world_size`.

Files: `sim/simulation.gd`, `sim/scenario_loader.gd`, `render/world_view.gd`,
`render/rain_renderer.gd`, `editor/schema/core_schema.gd`, `editor/editor_outline.gd`,
`editor/preview.gd`, `editor/editor_main.gd` (rebuild classification),
`editor/timeline/timeline_model.gd`, `editor/scene_checks.gd`,
`editor/scenario_validator.gd`, plus anything the grep in step 3 finds. Tests as below.
Docs: README (the format section's `output` paragraph, "The world size is separate",
plus a `world` entry), `manual.md` (the outline list, a "World size" part next to "The
output frame", the walkthrough's landscape step, and validation), and the M16 plan.

Verification:

- Full suite with no hash changes (or the moves explained, as above).
- `tests/fixtures/scenarios/wide_world.json`: a 1920×1080 world with a colony, food, a
  ground region, a scatter and a rain event with no area. Also tests for:
  - it builds with `sim.world.size == (1920, 1080)`, pheromone grid 480×270 and a
    ground map of the right size;
  - ants use the whole width (some ant x > 1080 after a run);
  - rain covers the whole world;
  - it's deterministic (same hash twice);
  - GDScript and native give the same hash. Add it to `test_native`'s parity list (or its
    fixtures loop), and check `test_core_generic`/fixture discovery still passes.
- `test_scene_checks`: `test_world_size_from_sim` reads `sim.world.size`, plus a case where
  food at x = 1500 is fine in the wide world and an error in the default one.
- `test_validator`: world size not a multiple of 8, too small, too large, and the
  large-world warning.
- `test_editor_outline` and `test_inspector`: the World row is always shown, and a size set
  on a scenario without `world` creates it (undo removes it).
- An editor test (or `test_editor_rebuild`): editing `world.size` rebuilds fully and the
  preview's world rect matches.
- `test_config`: the default stays 1080×1920 and nothing writes `world_size` into
  `default_config.tres`.
- Bench (`tests/bench.gd`) on `wide_world` and a 2160×3840 copy (a debug fixture, deleted
  afterwards): ticks/s next to `basic_forage`, noted in this section, sets the warning
  threshold.
- Stills: `tools/screenshot.sh` of the wide world at 1920×1080 output (`--size=1920x1080`,
  zoom 1) shows ground, scatter and ants filling the frame with no black band or seams at
  the old 1080 edge. Also an editor screenshot with the World row selected.

Hands on: `world` is a normal scenario section. M15l (founding frame budget and PNG
finals) is still open and independent.

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
  unreliable. Answered in M16h: GDScript (portability), and `record.sh` wraps it.

## Progress log

- M16a: schema (every option read by code; 3 schema areas filled by subagents against
  the coverage tests), `ScenarioJson`, `ScenarioDoc`, shipped scenarios reformatted
  once; README documents the options found only in code and the `output` section.
- M16b: `OutputFrame` and `--size=`/`SIZE=` through the player, scenes and tools; side-by-side
  split; default frame pixel-identical (tests of the old rects, before/after stills).
- M16c: editor scene (menus, file handling, recent files, unsaved prompt), static preview
  with frame overlay and pan/zoom, outline with preview selection (outline model and
  recent files by a subagent); phorid renderer null crash fixed.
- M16d: schema-driven inspector (every field type, greyed defaults with reset, variant and
  any_of switches, lists/maps, edit as JSON), Add menu; `EditorDefaults` (new items,
  variant switching, full examples for the every-key test) by a subagent.
- M16e: canvas gizmos (select, move, handles, Alt insert, Delete, Ctrl+D, snap), place tools
  tool bar, scatter keep-clear zones and camera-key frame overlays; `GizmoGeometry` (shapes,
  handles, hit tests, edits) by a subagent.
- M16f: staged `ScenarioLoader` build and partial preview rebuilds (view / ground+scatters
  from the first changed one / full), scatter props, blocking cells and dropped-prop warnings,
  Reseed, materials overlay; swatches and outline drag-to-reorder by subagents. Rebuild
  times in ms (full / ground edit / last scatter reseeded / render-only edit): basic_forage
  ~300 / 276 / 199 / 34, meadow_forage 953 / 969 / 415 / 36, two_species 592 / 599 / 246 / 37,
  colony_founding 1651 / 915 / 370 / 36, harvester_founding 1261 / 558 / 272 / 36,
  leafcutter_life 1389 / 557 / 285 / 38, nuptial_flight 1412 / 503 / 258 / 34. (Before:
  every edit was a full build, WorldView setup ~33 ms of it.)
- M16g: timeline panel (every timed list on one video-time ruler, events via the speed
  schedule; select, drag, resize, add, delete, Key here) and play preview (a real
  ScenarioPlayer in the output frame, seek with progress); `TimelineModel` (time mapping,
  tracks, hit tests, edits) by a subagent.
- M16h: the record pipeline reimplemented in GDScript (`RecordJob`, `tools/record.gd`;
  `record.sh` a wrapper; byte-identical output to the bash version), Run (main.tscn on a
  temporary copy) and Record (background job, progress, cancel) from the editor, settings
  per scenario; command lines and the two dialogs by subagents.
- M16i: `ScenarioValidator` (schema checks) and `SceneChecks` (by a subagent), Problems list,
  outline and preview marks, warnings before Save / Run / Record, `validate_scenarios.gd`,
  every shipped scenario clean; remembered panel sizes and last file; acceptance scenario
  built with the editor's tools and recorded at 1920×1080; README editor guide (subagent).
