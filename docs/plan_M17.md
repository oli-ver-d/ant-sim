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

Status: M17a done (presentation layer), M17b done (camera storytelling), M17c done (draft
scenario, story probe). Next: user reviews the M17c draft, then M17d.
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

### M17b: camera storytelling — DONE

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

**Done.** Keyframe syntax for M17c (all render side; `tests/test_camera.gd` checks hashes
are unchanged):
- Per keyframe `"smoothing": s` (default 0.35; 0 locks on). Applies to follows only.
- `"follow": {"ant": "same"}`: continues the cameras' shared *story* (`CameraDirector.story`,
  one dictionary shared by the surface and nest cameras): the ant (or brood item) the latest
  follow keyframe on either camera chose, or the ant an across follow was handed on as.
  Resolved when the keyframe first comes into use (from the previous keyframe's time), like
  every follow. `"ant": <slot>` follows a slot directly.
- `"follow": {"brood": "first" | "last" | "near" | <id>, "stage": "egg", "near": [x, y],
  "colony": 0}`: oldest / newest record (in that stage), nearest to `near`, or an id. Needs
  brood care (positions); belongs on the **nest** camera (brood is on the nest layer; on
  another camera the target just holds). Tracks the id through stages (carried brood rides
  with the nurse, drawn like the brood renderer), then the ant from `Brood.emerged_as(id)`
  (new read-only accessor; `Brood.NOT_EMERGED` = not in the last 32 emergences). A brood
  item that dies, or joins the abstract population, leaves the camera where it was.
- `"across": true` (+ optional `"switch_mode": true`) in any follow with an ant: while that
  keyframe is the one in effect (from its `t` until the next keyframe on that camera), the
  ant is handed to the other camera whenever it's on that camera's layer
  (`CameraDirector.carry()`; cut to the ant, then smoothed, at the across keyframe's zoom and
  smoothing). With `switch_mode` the layout changes to `"nest"` / `"surface"` when the ant's
  layer isn't shown (split shows both, so no switch). If both cameras have an across
  keyframe in effect, the one with the later `t` wins.
- Time jump: `"jump": s` on a `ticks_per_frame` point, e.g.
  `[{"t": 0, "tpf": 0.5}, {"t": 40, "tpf": 0.5, "jump": 120}]` (a point may also have only
  `"jump"`, no `"tpf"`). Runs in the first frame at or after `t`, on top of that frame's tpf;
  the cameras `snap()` (fit and follow smoothing) after it. Put it under a fade.

Changed from the plan: `"follow": {"state", "layer": "nest"}` needs no `layer` key — each
camera already chooses on its own layer (nest camera → nest layer; tested with `"state":
"dig"`). `"brood": "last"` added. `ScenarioPlayer.setup_data(dict, ...)` added (tests build
scenarios in code). `render.layout.modes` now applies only when a new point is reached (it
used to re-apply every frame), so a `switch_mode` switch holds until the next point.

Caveats for M17c: a followed ant's slot can be reused after it dies (the camera would then
follow the newcomer; rare, avoid following ants near `worker_lifespan`). The nest camera
only updates while the nest is shown; an across keyframe on it keeps working in `"surface"`
mode, but its non-across targets freeze. Across hands off at the moment the ant changes
layer (end of portal transit); the source camera holds at the entrance meanwhile.

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

**Done.** Files: `scenarios/leafcutter_life.json`, `tests/story_probe.gd`,
`tests/test_scenario.gd` (`test_leafcutter_life_loads_and_runs`, 60 sim s, ~5 s),
`render/split_layout.gd` (`render.layout.stats: false` hides the nest readout; render only),
README (scenario list, probe command, `stats`). No sim change; hashes untouched.

Sim setup (differs from `colony_founding`): queen + 4 minims, `open_entrance_at: 8` (so the
first brood is raised sealed in and the dig starts ~65 s), `brood_rate: 0.006` (first egg at
13 s instead of 28 s; later growth is leaf-limited, not brood-limited), `worker_lifespan:
1500` (first death ~1100 s, ~40 by 2100 s), initial brood egg 3 / larva 3 / pupa 3, only non-blocking
scenery. Food: one leaf close to the entrance, (610, 880), for the cutting close-up; a leaf at
(800, 1300) at 700 s; the "trunk" leaf at (540, 520) at 900 s (by 2100 s the only one, so
all traffic is on one trail); `drop_debris` (9, on `c0.food` near (545, 790)) at 2150 s. The
extra leaves of `colony_founding` pulled traffic onto several weak trails, so they're gone.
A queen-only founding (no minims) stalls in the current sim (one worker, brood stuck) — M17d
must keep the minims or fix that.

Seed 3 (six seeds probed with the first setup, three with the final one; seed 3 has the
busiest trunk trail at 2150 s — 17 cutting, 190 on the surface — and its debris clearing is
spread over 18 s so it can be watched; seed 2 opens and cuts sooner but its trail is thin).
Probe (`story_probe.gd -- leafcutter_life 3 2350 150`), sim seconds:
- queen (nest) (680, 725); main entrance surface (540, 1060), nest (720, 608)
- first egg 13.3 (id 9, at (685, 713)); larva 43.3; fed 60.6 and 87.6 at (713, 708); pupa
  103.4; callow 143.4 at (750, 715); ecloses 152.5 as a minim (ant 14)
