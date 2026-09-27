# M17: The life of a leafcutter colony (cinematic scenario)

Goal: one slow, cinematic vertical video, `scenarios/leafcutter_life.json`, that tells the
whole life of a leafcutter colony in order, holding on each moment long enough to read it:

1. **Nuptial flight and founding**: a winged queen drifts down, lands, sheds her wings, digs
   down and seals herself in; she spits out the fungus pellet she carried from her mother's
   nest and manures her first garden.
2. **The lifecycle**: she lays; an egg becomes a larva fed on gongylidia, a pupa, a pale
   callow, then a minim that joins the work. Later, old workers die and are carried out.
3. **Breaking ground**: the first minims dig up to the surface and the entrance opens.
4. **Leaf to fungus to food**: a media cuts a fragment from a leaf (with a minim riding it,
   guarding against phorid flies), carries it home and down the tunnel, gardeners chew it to
   pulp and plant it, fungus grows over it, and nurses harvest gongylidia to feed larvae.
5. **The trunk trail**: the colony has grown; debris falls across the busy trail and majors
   carry it off.
6. **Waste**: spent garden and the dead go out to the midden, which grows.
7. **Maturity and the next generation**: the whole sprawling nest; winged gynes and males
   pour out of the mound at dusk and fly, and the cycle starts again.

Slow-paced means: near real time (tpf 0.5) or slow motion (tpf 0.25) on close-ups, long
holds, gentle camera moves, time-lapse only in transitions (preferably under a fade), about
150–180 s of video (so a PNG final render takes ~2 h; draft with AVI).

Status: M17a done (presentation layer). Next: M17b.
M16 (scenario editor, `docs/plan_M16.md`) is planned but not started and independent of
M17; both touch `ScenarioPlayer.setup`, and M16's schema will need the new `render` keys.

## Where things stand (before M17)

