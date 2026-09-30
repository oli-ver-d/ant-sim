# Scenario editor manual

The scenario editor is a Godot scene in this project (`scenes/editor.tscn`) for making and
changing the scenario JSON files in `scenarios/`. It opens a scenario, shows it drawn by the
simulation's real loader and renderers, lets you edit every option of the format, previews it
running, and saves it back to JSON. You can also **run** a scenario interactively and **record**
videos from it.

This manual covers the whole editor. `README.md` is the reference for what each scenario
option does in the simulation ("Scenarios" section). Every field in the editor also has a
tooltip with its help text.

Contents:

1. [Starting the editor](#1-starting-the-editor)
2. [The window](#2-the-window)
3. [Files](#3-files)
4. [The outline](#4-the-outline)
5. [The inspector](#5-the-inspector)
6. [The preview and canvas editing](#6-the-preview-and-canvas-editing)
7. [Place tools](#7-place-tools)
8. [Ground and scenery](#8-ground-and-scenery)
9. [The timeline](#9-the-timeline)
10. [Play preview](#10-play-preview)
11. [The output frame](#11-the-output-frame)
12. [Running a scenario](#12-running-a-scenario)
13. [Recording videos](#13-recording-videos)
14. [Validation and the Problems list](#14-validation-and-the-problems-list)
15. [Keyboard and mouse reference](#15-keyboard-and-mouse-reference)
16. [Walkthrough: a scenario from scratch](#16-walkthrough-a-scenario-from-scratch)
17. [Walkthrough: the underground nest view](#17-walkthrough-the-underground-nest-view)
18. [Command line options](#18-command-line-options)
19. [Settings and files the editor keeps](#19-settings-and-files-the-editor-keeps)
20. [Tips and troubleshooting](#20-tips-and-troubleshooting)

---

## 1. Starting the editor

You need Godot 4.7 on your PATH as `godot` (or set `GODOT=`); in Git Bash:
`export PATH="/c/Tools/Godot:$PATH"`. Recording also needs `ffmpeg` on the PATH.

```bash
tools/editor.sh                               # reopen the last file (a new scenario the first time)
tools/editor.sh --new                         # start a new scenario
tools/editor.sh --scenario=meadow_forage      # open a shipped scenario by name
tools/editor.sh --scenario=D:/work/mine.json  # open any .json file by path
```

`tools/editor.sh` is the same as `godot --path . res://scenes/editor.tscn -- <options>`.

The editor opens in a landscape window (1600×900, or smaller to fit the screen). It uses the
window's own pixels and doesn't change how the other scenes (the player, the recorder) are
set up.

A new scenario starts from a minimal template: name `untitled`, seed 1, a 20 s video and
one colony of the first registered species at (540, 1500), with empty food and obstacle lists.

---

## 2. The window

```
+-----------------------------------------------------------------------------------+
| File  Edit  View  Run | Fit world  Fit frame | Run  Stop  Run options  Record...  |
+---------------+-------------------------------------------+-----------------------+
| Add...        | tool bar: Select Colony Food Wall ... Snap | selected item's title |
|               |   Materials                                |                       |
|  Outline      |                                            |  Inspector            |
|  (sections    |          Preview                           |  (a form for the      |
|   and items)  |  (the world, the output frame, gizmos)     |   selected row)       |
|               |                                            |                       |
|               |                                            |  Problems: ...        |
|               |                                            |  (validation list)    |
+---------------+--------------------------------------------+-----------------------+
| Timeline: Play Stop 1x  0.00 / 20 s (sim 0 s)  Key here  Fit                      |
|   ruler, one row per timed list (camera, speed, layout, captions, events ...)     |
+-----------------------------------------------------------------------------------+
| status line: file, modified, build time and counts, run and recording progress    |
+-----------------------------------------------------------------------------------+
```

- **Top bar**: the menus, then buttons for the most used commands (fit, run, record).
- **Outline** (left): the document as a tree of sections and items. **Add...** above it adds
  new items.
- **Preview** (centre): the scenario as it will look at the start of the run, with the tool
  bar above it. While the timeline plays, the play view takes its place.
- **Inspector** (right): a form with every option of the selected row. Below it is the
  **Problems** list.
- **Timeline** (bottom): everything timed in the scenario on one video-time ruler, plus the
  playback controls.
- **Status line** (bottom edge): the file (and "(modified)"), what the last preview build did
  and how long it took, how many colonies, food sources, ants and props there are, dropped
  scatter props, and the state of a run or recording.

You can drag the dividers between the outline, preview, inspector and timeline. The editor
remembers where you put them.

The window title shows the file name, with ` *` when there are unsaved changes.

---

## 3. Files

**File** menu:

| Item | Key | What it does |
|---|---|---|
| New | Ctrl+N | A new scenario from the template. |
| Open... | Ctrl+O | Opens a scenario JSON file. |
| Open Recent | | The last 10 files you opened or saved. |
| Save | Ctrl+S | Saves to the current file, or asks for a name (Save As) if it has none. |
| Save As... | Ctrl+Shift+S | Saves to a new file, which then becomes the current one. |
| Revert | | Reloads the file from disk, dropping your changes. |
| Quit | Ctrl+Q | Closes the editor. |

If there are unsaved changes, New, Open, Revert, Quit and closing the window ask first:
**Save**, **Discard** or **Cancel**. Quitting while a recording is running asks whether to
cancel the recording. A run started from the editor is a separate program and keeps running.

**Saving.** Files are written in the project's JSON style: tabs, keys in a fixed order per
section, whole numbers written as integers, short arrays and small objects on one line.
Opening a shipped scenario and saving it without changes leaves the file byte-for-byte the
same, so your diffs show only what you changed.

**Keys the editor doesn't know are kept.** If a file has keys that aren't part of the format
(notes, options from a newer version), they are kept and saved unchanged. They show in the
inspector as raw JSON fields and in the Problems list as warnings.

**Only what you set is saved.** Options you haven't set aren't written to the file; the
simulation uses their defaults. See [the inspector](#5-the-inspector).

**Undo and redo.** Every change is undoable: form edits, canvas drags, placing, deleting,
reordering and timeline edits. Use **Edit → Undo** (Ctrl+Z) and **Redo** (Ctrl+Y). A whole
drag counts as one edit.

---

## 4. The outline

The outline lists the document's sections, in this order:

- **Scenario**: the top-level settings (name, description, seed, duration, warmup,
  max agents and so on).
- **Speed**: the `ticks_per_frame` schedule, with a row for each point when it's a schedule.
- **Colonies**, **Food**, **Obstacles**, **Ground** (with its regions), **Scenery** (props and
  scatters), **Debris**, **Events**.
- **Camera**: the keyframes, or the **Surface camera** and **Nest camera** tracks for a
  scenario with split cameras.
- **Render**: with rows for captions, fades, grade, layout modes and story-marker windows.
- **World**: the size of the surface world.
- **Output**: the output frame.
- Any other top-level keys the file has.

Scenario, Colonies, Food, Obstacles, Ground, World and Output are always listed. The other sections appear
once the file has them; add them with **Add...**, the place tools or the timeline.

Items are labelled so you can tell them apart, e.g. `Colony 0: harvester @ 540,1500`,
`Food 1: food_pile @ 800,500`, `Event 0: rain @ 3s`, `Camera 1: 25s pos 540,960`.

- **Click a row** to select it. The inspector shows its form, the preview outlines the item
  (yellow) and the timeline highlights it if it's timed.
- **Drag a list item's row** onto another row of the same list to reorder it. Order matters
  for ground regions (later ones paint over earlier ones) and is otherwise just tidiness.
- Rows with validation problems are **red** (errors) or **orange** (warnings), and so is the
  section they're in. Hover over the row to read the messages.

**Add...** (above the outline) adds a new item to the selected row's section. With the
**Scenario** row selected, it offers every section. Actions: Add colony, food, obstacle,
ground region, prop, scatter, debris, event, camera key (or surface / nest camera key),
caption. The new item gets sensible defaults, is placed at the centre of the preview's
current view, and is selected so you can edit it straight away.

---

## 5. The inspector

The inspector is a form for the selected row, built from the scenario schema, so every
option of the format can be edited, including ones no shipped scenario uses.

**Set and unset options.** Options the file doesn't set are shown **greyed out** with their
default value. Editing one sets it in the file. The **x** next to a set option removes it
again (back to the default). This keeps files small: they only contain what differs from the
defaults.

**Field types:**

| Kind | Editor |
|---|---|
| Number | A text box (whole-number fields use a spin box). Values outside the allowed range show in the Problems list. |
| True/false | A check box. |
| Text | A text box. |
| Choice (enum) | A drop-down. Species, food types, nest types, scenery types, states and so on come from what the project has registered. Castes follow the colony's species. |
| Position `[x, y]`, size `[w, h]`, rect `[x, y, w, h]` | One box per number. |
| Points | A list of `[x, y]` rows (easier to edit on the canvas). |
| Colour | A colour button (hex string, name or `[r, g, b(, a)]`). |
| Material | A drop-down with a colour swatch per ground material. |
| Object | A foldable group of its own fields. |
| List | Items with add, move up/down and remove buttons. |
| Map (free keys, e.g. castes → counts) | One row per key, plus a row to add a key. |
| Typed object (e.g. obstacle `shape`, food or event `type`) | A type selector. Switching the type swaps in the new type's fields and keeps the values of fields both types share. |
| One of several forms (e.g. `ticks_per_frame` as a number *or* a schedule) | A form selector, then the chosen form's editor. |
| Anything else, and unknown keys | Raw JSON in a text box. |

`output.size` also has a preset menu (portrait, landscape, square, 4:5, 4K); see
[the output frame](#11-the-output-frame).

**Edit as JSON** (top of the inspector) edits the whole selected item as JSON text, for
pasting or bulk changes. **Delete** (next to it) removes the selected item.

**Colony options** worth knowing: `species`, `nest` position, `population` (starting ants
per caste), `nest_type` (another nest than the species' own), `release_per_second`,
`nest_params` (the fields depend on the nest type: entrance style, midden, underground and
so on), `params` (every simulation setting and species tunable, overridable for this colony),
`state_params` (behaviour wiring per state) and `channels` (pheromone channel settings).
README "Scenarios" explains what each does.

Hover over any field name for its help text.

---

## 6. The preview and canvas editing

The preview is the scenario built by the simulation's real loader and drawn by the real
renderers, as it is at the first frame (after `warmup`, if the scenario has one). It isn't a
running simulation: nothing moves until you [play](#10-play-preview) it.

**What's drawn:**

- the world (white bounds) and everything in it, as it will look;
- the **output frame** (blue rectangle, labelled `output 1080x1920 (tiktok)`) where the
  first camera keyframe puts it, with the platform's unsafe margins shaded red;
- things the renderer doesn't show, as faint outlines: ground regions, event areas,
  scatter areas and camera keys;
- the selected item in a yellow outline, with its **handles**;
- items with problems in a red or orange outline.

**Navigating:** mouse wheel zooms at the cursor; middle or right drag pans. **Home** (or
**Fit world**) fits the whole world; **F** (or **Fit frame**) fits the output frame.

**Rebuilding:** after an edit the preview rebuilds a quarter of a second after you stop
typing. It rebuilds only what the edit needs, so most edits are quick:

| Edit | What's rebuilt | Typical time |
|---|---|---|
| render, output or camera options | only the view | ~35 ms |
| ground, or a scatter | the ground, then the scatters from the first one that changed | 0.2–1 s |
| anything else (colonies, food, obstacles, hand-placed props...) | everything | 0.3–1.7 s |

The status line shows what was done, e.g. `Built in 384 ms: 2 colonies, 2 food, 300 ants,
18 props`.

### Selecting and editing on the canvas

With the **Select** tool (the default):

- **Click** an item to select it. Where items overlap, the smallest one under the cursor wins.
- **Drag** an item to move it.
- **Drag a handle** of the selected item to change its shape. Handles are the centre,
  radius, rect corners and the points of polylines and polygons. They exist for nests, food,
  obstacles, ground regions (including the soft-edge width), props, scatter areas and their
  `clear` shapes, debris, event areas and camera keys.
- **Alt+click** on a polyline or polygon edge inserts a point there.
- **Delete** (or Backspace) removes the last clicked point, as long as the shape keeps
  enough points; otherwise it removes the whole item.
- **Ctrl+D** duplicates the selected item, slightly offset.
- **Esc** cancels the drag in progress.

The preview must have keyboard focus for Delete, Ctrl+D, Enter and Esc (click it first).
A drag is written to the document, as one undoable edit, when you release the mouse. While
you drag, only the gizmo overlay moves; the preview rebuilds after you let go.

**Snap** (tool bar) snaps positions to a 10-unit grid.

---

## 7. Place tools

The tool bar above the preview has a button per tool. Pick one, then click or drag on the
preview. Each placement is one undoable edit, and the new item is selected. **Esc** drops a
shape you're drawing, or switches back to **Select**.

| Tool | Adds to | How to place |
|---|---|---|
| Colony | colonies | click: the nest position |
| Food | food | click, or drag to set the pile's radius |
| Wall rect | obstacles | drag a rectangle |
| Wall circle | obstacles | drag from the centre out to the radius |
| Wall line | obstacles | click each point, finish with Enter or a double click |
| Water | obstacles (`kind: water`) | click each polygon point, finish with Enter or a double click |
| Bridge | obstacles (`kind: bridge`) | click each point of the polyline, then finish |
| Region circle / rect / polygon | ground regions | as for circles, rects and polygons |
| Rock | scenery | drag from the centre out to the radius |
| Plant, Grass | scenery | click |
| Log | scenery | click each point (the first is the sawn end), then finish |
| Scatter | scenery (`scatter`) | drag the area it fills |
| Twig, Pebble | debris | click |
| Rain | events (`rain`) | drag from the centre out to the area's radius |
| Camera key | camera | click: a keyframe looking at that point |

New items get sensible defaults (a food pile of 200 crumbs, a `meadow` scatter, a 5 s rain
event and so on). Adjust them in the inspector.

The **Materials** toggle at the end of the tool bar is a view option, not a tool; see
[Ground and scenery](#8-ground-and-scenery).

---

## 8. Ground and scenery

**Ground.** The **Ground** row sets the `base` material, and its regions paint other
materials over it in order (later regions paint over earlier ones; reorder by dragging rows).
A region is a circle, rect, polygon or the whole world, with a `soft` edge (a handle on the
canvas), `ragged` edge noise, `strength`, and optional `noise` to paint only patches.
Materials: soil, sand, gravel, moss, litter, dry. Material drop-downs show each material's
colour.

**Materials** (tool bar toggle) draws the ground as flat colours per material, so you can see
exactly where regions are.

**Props.** Rocks, logs, plants and grass. Blocking parts (a rock, a log, a plant's stem) are
walls to the ants; canopies and grass blades aren't. A selected prop shows its **blocking
cells**, the surface cells it turns into walls.

**Scatters** fill an area with a preset's props (`meadow`, `forest_floor`, `rocky`, `sandy`)
from their own seed. They keep clear of nests, food and portals, plus any `clear` shapes you
add. When you select a scatter:

- the props it placed are tinted;
- the zones it keeps clear are shown: **hard** zones in red, the **reserve** ring round each
  nest (kept free for middens and later entrances) in orange;
- its blocking props' cells are shown, and any blocking prop it **dropped** (because it cut
  a colony off from its food or the world edge) is marked in red. The status line counts the
  dropped props;
- **Reseed** (in the inspector) gives it a new `seed`, for a different arrangement.

`"blocking": false` on a scatter keeps only its plants and grass, cut to their canopy. That
dresses a scene without changing the simulation at all.

**Debris** (twigs, pebbles) slows ants crossing it until something moves it.

---

## 9. The timeline

The timeline shows everything timed in the scenario against **video time**, the time in the
finished video, from 0 to `duration`.

**Rows:**

- **Camera**: the camera keyframes, or **Surface** and **Nest** rows for split cameras.
- **Speed**: the `ticks_per_frame` schedule drawn as a curve. Time jumps are marked `+Ns`.
- **Layout**: `render.layout.modes` switches.
- **Captions**, **Fades**, **Grade**, **Story marker**: the timed render lists. Captions and
  story-marker windows are drawn as spans.
- **Events (sim time)**: scenario events are timed in *simulated* seconds. The timeline
  converts them to video time through the speed schedule (warmup, ramps and jumps), so they
  line up with everything else.

The header shows the playhead's video time, the duration and the matching sim time, e.g.
`12.40 / 80 s (sim 1935 s)`.

**Editing:**

- **Click** an item to select it; the outline and inspector follow.
- **Drag** an item to change its `t`. An event dropped at a video time gets the sim time of
  that moment.
- **Drag a span's right edge** to change its `until`.
- **Double click** an empty spot on a row to add an item there. On a camera row this adds a
  keyframe framing the preview's current view.
- **Delete** removes the selected item.
- Times snap to 0.1 s; hold **Shift** to snap to single video frames (1/60 s).

**Key here** adds a camera keyframe at the playhead that frames what the static preview is
showing. So: move the preview to the shot you want, move the playhead, press **Key here**.

**The ruler:** click or drag on it to move the playhead. The mouse wheel zooms the ruler,
middle drag pans it, and **Fit** fits the whole duration.

---

## 10. Play preview

**Play** runs the document in the output frame, scaled to fit, starting at the playhead. It
plays exactly as the player and the recorder play it: same camera script, speed schedule,
layout, captions, fades and 60 fps video frames. The speed menu next to it (0.25× to 8×)
sets the playback rate.

- Moving the playhead while playing **seeks**. Forward seeks run on from where it is; seeking
  backwards rebuilds from the start. A progress bar shows long fast-forwards.
- **Stop**, or any edit, returns to the static preview.

Use it to check camera moves, caption timing and pacing without leaving the editor. For
interaction (drawing walls, the tuning panel) use [Run](#12-running-a-scenario).

---

## 11. The output frame

The **Output** row in the outline (always there, near the bottom) sets the video frame.
Select it and use the inspector:

- `size`: `[width, height]` in pixels. Both must be even and between 64 and 8192. The preset
  menu offers portrait 1080×1920 (the default), landscape 1920×1080, square 1080×1080, 4:5
  1080×1350, and 4K portrait and landscape. Pick **custom** or type into the width and height
  boxes for any other size.
- `safe_zones`: `tiktok` (default), `youtube_shorts` or `none`: which platform's UI areas the
  preview shades, captions keep clear of, and the player's **S** overlay shows.

The frame is only about rendering: a scenario runs the same (same state hash) at any frame
size. The world's size doesn't change with it (see [World size](#world-size) below). Camera `zoom` is world units per frame pixel, so a
wider frame shows more of the world at the same zoom, and `fit` keyframes fit whatever frame
they're in. Captions and text scale with the frame's short side.

A scenario without an `output` section uses the defaults (1080×1920, `tiktok`); its fields
show greyed out. The first change adds the section to the file. Undo removes it again, and
each field's **x** button resets it to its default.

Runs and recordings can override the size for one run (see below) without changing the
scenario.

### World size

The **World** row (always there, just above Output) sets the size of the surface world the
ants live in: `size` is `[width, height]` in world units, 1080×1920 by default. Both must be
multiples of 8 and between 256 and 4096. The preset menu offers the default, landscape
1920×1080, square 1920×1920 and large 2160×3840.

The white world bounds in the preview follow the new size at once, and the scenario is
rebuilt (press **Home** to fit the new world). A landscape frame over the default portrait
world shows the world's edges; set the world to 1920×1080 too and the ground, scenery and
ants fill the frame at zoom 1. A bigger world with a moving camera is another way to use it.

Unlike the output frame, the world size changes the run: the pheromone grid, the ground and
whole-world rain cover the new area, and the ants roam all of it. It also costs speed: a
world much larger than the default (over 4× its area) gets a warning in the Problems list.
Items left outside after shrinking the world are reported as errors. The nest's underground
has its own size (`nest_params.underground.size` on the colony).

A scenario without `world` uses the default; as with Output, the first change adds the
section and undo removes it.

---

## 12. Running a scenario

**Run** (F5, the Run menu or the top bar) starts the interactive player (`main.tscn`) as a
separate program, on the document **as it is on screen**, saved or not. The editor writes a
copy to `user://editor_runs/run/<name>.json` and runs that; your file isn't touched. You can
keep editing while it runs, and press Run again to restart it with your changes.

**Stop run** (Shift+F5) closes it. The status line shows `Running (pid N)` while it's open.

In the player: **Space** pause, **P** pheromones, **D** debug overlay, **S** safe zones,
**L** layout, **T** tuning panel, **F** follow the ant under the cursor, **C** back to the
scenario camera, **1–5** speed, **Esc** quit. Left-drag draws walls (Shift+drag erases),
right-click places food, the wheel zooms, middle drag pans. (See README "Running".)

**Run options...** sets how it runs. The settings are remembered for each scenario:

| Option | Meaning |
|---|---|
| Seed | The scenario's, a fixed seed, or a random one each run. |
| Start at | A video time to fast-forward to, or **From playhead** (the timeline's playhead). |
| Layout | The scenario's, or surface / split / nest. |
| Frame size | The scenario's `output.size`, a preset, or a custom `WxH`. |
| Captions | Show the scenario's captions. |
| Safe zones | Start with the safe-zone overlay on. |
| Pheromones | Start with the pheromone overlay on. |
| Debug | Start with the debug overlay on. |
| Tuning panel | Start with the tuning panel open. |

**Run** in the dialog saves the options and starts the run.

---

## 13. Recording videos

**Record...** (Ctrl+R) records the document to an MP4. It uses the same pipeline as
`tools/record.sh`, so the result is identical to recording from the command line. Like Run,
it records the document as it is on screen, saved or not.

**Settings page:**

| Setting | Meaning |
|---|---|
| Format | **PNG** (lossless frames; best quality, slow: use for finals) or **AVI / MJPEG** (about 7× faster; use for drafts), with the MJPEG quality. |
| Frame size | The scenario's, a preset or custom `WxH`. **Also set as the scenario's output size** makes it the scenario's `output.size` (an undoable edit). |
| Seed | -1 means the scenario's seed. |
| Start / end | The video times to record. **To the end** records up to `duration`. |
| Captions | Off records a text-free cut. |
| Output folder, file name | The default folder is `renders/`. The default name is `<scenario>_seed<N>[_WxH][_nocaptions][_from<s>]_<date_time>.mp4`. An absolute file name is used as it is. |
| Keep the captured frames | Keeps the raw capture folder next to the MP4. |

The summary line shows the frame size, frame count, length and output path, or what's wrong
with the settings. The settings are remembered for each scenario.

**While recording**, the dialog shows a progress bar, first for frames captured, then for
encoding, and the log. **Cancel** stops it and deletes the partial output. You can close the
dialog and keep editing: the status line shows the progress, and **Record...** reopens the
progress view. Only one recording runs at a time.

**When it's done:** **Open folder**, **Play** (opens the video) and **New recording**.

Videos are 60 fps, H.264 (yuv420p, CRF 18), with no audio. A recording captures at the full
frame size even if your screen is smaller; a warning about the window size in the log is
harmless.

**Tip:** record short AVI drafts (a few seconds, or a start/end range) to check a shot, and
PNG only for the final video. A long PNG recording can take hours.

---

## 14. Validation and the Problems list

The editor checks the document after every preview build. The **Problems** list under the
inspector shows the result: `Problems: none` or `Problems: 2 errors, 1 warning`, then one
line per issue (errors first) such as:

```
error    food/1/radius: 0 is out of range (at least 1)
warning  camera/1/t: Camera key at 25 s is after the end of the video (20 s)
```

**Click a problem** to select its item. Problems are also shown:

- in the **outline**: the item's row and its section are red (error) or orange (warning),
  and the row's tooltip lists the messages;
- in the **preview**: the item gets a red or orange outline.

**What's checked:**

Errors (the scenario is likely to fail or misbehave):

- a value of the wrong type (text where a number goes, a 3-number position...);
- a number out of its allowed range, or a fraction where a whole number goes;
- a required key missing (e.g. a colony without `nest`, food without `pos`);
- an unknown choice: a species, food type, nest type, state, material and so on that isn't
  registered;
- an unknown `type` or `shape` of a typed object, or a caste the colony's species doesn't have;
- an `output.size` that isn't even or is outside 64–8192;
- a `world.size` that isn't a multiple of 8 or is outside 256–4096;
- a nest, food source or nest entrance outside the world, or inside a wall or water.

Warnings (probably not what you meant):

- a key the format doesn't know (it's kept and saved as it is);
- an event whose sim time comes after the end of the video, so it never happens on screen;
- a camera key, caption, fade, grade point, layout switch or story-marker window that starts
  after `duration`;
- two colonies whose nests are too close (under 60 world units, or the sum of their nest
  radii);
- a caption that falls in the unsafe margins of the chosen safe-zone preset;
- a world over 4× the default area, which will run slower.

**Errors never block you.** Save, Save As, Run and Record with errors show a dialog listing
them, with **Save anyway**, **Run anyway** or **Record anyway**. Warnings don't ask.

**From the command line**, the same checks run over scenario files (with the simulation
built, for the wall checks):

```bash
godot --headless --path . -s res://tests/validate_scenarios.gd                 # every scenarios/*.json
godot --headless --path . -s res://tests/validate_scenarios.gd -- my_scenario  # by name or path
```

It prints `name: ok` or the issues, and exits with 1 if any scenario has errors. All shipped
scenarios validate cleanly.

---

## 15. Keyboard and mouse reference

**Anywhere in the editor:**

| Key | Action |
|---|---|
| Ctrl+N | New scenario |
| Ctrl+O | Open |
| Ctrl+S | Save |
| Ctrl+Shift+S | Save As |
| Ctrl+Q | Quit |
| Ctrl+Z / Ctrl+Y | Undo / Redo |
| Home | Fit the world in the preview |
| F | Fit the output frame in the preview |
| F5 | Run |
| Shift+F5 | Stop the run |
| Ctrl+R | Record... |

**Preview (click it first to give it focus):**

| Input | Action |
|---|---|
| Left click | Select (Select tool) or place (place tools) |
| Left drag | Move the item or a handle; span a circle or rect with a place tool |
| Alt+click | Insert a point on a polyline or polygon |
| Double click / Enter | Finish a polyline or polygon |
| Delete / Backspace | Delete the last clicked point, or the item |
| Ctrl+D | Duplicate the selected item |
| Esc | Cancel the drag or shape; again for the Select tool |
| Wheel | Zoom |
| Middle or right drag | Pan |

**Timeline:**

| Input | Action |
|---|---|
| Click an item | Select it |
| Drag an item | Change its time |
| Drag a span's right edge | Change `until` |
| Double click an empty spot | Add an item there |
| Delete | Delete the selected item |
| Shift while dragging | Snap to video frames instead of 0.1 s |
| Click / drag on the ruler | Move the playhead |
| Wheel | Zoom the ruler |
| Middle drag | Pan the ruler |

**Outline:** click to select; drag a list item's row to reorder it.

---

## 16. Walkthrough: a scenario from scratch

This builds a landscape scenario with two colonies, food, scenery, rain, a camera move and a
caption.

1. **Start fresh:** `tools/editor.sh --new`. You get one colony at (540, 1500).
2. **World and output frame:** select **World** and choose **landscape 1920×1080** from the
   size presets, then select **Output** and choose **landscape 1920×1080** there too, so the
   world fills the frame. Press **Home** to see the whole new world and **F** for the frame.
   The colony is now outside the world (the Problems list says so): drag it to about
   (700, 600).
3. **A second colony:** pick **Colony** on the tool bar and click at about (1200, 500). In the
   inspector, set its `species` to another species.
4. **Food:** pick **Food**, then drag out a pile near the right edge of the world. Drag out a
   second one elsewhere. Adjust `amount` and `radius` in the inspector.
5. **Scenery:** pick **Scatter** and drag a rectangle over part of the world. Select the
   scatter and try **Reseed** until you like the arrangement. Change `preset` to
   `forest_floor` for a different look.
6. **Ground (optional):** select **Ground**, set `base` to `soil`, then add a sand patch
   with **Region circle** and widen its soft edge with the handle.
7. **Rain:** pick **Rain** and drag a circle. On the timeline, drag the rain event to about
   3 s, or set its `t` in the inspector (events are in sim seconds).
8. **Camera:** zoom and pan the preview to the opening shot. Put the playhead at 0 and press
   **Key here**. Move the playhead to 10 s, frame a closer shot and press **Key here** again.
9. **Caption:** select **Render** and use **Add... → Add caption**. Set its `text`, `style`
   (`title`) and `until` in the inspector, or drag its span's edge on the timeline.
10. **Check:** the Problems list should say `none`. Press **Play** on the timeline to watch
    the camera move and the caption.
11. **Save:** Ctrl+S, e.g. as `scenarios/my_landscape.json`.
12. **Run:** F5, and try drawing walls and placing food in the player.
13. **Draft:** Ctrl+R, format **AVI**, end at 5 s, **Record**. When it's done, press **Play**.

The saved file also works outside the editor:

```bash
godot --path . -- --scenario=my_landscape
FORMAT=avi tools/record.sh my_landscape 1 5
```

---

## 17. Walkthrough: the underground nest view

A colony whose nest digs its own underground gets a second world: a layer of soil below the
surface, seen from above, where the queen, the brood, the diggers and the chambers are. It
is a real, fully simulated layer, linked to the surface by the nest's entrance shafts. This
walkthrough makes one and puts it on screen.

**Two things decide whether you see it:**

1. **The colony has an underground.** Its `nest_params` need an `underground` section.
   Without it there is nothing to show.
2. **The layout shows it.** `render.layout` splits the frame into a surface part and a nest
   part (`split`), or shows the nest full screen (`nest`). Without `render.layout` the
   scenario plays the surface full screen, even if the colony has an underground.

**Where you see it:** the static preview in the middle of the editor always shows the
**surface only**. The underground appears in **Play** (the timeline), **Run** (F5) and
**Record**, which play the scenario with its layout. So you set it up in the outline and
inspector, and check it with Play.

### Step 1: a colony whose nest digs

Two nest types have a queen, brood and chambers they plan and dig themselves as the colony
grows:

| Species | Nest type | Castes for `population` |
|---|---|---|
| `leafcutter` | `fungus_nest` (the species' own nest; nothing to set) | `queen`, `minim`, `media`, `major` |
| `harvester` | `granary_nest` (set `nest_type` to it) | `queen`, `minor`, `major` |

Other nest types (the harvester's own `seed_nest`, `basic_nest`) accept an `underground`
too, but they only get a shaft and dig just what you list in its `carve` and `plan`. Use one
of the two above for a living nest.

1. `tools/editor.sh --new`, or open your own scenario.
2. Select **Colony 0** in the outline (or add one with the **Colony** tool). In the
   inspector set `species` to `leafcutter`. (For harvesters: `species` `harvester` and
   `nest_type` `granary_nest`.)
3. Open `population` and add the castes: `queen` 1, `minim` 30, `media` 40. The queen lives
   in the royal chamber and lays the eggs; workers dig, nurse and forage. A nest without
   workers never digs.
4. Open `nest_params`, then `underground`, and set `size` to `[1280, 1280]` (the default
   size, but setting any field creates the section; an empty `underground` does the same).
   That is what gives the nest its own layer.
5. Decide how the nest starts:
   - **An established nest** (you see chambers straight away): in `nest_params` set
     `initial_chambers` to 3. Leave `underground.open` as it is (true: the entrance is open).
   - **A founding nest** (the story of the first dig): set `underground.open` to false and give
     the population only a queen and a few workers (e.g. `queen` 1, `minim` 4). The queen
     starts sealed in; once there are `open_entrance_at` workers they dig up to the surface.
     This takes a while in sim time, so it needs a fast speed schedule (see `colony_founding`
     and `harvester_founding` for tested values).
6. Add a food source near the nest with the **Food** tool so foragers have something to carry
   home and down.

The colony's JSON now looks like this:

```json
{
	"species": "leafcutter",
	"nest": [540, 1000],
	"population": {"queen": 1, "minim": 30, "media": 40},
	"nest_params": {
		"initial_chambers": 3,
		"underground": {"size": [1280, 1280]}
	}
}
```

(You can also paste that with **Edit as JSON** on the colony.)

The static preview hasn't changed apart from the nest's entrance: the underground isn't drawn
there.

### Step 2: turn on the split layout

The layout lives under `render.layout`. The quickest way to create it:

1. In the timeline, **double click** the **Layout** row at 0 s. This adds a layout switch
   `{"t": 0, "mode": "split"}` and creates `render.layout` (and `render`, if the file had no
   render section). The **Render** section now appears in the outline, with a **Layout
   modes** row.
2. Select the **Render** row in the outline and open `layout` in the inspector:

| Option | What it does |
|---|---|
| `mode` | `split` (default): surface and nest; `nest`: the nest full screen; `surface` (or `normal`): the surface full screen. The starting mode when there are no `modes`. |
| `colony` | Which colony's nest is shown (its index in **Colonies**; default 0). |
| `surface` | Where the surface part sits: `top` (default) or `bottom`; `left` or `right` put the two parts side by side, for landscape frames. |
| `ratio` | The surface's share of the frame: of its height for top/bottom, of its width for left/right (0.2–0.8, default 0.5). 0.45 gives the nest a little more room. |
| `stats` | The readout in the nest part's top left (ants, eggs, larvae, pupae). Off for a clean frame. |
| `highlight` | A ring round each new worker as it emerges. |
| `modes` | Timed switches (below). |

Instead of the timeline you can also use **Add... → Add caption** (which creates `render`) and
then set `layout.mode` in the inspector; or, on the Render row, **Edit as JSON** and paste:

```json
{"layout": {"mode": "split", "ratio": 0.45}}
```

3. **Check it:** move the playhead to 0 and press **Play**. The frame now shows the surface in
   its top part and, below it, the nest: dug chambers and tunnels in the soil, the queen, the
   brood piles and the workers, with the readout top left.

If Play still shows only the surface, see [Troubleshooting](#when-the-nest-doesnt-show) below.

### Step 3: switch the layout over time

`render.layout.modes` changes the mode at video times. Each switch holds until the next one,
so a video can open in the nest, cut to the split view, and end on the surface:

1. On the timeline's **Layout** row, double click at each time you want a change. Each new
   switch is `split`; select it and set its `mode` in the inspector (`nest`, `split`,
   `surface`).
2. Drag the switches along the row to retime them (Shift snaps to single frames).
3. Press **Play** from before each switch to see the cut.

For example, the nest full screen for the first 4 s, then the split:

```json
"modes": [{"t": 0, "mode": "nest"}, {"t": 4, "mode": "split"}]
```

When there are `modes`, the first switch sets the starting mode, and `layout.mode` only
matters if the first switch comes later than 0 s. Hide a hard cut under a fade
(`render.fades`) if you want it softer.

### Step 4: point the nest camera

With nothing set, the nest part's camera frames **everything dug so far** and eases out as the
nest grows (a `fit: excavation` keyframe with an 80-unit margin). That is often all you need.
For your own shots, give the nest part its own camera track:

1. If the scenario has no camera yet, select the **Scenario** row and use **Add... → Add
   camera key**, so the **Camera** section exists.
2. Select the **Camera** row. The inspector shows a form selector next to it: switch it from
   the keyframe list to **Separate surface and nest camera tracks**. Switching the form
   replaces the camera section, so do this before placing keys (or copy the old keys out
   with **Edit as JSON** first and paste them under `surface`).
3. The outline now has **Surface camera** and **Nest camera** rows, and the timeline has
   **Camera: surface** and **Camera: nest** rows. The surface track works as before: frame
   the preview and press **Key here** (it always adds to the surface track).
4. Add nest keys with **Add... → Add nest camera key** (Camera row selected) or by double
   clicking the **Camera: nest** row of the timeline. Then set each key in the inspector.

**Nest camera positions are in the underground layer's own coordinates**, not the surface's.
The layer runs from (0, 0) to its `size`, and the shaft and the royal chamber are at its
centre by default (`underground.shaft`, `underground.royal`), so for a 1280×1280 layer the
nest is around (640, 640). New nest keys come from the surface preview's view, so always
correct their `pos` in the inspector. (The static preview draws nest keys over the surface
at those numbers; their place there means nothing.)

Useful nest keyframes:

| Keyframe | Shot |
|---|---|
| `{"t": 0, "pos": [640, 640], "zoom": 3}` | A close-up of the royal chamber. Larger `zoom` is closer. |
| `{"t": 8, "fit": "excavation", "margin": 80}` | Eases out to frame everything dug, and keeps doing so as the nest grows. `min_zoom` / `max_zoom` limit it (e.g. `max_zoom` 2.6 so a small nest isn't shown too close). |
| `{"t": 12, "follow": {"brood": "first"}, "zoom": 4}` | Follows the oldest brood item through its stages, carried or not, and then the worker it becomes. |
| `{"t": 12, "follow": {"state": "dig", "near": [640, 640]}, "zoom": 4}` | Follows the digger nearest that point. |

Keyframes ease into each other over the whole gap between them, as on the surface.

**Following an ant between surface and nest:** give a follow keyframe `"across": true` and
the ant is kept when it goes through an entrance: the camera of the part showing its new layer
takes it over. Add `"switch_mode": true` too and the layout switches (`surface` ↔ `nest`)
when the ant's layer isn't on screen. With split tracks, `"follow": {"ant": "same"}` on the
nest camera picks up whatever the surface camera was following. See README "Scenarios" for
the details of follows.

### Step 5: the rest of the nest settings

These are all under the colony's `nest_params` (hover over a field for its help):

- `underground.size`: the layer's size in world units (default 1280×1280), separate from
  the surface world's size. `cell_size` (default 4) is the soil grid; smaller is finer and
  slower.
- `underground.texture`: clay, roots and stones in the soil (harder to dig; stones are dug
  round, leaving pillars). `underground.hardness` scales all digging work.
- `royal_radius`, `chamber_min_radius`, `chamber_max_radius`, `tunnel_radius`: the size of
  the chambers and tunnels the nest plans. `max_chambers` caps how many.
- `entrances`: `{"at": [900, 2200], "spacing": 150}` digs another entrance at each colony
  size in `at`.
- `nurseries`: separate egg, larva and pupa chambers once the colony is big enough
  (`"carve": true` digs them at the start).
- `brood`: timing and needs of eggs, larvae and pupae; `initial` gives the nest brood at
  the start (e.g. `{"egg": 3, "larva": 3, "pupa": 2}`), so the nurses have work straight away.
- `underground.highways`: busy tunnels widen (on by default; `false` turns it off).
- Top level: `max_agents` `{"surface": 900, "nest": 700}` caps how many ants each layer
  simulates one by one, to keep big colonies fast.

README "Leafcutter nests that dig their own underground" and "Harvester nests that dig
their own granaries" describe what each does.

### Step 6: run and record it

- **Play** on the timeline plays the layout, the modes and both cameras exactly as they will
  be recorded.
- **Run** (F5) opens the player with the scenario's layout. Press **L** there to cycle
  surface → split → nest. In the split layout the mouse (walls, food, zoom, **F**) works on
  the surface part. **Run options... → Layout** starts the run in another layout without
  changing the scenario.
- **Record...** records the layout as it is in the scenario.

From the command line, once it's saved as `scenarios/my_nest.json`:

```bash
godot --path . -- --scenario=my_nest --layout=split             # or --layout=nest
tools/screenshot.sh my_nest 0 renders/nest.png -1 --at=6        # a still at 6 s
FORMAT=avi tools/record.sh my_nest 1 10                         # a 10 s draft
```

### The whole example

A small scenario with an established leafcutter nest, 4 s of the nest full screen, then the
split view; the nest camera starts on the royal chamber and eases out to the whole nest:

```json
{
	"name": "my_nest",
	"seed": 1,
	"duration": 20,
	"colonies": [
		{
			"species": "leafcutter",
			"nest": [540, 1000],
			"population": {"queen": 1, "minim": 30, "media": 40},
			"nest_params": {
				"initial_chambers": 3,
				"underground": {"size": [1280, 1280]}
			}
		}
	],
	"food": [
		{"type": "food_pile", "pos": [540, 600], "radius": 24, "amount": 200}
	],
	"camera": {
		"surface": [
			{"t": 0, "pos": [540, 900], "zoom": 1.5}
		],
		"nest": [
			{"t": 0, "pos": [640, 640], "zoom": 3},
			{"t": 8, "fit": "excavation", "margin": 80}
		]
	},
	"render": {
		"layout": {
			"mode": "split",
			"ratio": 0.45,
			"modes": [{"t": 0, "mode": "nest"}, {"t": 4, "mode": "split"}]
		}
	}
}
```

The shipped `harvester_founding`, `colony_founding` and `leafcutter_life` scenarios are
longer examples: open one and look at its colony's `nest_params`, the **Camera: nest** row
and the **Layout** row.

### When the nest doesn't show

- **Play shows only the surface.** Check, in order: the file has `render.layout` (the
  Render row in the outline); its `mode`, or the first of its `modes`, isn't `surface`;
  `layout.colony` is the index of the colony that digs; and that colony has
  `nest_params.underground`. A nest without an underground layer plays full screen without
  an error.
- **The static preview doesn't show the nest.** That's expected: it shows the surface
  only. Use Play.
- **The nest part is empty soil, or looks at the wrong place.** A nest camera `pos` in
  surface coordinates (e.g. the colony's `nest` position) points somewhere else in the
  layer. Use positions within the layer's `size` (the centre by default), or a `fit:
  excavation` key.
- **Nothing gets dug.** A founding nest (`open: false`) only starts digging once it has
  `open_entrance_at` workers, and digging takes sim time: check the speed schedule, or use
  an established nest (`initial_chambers`) while you set up the shots.
- **L does nothing in the player.** The layout only cycles for a colony whose nest has an
  underground.

---

## 18. Command line options

```
godot --path . res://scenes/editor.tscn -- [options]      (or tools/editor.sh [options])
```

| Option | Meaning |
|---|---|
| `--scenario=<name or path>` | Open a scenario by name (`scenarios/<name>.json`) or any `.json` path. |
| `--new` | Start with a new document instead of reopening the last file. |
| `--screenshot=<file.png>` | Save a screenshot of the window once the preview is built, then quit. Needs a real window (not `--headless`). |
| `--select=<path>` | Select an item first, e.g. `colonies/0`, `scenery/1`, `render/captions/0`. |
| `--materials` | Turn the Materials overlay on. |
| `--play=<video s>` | Open the play view paused at that video time. |
| `--dialog=run` / `--dialog=record` | Open the Run options or Record dialog. |
| `--dialog=record_now` | Start a 3 s AVI draft recording (for a screenshot of the progress view; it's cancelled after the screenshot). |

Example: a screenshot of a scenario with its first colony selected:

```bash
tools/editor.sh --scenario=meadow_forage --select=colonies/0 --screenshot=renders/editor.png
```

---

## 19. Settings and files the editor keeps

All in Godot's user folder (`user://`, on Windows
`%APPDATA%\Godot\app_userdata\<project name>\`):

| File | Contents |
|---|---|
| `editor_settings.cfg` | Recent files (`[recent]`), panel sizes (`[layout]`), and the last Run and Record settings per scenario (`[run]`, `[record]`). Delete it to reset the editor. |
| `editor_runs/run/<name>.json` | The copy of the document the last Run used. |
| `editor_runs/record/<name>.json` | The copy the last recording used. |

Run and record settings belong to your runs, not the scenario, so they aren't saved in the
scenario file. The frame size is the exception: it belongs to the scenario (`output.size`),
which is why the Record dialog offers to set it there.

While a recording is starting, the project folder briefly has an `override.cfg` (it sets the
recorder's window size). It is removed as soon as the recorder has started, and always at the
end. If a crash leaves one behind, delete it: while it exists, new recordings refuse to
start.

---

## 20. Tips and troubleshooting

- **The preview didn't change after an edit.** It rebuilds 0.25 s after the last edit, and
  after you release the mouse when dragging. Big scenarios take up to about 2 s; the status
  line shows when the build is done.
- **An item is hard to click.** Clicks pick the smallest item under the cursor. Select large
  items (ground regions, scatter areas) from the outline, or zoom in.
- **Delete does nothing.** Click the preview first to give it keyboard focus. Delete on the
  timeline deletes the timeline's selection.
- **An event never happens.** Events are in *sim* seconds. With a fast speed schedule or
  time jumps, a small `t` can already be well into the video, and a large one may come after
  the end (the Problems list warns about that). Drag the event on the timeline to place it
  by video time.
- **A follow camera goes to the corner.** A follow keyframe picks its ant at the *previous*
  keyframe's time, so the ant (or brood item) must exist by then. Give it a `near` point.
- **Scatter props disappear.** A scatter drops blocking props that would cut a colony off
  from its food or the world edge. They're marked red when the scatter is selected. Move the
  area, add `clear` shapes, lower `density`, or use `"blocking": false`.
- **Captions sit in the wrong place in landscape.** Caption positions (`top`, `middle`,
  `bottom`) are inside the safe area of the chosen `safe_zones` preset. For landscape videos
  that aren't for a phone platform, set `safe_zones` to `none`.
- **Record says a recording is already running.** Only one runs at a time. If none is
  running, check for a leftover `override.cfg` in the project folder (see above).
- **Recording fails at the encoding step.** Check that `ffmpeg` is on your PATH.
- **An unknown species.** A colony with a species that isn't registered is an error in the
  Problems list, and the preview build logs a script error for that colony. Pick a
  registered species.
- **Undo went too far.** Use Redo (Ctrl+Y). Undo history resets when you open or create a
  document.