- first digger 65; entrance open 158; first spent garden out 161; midden m0 (502, 1152) 166
- first cut 231 at (528, 952) on the close leaf; carried down 236; underground 239 at
  (695, 708); gardener with pulp 242; first hitchhiker 281
- first major 450; population 50 at 774, 100 at 1237, 200 at 1708, 300 at 2095
- first worker death 1114, first corpse on a midden 1120; middens m1 (415, 1143), m2 (440, 1060)
- debris 2150: picked up 2150.1 at (493, 810), cleared 2152.8, then 2153.6, 2159.9, 2166.9,
  2168.5 (all between y 700 and 875 on the trail)

Video layout (150 s; ~2,180 sim s; the prologue M17d goes before 0, the finale M17e after
150, so every time here shifts by the prologue's length in M17g):
| video s | sim s | layout | content |
|---|---|---|---|
| 0–25.5 | 0–25 | nest | fade in, title, queen and pellet garden close (zoom 5.5→8.5), first egg laid at 13 |
| 25.5 | +30 jump | | dip; chapter "Egg, larva, pupa, worker"; brood id 9 followed (zoom 11) |
| 26–36.5 | 56–66 | nest | larva, fed at 60.6 (V30.6) |
| 36.5 | +40 jump | | dip |
| 37–46 | 107–116 | nest | pupa |
| 46 | +30 jump | | dip |
| 46–57.5 | 146–157.5 | nest | callow freed, ecloses at V52.5, followed as a minim |
| 57.5–76 | 157.5–225 | split | "Breaking ground": entrance opens at V58; time-lapse (tpf 4) V69–73 |
| 76–90 | 225–239 | split | "Leaf to fungus": cutter followed from V84 (across) to the garden |
| 90–106.5 | 239–255 | nest | garden, pulp, brood pile; captions on fungus farming |
| 106.5 | +1886.5 jump | | long fade; grade to daylight |
| 106.5–130 | 2142–2165 | surface | "The trunk trail": establishing at zoom 1.35, debris at V114.5, majors, hitchhiker follow |
| 130–142 | 2165–2177 | split | "Taking out the waste": middens (surface), `carry_spent` follow (nest) |
| 142–150 | 2177–2185 | split | pull-back (nest fit excavation, surface zoom 0.9), dusk grade, fade out |

Draft: see "Draft video" below. Stills of every beat were checked (framing, captions, subject
in shot); fixed after them: brood zoom 9 → 11, nest camera onto the chamber for the arriving
fragment, trunk-trail zoom 2.8 → 3.8 on the first pickup.

Draft video: `renders/leafcutter_life_seed3_20260928_084235.mp4` (AVI capture, 150 s, 9000
frames; recording took 24 min, most of it the 1886 s jump at V106.5 and the late sim).

What reads badly (for review and M17d–g):
- The followed brood item isn't marked: in a pile of eggs or pupae you can't tell which one
  is "ours". A soft ring on the story target (render only, like the split layout's
  highlight ring) would fix it.
- Four fades in 35 s during the lifecycle; the dips may feel choppy. The larva's feed
  (V30.6) falls under the chapter caption and the gongylidia hand-over is tiny.
- The sim seals four minims in with the queen (Atta queens raise the first brood alone);
  captions avoid saying otherwise. A queen-only founding stalls in the current sim (one
  worker, brood stuck): M17d must keep the minims or fix that.
- Breaking ground skips the dig (sim 65–158): the hole just appears after the dip at V57.5.
  The time-lapse V69–73 (tpf 4) is visible as a speed-up with no cue that time passes.
- Leaf to fungus: the fragment is followed from the leaf to the garden, but chewing to pulp,
  planting and fungus growing over it are small at zoom 6 and don't read as a sequence.
- Trunk trail: only ~320 ants (~190 on the surface) at sim 2150, so the trail is sparse for
  a "trunk trail"; majors are hard to tell from medias at zoom 3–4; the twigs are small.
  The hitchhiker follow (V124.5) takes whichever hitchhiker is nearest; not checked in frame.
- Waste: deaths are ~1 per 9 s, so the nest camera follows spent garden, not a corpse; the
  dead aren't singled out. Middens lie ~100 units from the entrance, not "far".
- Closing: the nest is 5–6 chambers and a few hundred ants, not a sprawling mature nest.
  A later closing (more sim time) or a bigger colony needs more recording time.
- Length: 150 s + ~15 s prologue + ~20 s finale ≈ 185 s, over the 180 s target: trim in
  M17g (lifecycle holds, waste).
- Grade: the sealed-nest grade is dim; the surface under the close leaf (V58–90) is dark.
- The split layout's new-worker ring (`NestType.highlight_ant`) pops up on the surface
  (seen at V71 and V133–145); a cinematic scenario probably wants it off.
- V53–57: the freshly eclosed minim is followed at zoom 7 but isn't identifiable among the
  others (same as the brood marker point above).
Frames spot-checked from the MP4 (26 times): framing, captions and safe zones are right;
the fragment carrier is in shot from the leaf to the garden; debris and trail read at zoom
3.2–3.8.

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
