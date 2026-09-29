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
scenario, story probe), M17c2 done (brood nurseries), M17c3 done (polish), M17d done (the
queen's landing), M17e done (alates and the nuptial flight), M17f done (phorid flies),
M17g done (final assembly and render). M17 is complete. Next: M16 (scenario editor).
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

### M17c2: brood nurseries — DONE

Goal (user request): a clear visual distinction of where eggs, larvae and pupae lie, with a
different floor colour beneath each, in distinct chambers once the nest is big enough; in
every nest with a queen and an underground (core, always on; state hashes of nests with an
underground change, accepted).
Files: `sim/nests/colony_nest.gd` (nurseries), `sim/nests/brood_care.gd` (carry priority),
`sim/nests/nest_chambers.gd` (`plan_chamber(..., near)`), `species/leafcutter/fungus_nest.gd`
and `species/harvester/granary_nest.gd` (no store in nurseries, `holds_food`),
`render/soil_renderer.gd` + `render/soil.gdshader` (floor tones), `tests/test_nurseries.gd`,
README (leafcutter nest section, harvester section).
Verify: new tests; full suite; `nest_probe` over 7200 s for `colony_founding` and
`harvester_founding` and `story_probe` for `leafcutter_life` seed 3 against HEAD (run side
by side from a worktree of HEAD); stills of the nest.

**Done.** As planned, plus changes to nurse work that the nurseries needed. Nurseries lie
~100 units apart (queen → eggs → larvae → pupae in `colony_founding`), and nurses walking
between them first cost `colony_founding` 21% of its ants by 7200 s. The fixes are in
`sim/nests/brood_care.gd`, `sim/behaviours/nurse.gd` and `sim/nests/brood.gd`, and they
apply only while nurseries are in use:
- **Batched feeding:** a nurse fetches food for up to 4 larvae (`FEED_LOAD`) and feeds hungry
  larvae within 24 units (`FEED_REACH`); what's left goes back to the store.
- **Local work first:** a task's rank drops by 1 per 40 units away (`LOCAL_REACH`), and idle
  nurses wait spread over the three nurseries.
- **Starving larvae first:** a larva at hunger 1 gets rank 5.5.

A further fix also applies without nurseries: brood put down outside a chamber goes straight
to its pile. This was the late slump in `colony_founding`. When a nurse carrying brood died
of old age or was sent to carry a corpse, the brood dropped in a gallery. Nurses navigate by
chamber and portal nav fields, never reached it, and each one that claimed it was stuck for
good. By ~6000 s, 60+ nurses were walking to 68 callows lying in galleries.

Tried and dropped:
- `FEED_LOAD` 8 / `FEED_REACH` 40 (no better).
- A fungus garden in the larvae's nursery (no better; walking, not food, was the limit).
- 25% more nurses (no better while nurses were stuck).

Probes after the fixes, 7200 s:

| Run | M17c | M17c2 |
|---|---|---|
| `colony_founding` | 3550 ants | 3632 ants |
| `harvester_founding` | 4569 ants | 4618 ants |

`colony_founding` loses 425 larvae to starvation by 7200 s. At 5000 s it has lost 170,
against 71 at M17c.

`leafcutter_life` seed 3 story probe:

| Beat | M17c | M17c2 |
|---|---|---|
| 200 ants | 1708 s | 1801 s |
| 300 ants | 2095 s | 2187 s |
| First debris cleared | 2153 s | 2153 s |
| First corpse on a midden | 1120 s | 1120 s |

Stills (nest layout): `colony_founding` at 3000 s and `harvester_founding` at 2000 s show the
three floors clearly. The harvester's three nurseries lie spread over the nest rather than
together (the site nearest the queen was taken). Growth is unaffected, so this is left as is.

Hashes: every underground nest's hash changes (nurseries, and brood put down in galleries);
single-layer hashes and native parity are unchanged.

For M17c3: the lifecycle chapter can follow brood from the egg nursery on through the larvae
and pupae nurseries (M17b's `"follow": {"brood": ...}`), and the three floor tones make the
stages readable. Re-run the story probe first, since the beat times moved.

### M17c3: polish the draft

Goal: fix what reads badly in the M17c draft (list under M17c) that doesn't belong to
another phase, and use the nurseries in the lifecycle chapter. Queen-only founding stays
with M17d, and the length trim with M17g.
- **Story marker:** a soft ring on the followed brood item or ant (render only, like the split
  layout's highlight ring).
- **Nest ring:** the new-worker ring off for this scenario (a render option).
- **Lifecycle:** fewer dips. Follow brood egg nursery → larvae nursery → pupae nursery, so
  the floor tones carry the stages, and keep the larva's feed out from under captions.
- **Breaking ground:** show part of the dig, and cue the time-lapse (caption or grade).
- **Leaf to fungus:** closer framing on chewing, planting and growth.
- **Trunk trail:** a denser trail, majors that read (zoom or caption), and a hitchhiker
  follow checked in frame.
- **Waste:** follow a corpse to the midden if one comes in the window, else re-caption.
- **Grade:** brighten the sealed nest and the leaf close-up.

Files: `scenarios/leafcutter_life.json`, render files for the marker and the ring option,
README, tests for any new render keys.
Verify: story probe (seed 3, and a re-pick of the seed if the nurseries moved the beats
badly), stills of every beat, a `FORMAT=avi` draft checked for resolution, fps and
duration, and the full suite.

**Done.** Render side:
- `render.story_marker: [{"t", "until", "fade"}]` (`render/story_marker.gd`, `StoryMarker`):
  a soft pulsing ring on the camera story's target, drawn in world space on top of each
  WorldView (one per camera, created by `ScenarioPlayer`). `CameraDirector.story_pos()`
  gives the story ant's or brood item's position on that camera's layer (null elsewhere).
- `render.layout.highlight: false` turns off the split layout's new-worker ring.
- Tests in `tests/test_camera.gd` (marker alpha, `story_pos` for ants and brood, markers
  created, highlight option); README (render keys, scenario description, probe args).
- `tests/story_probe.gd`: prints when the nurseries come into use and where, then follows
  the first egg laid after that (and after an optional 5th arg, `track_after` sim s)
  through its stages, carries and feeds to the ant it becomes.

Seed 3 kept: the nurseries didn't move the early beats (first egg 13.3, open 158, first cut
231, fragment underground 239 are as in M17c); debris pickup 2150.0, first 5 cleared by
2153.9 (faster than M17c). Nurseries in use at 1770 s: eggs (815, 688), larvae (669, 902),
pupae (587, 850). Egg id 247: laid 1772.6 at the queen, carried 1776.9–1782.5 to the egg
nursery, larva 1802.7, carried 1808.9–1821.9, fed 1837.9, pupa 1869.9, carried
1873.5–1877.6, callow 1909.9, ecloses 1918.3 as ant 224 (a media).

Scenario, restructured (163 s; the video order is now founding → breaking ground → leaf to
fungus → lifecycle → trunk trail → waste → close):
| video s | sim s | layout | content |
|---|---|---|---|
| 0–25.5 | 0–25.5 | nest | title, queen and pellet garden, first egg (id 9, marked) |
| 25.5 | +124 jump | | dip; "Breaking ground" |
| 26–35 | 150–159 | nest | a marked digger at the shaft face; the entrance opens at V34 |
| 35–53 | 159–231 | split | nest opens; time-lapse V41–47 (tpf 6) captioned "Days pass..." |
| 53–62 | 231–240 | split | "Leaf to fungus": marked cutter followed (across) to the nest |
| 61.5–83 | 240–336 | nest | garden close-up (zoom 10), pulp; growth time-lapse V72–78 (tpf 8) |
| 83.5 | +1437.5 jump | | dip; "Egg, larva, pupa, worker" |
| 84–124 | 1774–1925 | nest | egg 247 followed and marked through the three nurseries; real time on carries and the feed, ramps up to tpf 4–8 between |
| 124.5 | +218 jump | | dip; daylight grade |
| 125–146 | 2143–2164 | surface | trunk trail (zoom 2.7–2.9), marked major with a twig, marked hitchhiker |
| 146–156.5 | 2164–2175 | split | waste: marked corpse carrier (surface), `carry_spent` (nest) |
| 156.5–163 | 2175–2181 | split | pull-back, dusk, fade out |
Only four full dips now (was eight); the old lifecycle dips are time-lapses. Grades
brightened: sealed nest 0.92 → 1.02 (vignette 0.45 → 0.36), leaf close-up 0.96 → 1.08.
Timing was placed from the probe with a throwaway script integrating the tpf schedule
(sim time at a video time); `record.gd --stills` confirms it (e.g. V106.3 = sim 1838).

Stills of every beat were checked (`renders/stills_c3a`): marker on the egg, digger,
cutter, brood 247 in each nursery (floors read clearly), new worker, major, hitchhiker and
corpse carrier. Fixed after them: dig shot zoom 5 → 6.5 with a marked digger, garden zoom
8–9.5 → 10–10.5, trunk-trail establishing zoom 2 → 2.7.

Draft video (M17c3): `renders/leafcutter_life_seed3_20260928_231702.mp4` (AVI capture,
1080x1920, 60 fps, 163.0 s, 9780 frames; ~27 min to record and encode). Frames at V29,
V68 and V127 spot-checked after the framing fixes.

Still reading badly / left for later phases:
- Length 163 s (was 150); with the prologue and finale ~200 s. Trim in M17g (lifecycle
  holds, trunk trail, waste).
- Trunk trail still ~300 ants; a denser trail needs more sim time (recording time) or
  faster growth. Traffic is split with the (800, 1300) leaf's trail.
- The pupa nursery's pale sand floor looks blocky (square cells) at zoom 7–9: a soil
  shader detail to smooth (render only).
- The fungus growing over the pulp is subtle in the small founding garden.
- The waste chapter's nest half follows `carry_spent` but it isn't marked (one story).

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

**Done.** Sim (all opt-in; without `"landing"` nothing runs, draws random numbers or is
hashed):
- `sim/nests/founding.gd` (`Founding`, owned by `ColonyNest.founding`): phases FLYING →
  SHEDDING → WALKING → DIGGING → GOING_DOWN → HOME. Flight: a quadratic curve from `from` to
  `land`, eased out, altitude `altitude * (1 - t)^1.5`; she is placed on the curve each tick
  (no collisions). Shedding: right pair at 35%, left at 75% of `shed` (`Wing` items,
  `sim/items/wing.gd`, item type `"wing"`, destroyed at `wing_life`). Walk: four waypoints
  round the entrance at `loop_radius`, then its middle (`Steering.move_to`). Dig: she turns
  over the hole; `spoil_pellets` pellets go on the heap (`receive_spoil`). Then
  `sim.enter_portal(i, portal, true)` (new `force` arg: through the closed portal) and, on
  the nest layer, she is put in her niche (fading in) and the state becomes `"queen"`.
- `sim/behaviours/found_nest.gd` (core, registered after `carry_corpse`); allowed only for a
  queen of a nest with a landing, through a new `NestType.extra_states(caste)` hook in
  `Colony.build_allowed_states` (so other runs' state ranks, and hashes, are unchanged).
- `ColonyNest`: `spawn_initial` spawns the queen in the air and holds workers back
  (`Founding.waiting`, placed in the royal chamber when she's home); `_update_colony` returns
  early until she's home (brood, laying, roles, digging wait); `queen_home()`; FungusNest
  doesn't manure before. `entrance_sites()`: no main entrance drawn before she digs, an open
  hole growing while she digs, then as the nest has it (sealed: refilled).
Render: `NestType.winged_ants(sim)` (ant → pairs on, altitude, beating); `render/wing_renderer.gd`
(`WingRenderer`, two passes per WorldView: ground shadow under the ants, offset along the
light by altitude; wings over the riders: beating blur fan in flight, held out gliding in,
folded over the abdomen on the ground), `render/wing_look.gd` (one wing: membrane, leading
edge, vein, stigma), `AntRenderer.LIFT_SCALE` (body drawn larger in the air), `ItemRenderer`
draws shed wings and fades them over their last third.
Scenario: `scenarios/queen_landing.json` (the prologue on its own, 25 s: leafcutter_life's
colony with `founding.landing` = from (300, 700), land (520, 1040), altitude 260, flight 7,
shed 5, loop_radius 10, dig 12; real time for flight and shedding, 3x walk, 4x dig; three
captions, fades). Phase times (seed 3): lands 7.0, walk 12.0, digs 24.7, goes down 36.7,
home 37.3 (sim s) = video ~V7, V12, V16.3, V19.7, V20.3. `leafcutter_life.json` is **not**
changed: the landing delays every underground beat by its length (~37 s), so M17g merges
the prologue and re-runs the story probe.
Tests: `tests/test_founding_landing.gd` (7: starts in the air with two pairs and no
entrance; lands at `land`, hole drawn while digging, ends in her niche, 2 wings on the
surface where shed, 5 ants, still sealed, pellets on the heap; underground waits (brood
ages, eggs, manuring); wings decay; the first workers dig the shaft open later;
deterministic; a `"founding"` key without `"landing"` hashes as none). `tests/test_native.gd`
runs `queen_landing` (1800 ticks) both ways. Fingerprints of `colony_founding` (1500 ticks),
`leafcutter_life` (1800) and `harvester_founding` (1500) match HEAD before M17d.
Stills (`tools/screenshot.sh queen_landing <ticks> ... --layout=surface`): flight with
beating wings and the shadow falling on the leaf, gliding in, folded wings, one pair shed,
both pairs on the ground, digging (hole), sealed plug with the wings beside it.

Fixed on the way (render): the ant MultiMesh now has fixed world-sized bounds
(`multimesh.custom_aabb` in `AntRenderer.bind`). The canvas item only takes the MultiMesh's
bounds when it's redrawn, so with a lone ant (the landing queen) the bounds went stale and
her body was culled once the follow camera moved away from her start. Stills didn't show it;
the first AVI draft did (wings with no body).

Draft video (M17d): `renders/queen_landing_seed3_20260929_002040.mp4` (AVI capture,
1080x1920, 60 fps, 25.0 s, 1500 frames). Frames at V4, V9.5, V14, V18, V20, V21 and V24 were
checked. They show flight with beating wings and her shadow, the wings coming off, the
walk, digging, going down and the sealed plug.

Changed from the plan: no dig job from the surface. The shaft cells stay soil and she is
moved to her niche after the portal fade (the nest camera isn't shown then); the minims later
dig the same shaft (`chambers_layout.shaft`) open as before. The minims are kept (sealed in
with her when she arrives), as M17c noted. Wings decay rather than being carried out.

`nest_probe` over 7200 s, `colony_founding` against a copy of it with `"founding":
{"landing": {}}` (default landing, ~50 s), run side by side:

| sim s | without | with landing |
|---|---|---|
| 3000 | 575 ants | 494 ants |
| 4200 | 1465 | 1464 |
| 5400 | 2391 | 2408 |
| 7200 | 3632 (25 chambers, 3 entrances) | 3808 (28 chambers, 3 entrances) |

The landing run starts ~50 s late, catches up by 4200 s and grows as well after that (the
runs differ by their random numbers from then on). The nest grows fine with the landing.

For M17g: take the prologue's colony params, camera keyframes, tpf points and captions from
`queen_landing.json` into `leafcutter_life.json` (shift everything after by ~20 s of video
and every sim time by the landing's ~37 s), and re-run `story_probe`.

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

**Done.** Sim (all opt-in; without `"alates"` nothing runs or is hashed):
- `sim/nests/alates.gd` (`Alates`, owned by `ColonyNest.alates`, nest_params `"alates"`,
  needs an underground). Raising: `Brood._brood_caste` asks `Alates.next_caste()` for every
  egg laid (after `first_workers`); past `from_population` the next `count` eggs are alates,
  shared out over `castes` weights by largest shortfall (no RNG). Alates emerge like any
  callow; `ColonyNest.first_state()` gives them `"alate"`; they never go abstract
  (`free_callow`), don't age (no carry capacity) and don't count in `workers_alive()`.
  Scenario `population` may include them.
- Per alate (parallel arrays in `Alates`, hashed): WAIT (wander in the dug chamber nearest
  the main shaft, pauses from `sim.rng`) → UP on a flight (one every `stagger` s, via
  `Travel.to_portal`) → GATHER on the mound (sunflower spots within `gather_radius`, off the
  hole, milling) → TAKE_OFF (first out first, from `gather` s after the call, every ~`every`
  s; `warm_up` s beating on the ground, then `climb` s: altitude `altitude * u^1.6`, drifting
  `distance * u^2` toward `drift` fanned over `spread`, clamped inside the world) → removed
  in `Alates.update()` (outside the ant loop), counted in `flown`/`flown_by`.
- Escorts: once a second while alates are out, up to `escort` surface workers within
  `escort_reach` (not carrying or riding; biggest caste first, then nearest) are put in
  `"escort"`: they mill round the mound at 1–1.6 × `gather_radius` and go back to their
  caste's `initial_state` when the flight is over.
- Core states `alate` (`AlateBehaviour`, joins/leaves `Alates` in enter/exit) and `escort`
  (`EscortBehaviour`), registered after `found_nest`; allowed only through
  `NestType.extra_states(caste)` (now takes the `CasteDef`, not its id) when the nest has
  alates: `alate` for alate castes, `escort` for castes with carry capacity and surface states.
- Scenario event `{"type": "nuptial_flight", "colony": n}` → `NestType.start_nuptial_flight()`
  (false for nests without alates, or while a flight is under way).
- `CasteDef.alate`; `leafcutter.tres` gains `gyne` (size 20, like the queen with a smaller
  abdomen) and `male` (15, dark, small head, big thorax), spawn_ratio 0, initial state
  `alate`, after the queen. Hashes: `state_hash()` hashes `abstract_by_caste` only up to
  `SpeciesDef.hashed_castes()` (castes before the first alate), and new castes allow no
  states without `alates`, so no existing hash moved (see below).
Render: `ColonyNest.winged_ants()` adds every alate (`Alates.wings_of`: folded in the nest and
going up, held out now and then on the mound, beating with altitude on take-off), so M17d's
`WingRenderer` and `AntRenderer.LIFT_SCALE` draw them with no render change.
Scenario: `scenarios/nuptial_flight.json` (the finale on its own, 32 s): leafcutter_life's
ground, an open nest with 3 chambers, 134 workers and queen, 5 gynes and 9 males; flight
called at sim 1 s. Probe (seed 3): first alate out 8.0, escorts 9.4, take-offs 10.8–~28,
last gone ~34 sim s; video: 3x until V2.3, real time from V3; camera on the mound zoom
5.5 → 4.5 → 2.8 pulling back as they climb; dusk grade; three captions.
Tests: `tests/test_alates.gd` (7: brood raises 2 gynes + 4 males past the population, all
waiting underground; none below it; the whole flight — gathering, escorts, all drawn with
wings, climbing, all flown by caste, escorts back to work, queen stays; a male emerging after
a flight waits for the next; deterministic; off without params (no states allowed);
`hashed_castes`). `tests/test_native.gd` runs `nuptial_flight` (900 ticks) both ways.
Stills (`tools/screenshot.sh nuptial_flight 0 out.png 3 --at=<video s>`): alates on the
mound with folded and spread wings among the escorts, several climbing away with beating
wings and fading shadows. Fixed after them: `gather_radius` 26 → 45 and alates kept off the
hole (they piled up on the entrance), UP at full speed (the walk up took ~9 s).

Hashes: `state_hash()` after 1800 ticks, GDScript and native, of `colony_founding`,
`leafcutter_life`, `queen_landing`, `fungus_farm`, `trunk_trail`, `leaf_strip` and the
`brood_demo`, `garden_demo`, `nest_bench`, `midden_demo` and `entrances_demo` fixtures are
identical to HEAD before M17e (baseline recorded in a worktree of HEAD). Full suite passes
(the leafcutter caste count in `test_simulation` is now 6).

Draft video (M17e): `renders/nuptial_flight_seed3_20260929_083831.mp4` (AVI capture,
1080x1920, 60 fps, 32.0 s, 1920 frames). Frames at V5, V10, V13, V17, V22 and V27 were
checked: alates spread over the mound among the escorts, several climbing away with beating
wings, the last few leaving as the camera pulls back. Reads well enough as a finale; left
for M17g: alates in the nest aren't shown (the finale is surface only), the mound is crowded
with ~100 workers that come out at the start of this standalone run, and males vs gynes
are told apart only by size and colour.

For M17g: add to `leafcutter_life`'s colony `"alates": {"from_population": 150, "count": 14,
"castes": {"gyne": 1, "male": 2}, ...}` with the finale's flight params from
`nuptial_flight.json`, and a `nuptial_flight` event just before the closing; check with the
story probe that the alates have emerged by then (egg to adult is ~135 s plus carrying at
leafcutter_life's brood times; population 150 comes ~1500 s) and place the finale's camera,
captions and grade from `nuptial_flight.json`.

### M17f: phorid flies (optional flavour)

Goal: tiny parasitoid flies hover over the trail and dive at fragment carriers; a carrier
with a hitchhiking minim is left alone, one without is chased (sim: species-local fly
agents with their own RNG stream split from `sim.rng` only if enabled, or render-only if
the effect can be faked from sim state: flies drawn around carriers without riders).
Prefer render-only (no hash risk): `species/leafcutter/phorid_renderer.gd` registered as a
renderer, reading carriers and riders from sim state.
Verify: stills; suite. Skip if M17c's draft already reads well without it.

**Done** (render-only, as preferred; no hash can move):
- `species/leafcutter/phorid_flies.gd` (`PhoridFlies`): the fly model, opt-in by
  nest_params `"phorids"` (kept on `FungusNest.phorids`, never read by the sim). Own
  `RandomNumberGenerator` (seeded from colony id and `seed`). Moved from sim state once per
  frame (`update(sim, now, alpha)`): carriers are the carried `item` ("leaf_fragment") items
  on the surface; guarded = the item has riders. Per fly: AWAY (fades out; turns up near a
  random carrier every `arrive` s) → TRAIL (hangs 12–22 units off the carrier's head for
  0.8–2.2 s) → DIVE (3x speed at the head, dropping low) → a guarded carrier: veers off at 13
  units (`veered`); unguarded: hit at 2.5 units (`hits`) → VEER (flung off, 0.35–0.7 s) →
  TRAIL again while `dives` last, else the nearest other carrier within `reach` (each fly
  already after one counts as 80 units further; guarded or not is only found out on the
  dive) or AWAY. Carriers within `clear` (90) of the nest entrance are ignored: at first
  every fly ended up bunched on the entrance chasing carriers that went underground before
  it could dive, and with "unguarded first" picking no fly ever veered. After a jump in time
  (first frame, fast-forward to a still) it catches up over up to 8 s in 1/30 s steps.
  Params: count 5, reach 170, dives 3, speed 70, altitude 9, arrive 2, clear 90, item, seed.
  Over 150 s of trunk_trail (8 flies): ~290 hits, ~25 veers.
- `species/leafcutter/phorid_renderer.gd` (`PhoridRenderer`), registered as
  `"surface_top:fungus_nest"`: ground shadow offset by altitude (WingRenderer.LIGHT),
  beating pale wing blur, hump-backed dark body, 3.4 units long (a little larger than life
  so it reads). New core hook: `WorldView` attaches a nest's `"surface_top:<type>"` renderer
  on the surface over ants, riders and wings (the surface twin of `underground_top`).
- Scenarios: `trunk_trail.json` (count 8) and `leafcutter_life.json` (count 6) have flies.
- Tests: `tests/test_phorids.gd` (5: over 150 s of trunk_trail, flies hit unguarded carriers
  and veer off guarded ones, never hitting a guarded one; active flies stay by a carrier;
  same `state_hash()` with and without; deterministic; off without params).
Stills (`tools/stills.sh trunk_trail 6,11,17`, 1080x1920): flies visible by the fragment
carriers as dark flecks with wing blur and a shadow; at trunk_trail's zoom (~1.3 at V11) they
are small, so they read on close-ups (zoom 4+), which is where leafcutter_life's trail shots
are. No draft video this phase (render-only, checked with stills).

For M17g: the flies are already on in `leafcutter_life`; check them in the AVI draft on the
hitchhiker close-up (t≈140 camera follow) and tune `count`/`reach` if the trail shot is too
busy or empty.

### M17g: final assembly and render

Goal: put the prologue (M17d), finale (M17e) and flies (M17f) into `leafcutter_life.json`,
re-run the story probe, retime captions/camera, check frames against the safe zones
(`tests/frame_probe.gd`), update the README (scenario list, captions/fades/grade, camera
keyframes, landing/alates params), AVI draft then the PNG final (background, ~2 h).
Verify: full suite; draft reviewed; final MP4 in `renders/`.

**Done.** `leafcutter_life.json` now tells the whole story in 198 s (was 163): the colony has
`founding.landing` (queen_landing's), `alates` (from_population 150, count 14, gyne 1 :
male 2, nuptial_flight's flight params except `stagger` 0.4 and `gather` 20, see below),
`phorids` count 10 and a `nuptial_flight` event at sim 2172. No sim or render code changed;
no hash moved (leafcutter_life isn't in the hash tables; queen_landing and nuptial_flight
keep their native parity runs).

Story probe (seed 3; `tests/story_probe.gd` now also prints the landing phases, the alate
beats and, during a flight, per-second counts of alates waiting / going up / on the mound /
taking off / flown). Seed 3 kept: every beat happens, in view. The landing delays the
underground by more than its 38 s (the entrance opens at 305, was 158):
| beat | sim s |
|---|---|
| lands / walks / digs / goes down / home | 7 / 12 / 25 / 37 / 38 |
| first egg (id 9) | 50.6 |
| entrance open / first cut / fragment underground | 305 / 371 / 383 |
| alate eggs laid / all 14 alates waiting | 1544–1597 / 1737 |
| nursery egg 258: laid, carried, larva, carried, fed | 1791.4, 1793.5–1799.5, 1821.4, 1822.9–1837.6, 1854.1 |
| pupa, carried, callow, ecloses (a media) | 1886.2, 1887.5–1892.3, 1926.2, 1935.2 |
| debris dropped / first 5 cleared | 2150 / 2150–2155 |
| flight called / 13 on the mound / all gone | 2172 / 2193 / ~2214 |

| video s | sim s | layout | content |
|---|---|---|---|
| 0–20.3 | 0–37 | surface | title over the flight; landing, wing shedding, walk (3x), dig (4x) |
| 21.2–38.5 | 38–55.5 | nest | queen home, pellet garden, first egg (brood 9, marked) |
| 38.5 | +240 jump | | dip; "Breaking ground": marked digger at the shaft face |
| 48–74.7 | 305–383 | split | nest opens; "Days pass..." time-lapse (tpf 6); "Leaf to fungus": marked cutter followed across into the nest (2x on the walk home) |
| 75–94 | 383–462 | nest | garden close-up, pulp; growth time-lapse (tpf 8) |
| 94 | +1330 jump | | dip; egg 258 followed and marked through the three nurseries (1x on carries and the feed, 3–16x between) to a new worker at V135.6 |
| 138–155 | 2145–2162 | surface | trunk trail; marked major clearing debris; marked hitchhiker, phorids |
| 155–164 | 2162–2171 | split | waste: marked corpse carrier, `carry_spent` in the nest |
| 164–172 | 2171–2191 | split | dusk; "The next generation": marked alate in the nest; flight called V165, 3x over the walk up |
| 172–198 | 2191–2216 | surface | alates crowd the mound and take off one by one; closing captions, fade |

Timing was placed with the new `tests/timeline_probe.gd` (the "throwaway script" of M17c3,
now a documented probe: sim time at video times and video time/speed at sim times, from a
scenario's `ticks_per_frame`).

Fixed on the way (scenario data, and documented in the README's camera section):
- A follow picks its target at the *previous* keyframe's time. The first-egg, nursery-egg
  (across the jump), debris-major and cutter follows all resolved before their target
  existed and the camera went to `near` or the world's corner. Each now has a `pos` keyframe
  just after the egg / jump / event, and the follow after it.
- A follow eases toward the next `pos` keyframe over the whole gap, so the major,
  hitchhiker and corpse follows drifted off their ants; `{"ant": "same"}` holds before the
  cuts now (not on the nest's `carry_spent` shot: that ant leaves the layer).
- The alates' waiting chamber is far from the shaft in the grown nest: the walk up took
  ~12 s, and take-offs at `gather` 9 drained the mound as it filled (at most 6 on it). With
  `stagger` 0.4 and `gather` 20 all 14 set off within 6 s and 13 are on the mound when the
  first takes off.
- Hitchhiker follow: the trail runs at x≈460 there (near [540, 760] picked a far one).
- Phorids 6 → 10: at 6 about one fly was in frame on the trail close-ups.
- The dusk grade brightened a little (1.0 → 1.06 at the start, 0.86 → 0.92 at the end).

Safe zones: frames of the draft every few seconds (46) were checked with the TikTok/Reels
zones (top 150, bottom 400, right 120 px) drawn over them (ffmpeg `drawbox`; `frame_probe.gd`,
named in the plan, is an FPS probe and doesn't check zones). Captions sit inside the safe
area by construction; the story targets and marker rings were inside in every frame
checked. The only miss was the cutter at the top of the split view at V68, from the
unresolved follow above, and that is fixed now.

Tests: `test_scenario::test_leafcutter_life_loads_and_runs` also checks the landing (in the
air at the start, home by 60 s), alates, phorids and one nuptial_flight event. Full suite
passes.

Draft video (M17g): `renders/leafcutter_life_seed3_20260929_103508.mp4` (AVI capture,
1080x1920, 60 fps, 198.0 s, 11880 frames). The camera fixes after it (cutter, holds, nest
waste shot) were checked with stills (`renders/stills_g3`); they change only the cameras, so
the sim is the same. Stills tool quirk seen: the first still of a run can miss ants and the
garden (the same moment was fine in the video and in the next still).

Final video: `renders/leafcutter_life_seed3_20260929_111827.mp4` (PNG capture, 1080x1920,
60 fps, 198.0 s, 11880 frames, 154 MB; ~1 h 50 min to render and encode). Frames at V69,
V147, V152, V160 and V180 spot-checked: marked cutter at the leaf, major and hitchhiker
centred, the nest's waste shot, alates taking off.

Left for later (not blocking): the pupa nursery's blocky pale-sand floor (M17c3 note), the
colony is ~250 ants at the trunk trail (a denser trail needs more sim time), and gynes vs
males are told apart only by size and colour.