Already in the sim and usable as-is (see README "Species: leafcutter ants" and "Leafcutter
nests that dig their own underground"):
- Sealed founding (`underground.open = false`): queen + minims + fungus pellet
  (`initial_fungus`), queen manures from `queen_reserve`, digs up at `open_entrance_at`.
- Brood with care: egg → larva → pupa → callow → worker, carried by nurses, fed gongylidia,
  groomed; `first_caste`/`first_workers`; majors appear (spawn_ratio 0.1) once past them.
- Leaf line: `cut_leaf` → `carry_home` → `carry_down` → `garden` (pulp, planting, weeding,
  mould) → `carry_spent` to a midden. Gardens are cell grids (`garden_grid.gd`).
- Hitchhiking minims (`seek_ride`/`hitchhike`), patrolling majors (`patrol_trail`,
  `clear_debris`), `drop_debris` events on a trail channel.
- Refuse and corpses: `params.worker_lifespan`, `carry_corpse`, middens (`nest_params.midden`).
- Camera keyframes per layout part (`camera.surface` / `camera.nest`), `follow` an ant on
  one layer, `fit: excavation`; layout modes switched by time (`render.layout.modes`);
  `ticks_per_frame` ramps.

Missing (this milestone): captions/fades/light (presentation), a camera that follows one
ant (or one brood item) across layers and through its life, the queen's landing and wing
shedding, alates and the nuptial flight, phorid flies, and the scenario itself.

## Design decisions (apply to every phase)

1. **Render-only where possible.** Presentation and camera work live in `render/` and
   `scenes/` and never touch `sim.rng` or the sim; they can't change hashes.
2. **Sim additions are opt-in** (nest params, colony params, scenario events) and generic
   where they are about ants in general (landing, wings, alates, nuptial flight belong to
   the core `ColonyNest`; phorid flies are the leafcutter's own). Existing scenarios keep
   their state hashes (`tests/test_layers.gd`, `tests/test_native.gd`). New castes are
   appended after existing ones with `spawn_ratio = 0`; check `pick_caste` doesn't draw
   the RNG differently.
3. **Native parity**: new behaviours are GDScript states outside the kernel hot path. If a
   phase touches `explore`/`follow_trail`/`carry_home`/`linger`/`Steering`/`lay`/`Travel`,
   mirror it in `native/src/ant_kernel.cpp`.
4. **Story timing is measured, not guessed.** `tests/story_probe.gd` (M17c) prints the sim
   times of the story beats for a seed; camera keyframes and captions are placed from its
   output. Pick a seed where every beat happens on time and in view.
5. **Captions are data** (`render.captions`); the scenario can be recorded without them
   (`--captions=0`) for a text-free cut.
6. **Safe zones**: captions and key action stay out of the TikTok/Reels UI zones
   (`Overlays.SafeZones`: top 150, bottom 400, right 120 px).

## Phases

### M17a: presentation layer (captions, fades, light) — DONE

Goal: `render/presentation.gd` (`Presentation`, a CanvasLayer over the whole frame, also over
the split layout) driven by video time from `ScenarioPlayer.advance`:
- `render.captions`: `[{"t": 2, "until": 8, "text": "...", "style": "title"|"chapter"|"caption",
  "pos": "top"|"middle"|"bottom", "fade": 0.8}]`; drawn with outline/shadow, faded in and out,
  word-wrapped inside the safe area.
- `render.fades`: `[{"t": 60, "to": 1.0, "color": [0,0,0]}, ...]`: an overlay whose alpha is
  ramped between points (fade to black, dip between chapters).
- `render.grade`: `[{"t": 0, "tint": [r,g,b], "brightness": 1, "saturation": 1,
  "vignette": 0.3}, ...]`: a colour grade ramped between points (dawn, noon, dusk, night),
  a screen-reading shader on a full-frame ColorRect.
- `--captions=0` (main and record) hides captions.
Files: `render/presentation.gd`, `render/grade.gdshader`, `scenes/scenario_player.gd`,
`scenes/main.gd`, `scenes/record.gd`, `tests/test_presentation.gd`, README (Scenarios).
Verify: unit tests of the ramps/caption alpha; full suite (no hash changes); a windowed
still with a caption and a dusk grade.

**Done.** As planned. Keys are read in `Presentation.setup(render)`; values between points
ramp linearly (`Presentation.ramp`). The grade is one shader over `hint_screen_texture`,
so it grades whatever is under it (both split parts, seam, stats). Captions/fades sit above
the grade. The nest's stats readout (`SplitLayout._stats`) is still shown; a scenario that
wants it gone should get `render.layout.stats: false` in M17c if needed.

### M17b: camera storytelling

Goal: camera keyframes that tell a story across layers.
- `"follow": {"ant": "same"}` keeps following the ant a previous keyframe chose, and a
  `"follow"` with `"across": true` keeps one ant through portals: `ScenarioPlayer` gives the
  followed ant to whichever part (surface/nest) shows its layer, switching layout mode
  automatically if asked (`"switch_mode": true`), so one shot follows a fragment from the leaf,
  down the entrance, to the garden.
- `"follow": {"brood": "first" | "near": [x,y], "stage": "egg"}` follows a brood record by id
  through its stages (Brood positions; carried brood follows the nurse), then the ant it
  becomes when it ecloses (Brood emergence log gives the new ant).
- `"follow": {"state": "garden"|"carry_corpse"|..., "layer": "nest"}` choices on the nest
  camera (already mostly works; check the "near" resolution against the nest layer).
- Optional `"smoothing"` per keyframe (slower, more cinematic follow; default 0.35 s).
- `"jump": seconds` on a `ticks_per_frame` point (or `playback.jumps`): run that many sim
  seconds in one frame (for use under a fade), so long time skips don't need huge tpf ramps.
Files: `render/camera_director.gd`, `scenes/scenario_player.gd`, maybe `sim/nests/brood.gd`
(read-only accessors: id → index, emergence → ant), `tests/test_camera.gd` (new).
Verify: tests with a small scenario (queen founding): brood follow keeps the same id through
stages; across-follow switches parts when an ant takes a portal; hashes unchanged.
Hands on: keyframe syntax for M17c.

### M17c: scenario draft from existing features, story probe

Goal: `scenarios/leafcutter_life.json` telling chapters 2–6 (sealed founding onward) with
existing sim features, captions, fades, grade and the M17b camera; and
`tests/story_probe.gd` printing beat times (first egg/larva/pupa/callow/worker, entrance
open, first leaf fragment underground, first gongylidia fed, first major, first debris
cleared, first corpse to midden, population steps).
- Start from `colony_founding`'s nest params; slower brood stages early so the first brood
  can be watched (tune `brood` durations), `worker_lifespan` so corpses appear by chapter 6,
  `drop_debris` events on `c0.food` timed after majors patrol, leaves placed for a good
  cutting close-up near the first entrance.
- Try several seeds with the probe; pick the one with the best timing.
- Layout: nest full screen for chapters 1–2, split for 3–4 (surface top), surface full
  screen for chapter 5, nest for the waste, split pull-back for the end.
Verify: probe output; `test_scenario`-style load test (scenario loads and runs 60 s); AVI
draft (`FORMAT=avi tools/record.sh leafcutter_life`, in the background).
Hands on: timings, chosen seed, a list of what reads badly in the draft.

### M17d: the queen's landing (prologue)

Goal: chapter 1. Opt-in `nest_params.founding.landing`: the queen starts on the surface as
an alate (winged), flies in from off-screen (render: wing blur, shadow offset by height,
eased descent; sim: she is an ant in a new `alight` state moving along a path, not
colliding), lands at the nest site, sheds her wings (two wing items left on the ground, drawn
by a new item renderer; they later decay or are carried to the midden), walks a short loop,
digs a shaft down (a dig job from the surface; the shaft becomes the founding chamber's
way in) and seals it (the entrance cell refilled; `open: false` founding then proceeds as now
and the minims later reopen the same shaft).
Files: `sim/nests/colony_nest.gd` (+ a founding helper), new behaviour(s) in
`sim/behaviours/` (`alight`, `found_nest`), `render/ant_renderer.gd`/`ant.gdshader` (wings,
altitude), an item renderer for shed wings, leafcutter nest params in the scenario,
tests (`test_founding_landing.gd`): queen ends sealed underground, entrance reopens later,
old scenarios' hashes unchanged, native parity test still passes.
Verify: tests, full suite, windowed stills of the landing, then a nest_probe run of
`colony_founding` with the landing turned on (background) to check the nest still grows.

### M17e: alates and the nuptial flight (finale)

Goal: chapter 7. Opt-in `nest_params.alates`: past a population, the queen's brood
includes winged castes (`gyne`, `male`, appended to `leafcutter.tres` with spawn_ratio 0,
chosen by the nest, not by `pick_caste`'s ratios); alates stay in the nest (`linger` in a
chamber, fed) until a `nuptial_flight` scenario event: they walk up, gather on the mound
with workers milling round them (majors guarding), and take off one by one (sim: state
`take_off`, the ant leaves the world; render: wings, climbing altitude, shrinking shadow,
leaving frame). Males smaller, darker; gynes large.
Files: `sim/nests/colony_nest.gd`, `sim/scenario_events.gd` (`nuptial_flight`),
`sim/behaviours/take_off.gd`, `species/leafcutter/leafcutter.tres`, ant renderer/shader
(shared wing drawing with M17d), tests (`test_alates.gd`), README.
Verify: tests incl. hash checks; stills of the flight; full suite.

### M17f: phorid flies (optional flavour)

Goal: tiny parasitoid flies hover over the trail and dive at fragment carriers; a carrier
with a hitchhiking minim is left alone, one without is chased (sim: species-local fly
agents with their own RNG stream split from `sim.rng` only if enabled, or render-only if
the effect can be faked from sim state: flies drawn around carriers without riders).
Prefer render-only (no hash risk): `species/leafcutter/phorid_renderer.gd` registered as a
renderer, reading carriers and riders from sim state.
Verify: stills; suite. Skip if M17c's draft already reads well without it.

### M17g: final assembly and render

Goal: put the prologue (M17d), finale (M17e) and flies (M17f) into `leafcutter_life.json`,
re-run the story probe, retime captions/camera, check frames against the safe zones
(`tests/frame_probe.gd`), update the README (scenario list, captions/fades/grade, camera
keyframes, landing/alates params), AVI draft then the PNG final (background, ~2 h).
Verify: full suite; draft reviewed; final MP4 in `renders/`.
