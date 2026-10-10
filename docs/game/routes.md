# Real-world routes: road, world and first catalog routes

Requirements: REQ-D3D-11 (p.1, 3, 6, 10, 12, 13), REQ-D3D-08, REQ-D3D-05, REQ-STR-06 p.7.
Owner decisions: У-40 (own built-in catalog), У-41 (road shape as in real life, built from our
stylized assets), У-44 (first routes — the most spectacular, "unreal-looking" roads in South
China and on islands). Open: Н-78 (г), (е); Н-80 (owner confirms the route list, section 9).
Tasks: T-178 (sections 1–8, this spec), T-191 (section 9, route shortlist). Consumers:
technical-artist T-184 (road), T-185 (scenery, streaming); developer T-180, T-181, T-186 (data).
Style: `art-bible.md`, section "Real-route environment sets" (new sets `env_karst`, `env_gorge`).
Stylized tracks (`flat`, `hills`, `mountains`, `seaside`) stay as in `tracks.md`; nothing here
changes them.

## 1. Pillars of a real route

1. **The road on the screen is the road on the map.** Order and direction of turns, the
   hairpins and the climbs match the real route (D3D-11 p.10, p.13). We simplify the
   world, not the road.
2. **One look says where you are.** Karst towers over rice fields, a marble gorge with a
   jade river, or a stack of hairpins on a cliff: each route is recognizable from one frame
   without a caption, like the four stylized tracks (D3D-08 p.8).
3. **Nothing pops in front of the rider.** The road ahead, the terrain to the horizon and
   the landmarks are always there; only small detail (grass, bushes, far trees) may fade in
   (section 7).
4. **An hour without boredom on a real road.** A new landmark or scenery zone at least every
   1.5 km (D3D-08 p.12 rule applied to routes). On the way back (out-and-back, D3D-11 p.6)
   the world is the same: the same trees stand in the same places.

## 2. Before: what the current worlds give a real route

Frames: `shots/2026-10-10-t178/before/` — `mountains/ride_{1000,6000,8600}m.png`,
`seaside/ride_{1800,6100,8600}m.png` (`./scripts/screenshot.sh`, 32 km/h, 90 rpm,
gl_compatibility). The "climb" and "bend" fixtures of D3D-11 p.12 cannot be shot yet: they
need T-180/T-181 data and the T-184 route track. Their "before" is the current stylized
tracks, these six frames.

Checklist `ride-visual-review` (items 1–11; item 12 is not run, nothing was changed):

- Items 1–8 pass on all six frames: ground to the horizon, sky gradient, rider silhouette,
  road as the leading line, three depth planes with haze, toon light with blue shadows,
  palette per art-bible, no overexposure under the HUD area.
- Item 9 passes (several conifer forms, umbrella pines, bushes, lighthouse; no grid).
- Item 10 passes (posts, tufts and guardrail pass the camera).
- Item 11: no artifacts seen.
- Result: 11/11 run items on every frame, no blocking items. The worlds are fine as
  stylized tracks.

What they cannot give a real South China / island route (the reason for new sets, section 6):

- Every frame is a meadow with spruce or umbrella pine and snowy Alpine ridges or a
  Mediterranean beach with a lighthouse. Nothing reads as karst, rice paddy, bamboo,
  subtropical forest or a gorge.
- The road is straight or gently curved on every frame. Even the mountains "switchback" frame
  (8600 m) reads as a straight valley road. Real routes have hairpins every 100 m (Tianmen),
  so the road builder and camera must show tight turns (sections 3, 4).
- There are no cliffs close to the road, no tunnels or galleries, and no stacked road levels.
  The gorge and hairpin routes need all three.

## 3. Road on real geometry (for T-184)

### 3.1. Terms

- **Route polyline**: route data points (lat, lon, h), ≤ 50 m apart (D3D-11 p.2).
- **Track axis (rider line)**: the line the rider follows, `Track.sample_into(s).position`.
  The road is built around it: road center is `road_center_offset_m` to the left (−1.4 m
  today, rider in the right lane). **All radii and position tolerances in D3D-11 p.10 are
  measured on the track axis.** Proposal for requirements: say "track axis (rider line)"
  instead of "road axis" in p.10 (а), (в), (г). p.10 (е) clearance stays measured from the
  road center.
- **Hairpin**: a heading change > 120° within 60 m of route length (definition for
  p.10 (а); proposal to requirements).

### 3.2. Projection

- Spherical azimuthal equidistant projection centered on the center of the route's
  lat/lon bounding box, sphere radius 6 371 008.8 m (the same as the haversine in D3D-11).
  x = east, −z = north (Godot: −Z forward = north), y = h(s).
- Why: distances from the center are exact, other distortion is (d/R)²/6 — 0.004 % at 100 km
  from the center. This keeps p.10 (б) and (в) without corrections on any route up to 200 km.
  A plain equirectangular projection fails p.10 (б) on long north–south routes (error
  tan φ · Δφ — 0.7 % for ±0.9° at 24° N).
- Floating origin: scene coordinates are kept relative to an origin that is moved (rebased)
  when the rider is more than 2 km from it. All world nodes are shifted in the same frame;
  the camera-relative picture does not change. Reason: float32 vertex jitter is ~4 mm at
  32 km from the origin and is visible on the rider and on near outlines. `[авто]` proposal:
  on the 200 km fixture the rider's render position is never more than 4 km from the
  scene origin, and the camera-to-rider offset is continuous across a rebase (±1 mm).

### 3.3. Smoothing and minimum radius

The input polyline is OSM nodes (2–30 m apart, corners at every node). The rider needs a
smooth line, and hairpins need a minimum radius. The rule is "smooth only as much as needed":

1. Drop near-duplicates (< 0.5 m), resample uniformly every 2 m by arc length.
2. Gaussian low-pass on (x, z) with σ = 3 m (kernel ±9 m), ends pinned (closed routes —
   periodic). This removes node corners and keeps p.10 (в) (±3° where R ≥ 30 m).
3. Curvature from points 4 m apart. Where the radius is below **R_min = 8 m**, widen the
   turn: Laplacian relaxation restricted to the violating window, the window grows by ±10 m
   per pass, up to 50 passes, until min R ≥ 8 m. Deviation from the projected polyline stays
   ≤ 5 m (≤ 10 m in hairpins, p.10 (а)). If that is impossible, the route data is wrong and
   T-186 must fix it (validation error with route id and s).
4. Heights are not smoothed here: the axis height is h(s) from the route profile (T-181)
   ±0.05 m every 50 m (D3D-08 p.4 via D3D-11 p.10 (д)). Height smoothing is a data step
   (section 8.2).

Numbers to confirm (Н-78 (е)): **R_min 8 m — confirmed by game-designer**, on the track
axis. Why 8 m and not more: real hairpins on Tianmen, Sa Calobra and the 24-zig have a lane
radius of about 6–12 m. At R_min = 12 m the widened hairpin legs move apart by up to 2 × 7 m
and leave the 10 m tolerance. At 8 m the left-hairpin inner road edge is still 8 − 4.65 =
3.35 m from the turn center (the mesh does not fold, section 3.5).

### 3.4. Length and the distance mapping (proposal to change p.10 (б))

A widened hairpin is longer than the real one: a 180° bend with raw radius 5 m widened to
8 m adds π · 3 ≈ 9.4 m. On a hairpin-dense road (Tianmen, about 9 bends per km) this is up to
8 % of the length per kilometer. **As written, p.10 (б) (axis length between points 1 km
apart = Δs ± 0.5 %) cannot hold on such routes.** Proposal:

- The scene path is mapped to route distance s **piecewise between route points**. Every
  route point (≤ 50 m apart) has its own scene arc position. Between two points the rider's
  scene position is the arc fraction equal to the s fraction. There is no drift: the scene
  and s are in step at every route point.
- Where a turn was widened, the extra arc length is spread over ±100 m around it (the local
  scene-speed factor stays within 1.00 ± 0.05). A rider at constant speed does not
  "accelerate" through the hairpin.
- New wording for p.10 (б): "the rider's scene position at s lies on the track axis at the
  arc position mapped from s; the local factor (scene arc / Δs) over any 200 m window is
  within 1 ± 0.05; on routes where no turn was widened, the axis length between points 1 km
  apart = Δs ± 0.5 %." `[авто]` on the "bend" fixture (no widening) and on a new "hairpin"
  fixture (section 8.4).

### 3.5. Cross-section, banking and hairpins

The cross-section is the art-bible one (6.5 m, two lanes, rider in the right lane) unless the
set overrides it (section 6). Additions for real geometry:

| Item | Rule |
|---|---|
| Road width / center offset | per set: `env_karst` lanes 5.5 m / −1.2 m (Yangshuo lanes are 4–6 m wide), `env_gorge` 6.5 m / −1.4 m. Same lane logic: the rider in the right lane of his direction |
| Banking (cross-slope) | 0 on straights (as today). In turns with R < 200 m: superelevation toward the inside of the turn, **4 %** (confirmed ±4 %, Н-78 (е)). Ramp in and out over 20 m (≤ 1 % per 5 m). Why so little: 4 % is 2.3° — the horizon stays level (motion-sickness rule); the turn is read by the rider's lean and the guardrail, not by a tilted road |
| Hairpin outer side | parapet or guardrail on the outside of every turn with R < 50 m (`env_gorge`: concrete parapet 0.6 m; `env_karst`: low stone parapet 0.5 m); plus the existing rule "valley side on climbs" |
| Hairpin inner side | the roadside strips (gravel, curb, grass) are offset curves. On the inner side of a turn, offsets ≥ R_local − 0.5 m are clamped to R_local − 0.5 m (fan around the turn center), so no triangle folds. `[авто]` proposal: every triangle of the road and roadside meshes has a normal with y > 0 (no folded or inverted faces) on the "hairpin" fixture |
| Hairpin markers | a chevron board on the outer side, 25 m before the apex (black on white, art-bible ink tone, not HUD yellow); on Tianmen also a stone stele every 9th bend (landmark, real) |
| Inner widening | not in phase 1. Phase 2 option: +min(2 m, 30 m / R) on the inside of turns with R < 20 m |
| Junctions with other roads | phase 1: none, only the route's own road is built. Phase 2 option: 40 m stubs of side roads at junctions with `highway=primary/secondary`, fading into the terrain |

Rider and camera in tight turns (no code change asked, checks only):

- Lean stays as D3D-07 p.3 (capped at 0.45 rad). At R = 8 m the cap is reached above about
  21 km/h; this is accepted.
- The speed model does not change in turns (p.10 (д)). Descending a hairpin road at
  50–60 km/h through R = 8 m gives a heading rate up to 120°/s. The camera already trails
  the heading (τ = 0.25 s). `[авто]` proposal: on the "hairpin" fixture at 60 km/h the camera
  yaw rate is ≤ 150°/s and the rider stays in frame (D3D-07 p.5). If the rate is higher,
  the camera τ grows with the heading rate (TA decision, no design change).
- `[авто]` proposal: the camera is never inside terrain, walls or objects, and the line from
  the camera to the rider's pelvis is not blocked by terrain, a cut bank or a retaining wall,
  at every 10 m on the "hairpin" and "stack" fixtures (section 8.4).

### 3.6. Elevation in the scene (D3D-08 via D3D-11 p.10 (д))

- Axis height = h(s) of the route profile, ±0.05 m every 50 m; rider pitch atan(g(s)/100)
  ±1° (D3D-08 p.4, p.5). The road surface is the cross-section swept at h(s) plus banking.
  The inner edge of a climbing hairpin is steeper than the axis (grade × R / r_edge). This is
  real and accepted.
- Terrain near the road follows the road height as today (`TerrainField` corridor: flat
  shelf at −0.45 m, cut bank on the uphill side). The height field takes **every road pass
  within its kernel**, not only the one at the current s (hairpin stacks, out-and-back).
- Bridges (`bridge=yes` ranges in route data): deck at h(s), terrain kept ≥ 2 m below the
  deck under its whole width, water under it if a river polyline crosses (section 5.4).
- Tunnels (`tunnel=yes` ranges): phase 1 shows them as a **rock gallery** — a deep cutting
  with an overhang on the mountain side and an open valley side (the real Taroko half-tunnels
  look exactly like that). The sun reaches the road, the HUD stays readable, the camera stays
  outside rock. Ranges longer than 400 m: the same gallery with the overhang closing to a
  portal every 200 m (a short dark band, ≤ 8 m). Fully enclosed tunnels are a phase 2 option.

## 4. Overlapping sections and stacked roads (p.10 (е))

Real routes come back on themselves: out-and-back legs, a loop that reuses a road, hairpin
legs stacked on a slope, and the Sa Calobra "Nus de sa Corbata" where the road passes under
itself. Classification of two route passes A (smaller s) and B (larger s), more than 20 m
apart by s, whose track axes come within road width + 2 m horizontally:

| Δh at the closest point | Case | Scene |
|---|---|---|
| ≤ 0.5 m | **same road** | One road surface. B's road chunks skip the asphalt and roadside where B's axis is within road width of A's. B's rider line lies on A's surface: B's lane is the lane of its direction. Where the passes join or split there is a 30 m taper, as a junction: one road widens into two and the markings follow (one center dash line) |
| 0.5–5 m | **data error** | Not allowed: the validation test fails with the route id and both s (T-186 fixes heights, section 8.2) |
| ≥ 5 m | **grade-separated** | The upper pass is a bridge deck over the lower road (vertical clearance ≥ 4.5 m). Retaining wall from the lower road's edge up to the upper road's edge where they are closer than 6 m horizontally |

Hairpin stacks on a slope (legs 10–40 m apart, 5–20 m higher) are not overlaps: terrain
between them is a steep slope or a stone retaining wall (`env_karst`, `env_gorge`: masonry
wall, art-bible). D3D-08 p.4 holds on both legs: terrain never rises above either road
within its width.

Return pass of an open route (D3D-11 p.6, out-and-back): the road is the same road (case
"same road", built once). The rider moves to the right lane of the return direction: the
rider line shifts by 2 × 1.4 m = 2.8 m to the left of the forward direction (1.2 × 2 =
2.4 m on `env_karst`). The shift is the turnaround below.

**Turnaround at the end of an open route** (proposal to requirements, Н-78 (г)). An instant
reversal at s = L is impossible on a road with R_min = 8 m. The scene shows a turning circle:
a round asphalt area at the end of the road (radius 10 m, low curb, a landmark of the route
in the middle: a pavilion, a viewpoint sign, the cave gate). The rider loops around it at
R = 8 m: the arc is T_turn = 45 ± 5 m long. Proposed change of p.6: for s_cum ∈ [L; L + T_turn]
the coordinate and height stay those of the end point, and the grade is 0. Then the return
pass starts with coordinate at L − (s_cum − L − T_turn). The same at s = 0 when the rider
turns forward again. On the map the turnaround is invisible (a 45 m stop at the end).
Alternative (not recommended): no turning circle; the rider "jumps" to the other lane
behind a fade. That breaks pillar 3 and the motion-sickness rule.

**Closed routes** (laps, p.6): the seam must be invisible. Data rule for T-186: a closed
catalog route has its last point equal to its first point (the closing segment is part of L),
so the gap at the seam is 0 and the smoothing in 3.3 is periodic. `[авто]` proposal: on a
closed route the track axis heading at the seam is continuous (±3°) and the position jump
is ≤ 0.05 m.

## 5. Scenery along the route (for T-185)

### 5.1. Clearance

- No object closer than **road half-width + 1 m** to the road center of **any** route pass
  (not only the pass at the object's s). This is the p.10 (е) rule, applied to all passes
  through a spatial index of the axis (as `ConiferKit.RoadIndex`).
- Distance is measured to the object's footprint edge: trunk or base radius, not the
  instance origin. Crowns must not reach over the asphalt lower than 4.5 m above the road
  (camera at 2.1 m, rider 1.5 m).
- Inside every turn with R < 50 m, no trees within 15 m of the inner road edge. The road
  ahead must be readable through the bend (pillar 1). Only grass and low bushes ≤ 1 m
  are allowed there.
- Turning circle, bridges, galleries: no scenery on them or within 1 m of them.

### 5.2. Placement by zone

The world along a real route is chosen per **scenery zone**: a range of s with a zone type
from the route's set (section 6). Zones are part of the route data (list of
`(s_from, s_to, zone)`), like the landmarks of stylized tracks. T-186 makes a first cut from
OSM landuse/natural tags within 300 m of the road (`landuse=farmland` + paddy → `paddy`,
`natural=wood`/`landuse=forest` → `forest`, `landuse=residential` / `place=*` → `village`,
`natural=cliff`/gorge → `gorge`, `natural=water`/coast → `river`/`coast`). game-designer
reviews it per route (target: 3–12 zones per 10 km, no zone shorter than 300 m).

- Placement is **deterministic by location**: the random seed of a scenery cell is a hash
  of (route id, cell x, cell z), not of s. On the way back and on the next lap the same
  trees are in the same places (pillar 4).
- Zone transitions are blended over 150 m (mix tables cross-fade), not cut at a line.
- Density per zone — the art-bible table for the set (instances per km of road, by type).
  Visible budget 2000 instances, total for the active cells 40000 (D3D-05 p.4, D3D-08 p.6).
  If a point sees more than 2000 (hairpin stacks see several legs at once), all vegetation
  types in the visible cells thin out evenly, as today.

### 5.3. Landmarks

- Real landmarks of the route are placed at their real position, projected, as stylized
  single meshes (not copies of photos or trademarks). Examples: Tianmen — the cave gate in the
  cliff above the last hairpins, the bend steles; Taroko — the gorge gate arch at the start,
  a red bridge, the Changchun shrine on its waterfall, the Tianxiang pagoda; Yangshuo —
  Moon Hill (karst with a round hole), the stone Yulong bridge, the Big Banyan.
- Between real landmarks, generic ones of the set fill gaps, so that the gap between
  neighboring landmarks along s is ≤ 1.5 km (D3D-08 p.12 rule; `[авто]` proposal for
  catalog routes, data check).
- At most 6 landmark meshes are active at once (section 7, `MeshInstance3D` budget).
  Landmarks are visible from 3 km and are streamed before they appear above the horizon.

### 5.4. Water and terrain

- Rivers: T-186 extracts `waterway=river|stream` lines within 400 m of the route (OSM, ODbL)
  with a water level from the DEM, made monotone downstream. The scene draws a stylized
  ribbon (width from the `width` tag; default 30 m for a river, 6 m for a stream) with the
  set's water colors. Without data in a `river` zone, a procedural ribbon runs 20–60 m from
  the road on the valley side.
- Far terrain: stylized, from the set's relief generator (karst towers, gorge walls,
  terraces), driven by zones. The real DEM is **not** used for the far horizon in phase 1
  (owner question Q2 in section 10).

## 6. Which world a route uses

| Set | For | Status |
|---|---|---|
| `env_karst` — South China karst | Yangshuo, Tianmen, 24-zig, Guilin area | **new** (art-bible) |
| `env_gorge` — subtropical marble gorge and mountain forest | Taroko, Taiwan KOM up to ~2 000 m (above that — alpine zone) | **new** (art-bible) |
| `env_med_island` — Mediterranean limestone island | Sa Calobra | only if the owner picks it: about 70 % reuse of `seaside` and `mountains` assets (umbrella pine, cypress, rock, sea) plus limestone cliffs |
| `env_volcanic` — volcanic island | Teide | only if picked: new lava/pumice palette, Canary pine; not in phase 1 |
| `seaside`, `mountains`, `hills`, `flat` | stylized tracks only | the four existing sets do **not** fit South China or tropical islands (section 2) |

How a set is chosen: by the game-designer, per route, recorded in the route data
(`environment_set`) and in section 9. One route has one set (D3D-11 p.1). Zones give the
variety inside the set. A long route that crosses climates (Taiwan KOM: subtropical gorge →
cloud forest → alpine) uses zones of one set (`env_gorge` has an `alpine` zone with dwarf
bamboo grass and conifers from `ConiferKit`).

`env_karst` and `env_gorge` share the subtropical core (bamboo, banyan, broadleaf evergreen,
stone parapet, masonry wall, red steel bridge, village houses), so the second set costs
about half of the first. A separate "tropical island coast" set (palms, white beach) is not
needed for the recommended routes. It is listed as a future option for Hainan-type routes.

## 7. Chunk streaming from the player's point of view (D3D-11 p.10 (ж), p.13)

What the rider sees:

| Never pops (built before it can be seen) | May appear (fade-in, never a hard pop) |
|---|---|
| road surface, markings, curb, parapets within 1 500 m of the rider, **including other passes** (the next hairpin legs above, the return road) | grass tufts — 450 m, 50 m fade |
| terrain to the camera far plane (3 km): no holes, no visible edge | bushes and small props — 1 000 m, 100 m fade |
| landmarks within 3 km | trees — 1 500 m, 100 m fade (dithered "self" fade of `visibility_range`) |
| water, bridges, galleries within 1 500 m | roadside posts — 700 m (tiny; may pop) |

Structure (proposal for TA, numbers are budgets, not code):

- **Road**: chunks of 400 m of route s (asphalt mesh + roadside mesh = 2 `MeshInstance3D`).
  Active: every chunk whose AABB is within 1 700 m of the rider. Cap 8 chunks. Nearest
  first; a dense hairpin road may hit the cap, because 8 × 400 m covers the visible road).
- **Terrain and scenery**: a world-space grid, not s-ranges. Terrain cells 1 024 m (cap 18
  active), scenery cells 512 m (MultiMesh per type per cell; trees active within 1 700 m).
  Overlapping passes then share cells, and placement is deterministic by location (5.2).
- **Budget split** of `MeshInstance3D` ≤ 60: rider and bike 10, road 16, terrain 18,
  landmarks 6, water 4, bridges and galleries 4 → 58, 2 spare. Materials ≤ 12 (asphalt,
  terrain, world toon, rider toon, water and the existing ones; the new sets add no material,
  colors come from vertex colors).
- **Build ahead**: a chunk or cell is requested when it comes within its visible range
  + 300 m (18 s ahead at 60 km/h). It is released beyond the range + 600 m (hysteresis, no
  thrashing on out-and-back). Generation runs off the main thread. Attaching it to the scene
  takes at most one chunk per frame.
- **Start**: the window around s = 0 is built behind the loading screen before the ride
  starts; the ride never starts with missing road.

`[авто]` proposals:

1. 200 km fixture, simulated ride at 60 km/h, check every 50 m: active road chunks ≤ 8,
   terrain cells ≤ 18, scenery cells ≤ 24 per type. For every route point within 1 500 m of
   the rider (any s), its road chunk is built and visible.
2. At most one chunk/cell is attached per frame. The attach step of the largest chunk is
   ≤ 2 ms on the dev machine (logged).
3. Visible MultiMesh instances ≤ 2000, `MeshInstance3D` ≤ 60 and materials ≤ 12 at every
   50 m (as p.10 (ж)).

`[ручная проверка]` stays as p.13: no hitch when chunks stream in, 60 FPS on the Mac.

## 8. Frames, data rules and proposed criteria

### 8.1. Frame set for p.12

- "climb" fixture: 500 / 1 500 / 1 950 m; "bend" fixture: 900 / 1 000 / 1 100 m (as p.12).
  The fixtures are drawn with `env_karst` once it exists, before that with `hills`.
- Shot with `./scripts/screenshot.sh <dir> 32 90 <distances> <track id>`. T-184 adds a track id
  for fixtures (e.g. `fixture:climb`).
- Before: `shots/2026-10-10-t178/before/` (section 2). After: `shots/<date>-t184/`,
  `shots/<date>-t185/`.
- Per catalog route (after T-186): 5 frames picked by game-designer from the data and listed
  in section 9.4 for each confirmed route — start, a hairpin apex (or the sharpest bend),
  mid-climb, a landmark, the turnaround or the seam. Checklist ≥ 10/12, no blocking items,
  plus "the route is recognizable without a caption" (pillar 2).

### 8.2. Data rules for route preparation (T-186)

1. Elevation from the DEM is sampled every ≤ 10 m. Inside `tunnel=yes` and `bridge=yes`
   ranges it is replaced by linear interpolation between the portals or abutments. The DEM
   gives the mountain top above a tunnel and the valley floor under a bridge.
2. Robust smoothing: a 50 m median filter, then a 100 m triangular filter. The grade change
   between neighboring 10 m points is ≤ 3 % (no "steps"). Exception: real ramps are kept if
   the published max grade says so (Wuling ramps up to 27 %, clamped at 25 % by p.4).
3. Check against known control heights (OSM `ele` on passes and places, published climb
   data): total gain within ±10 % of the published figure, summit within ±15 m. Otherwise
   fix by hand or anchor heights.
4. Overlaps (section 4, "same road"): the later pass takes its heights from the earlier pass
   at the nearest point, so both are equal ±0.05 m.
5. Closed routes: last point = first point (section 4).
6. Route data also carries: `environment_set`, `zones`, `landmarks`, `bridges`, `tunnels`,
   `rivers` (polylines with level), the region (p.1) and the source/license records (p.3).

### 8.3. Numbers of Н-78 (е) — game-designer's position

| Number | Position |
|---|---|
| Road axis within 5 m of the route, 10 m in hairpins | confirm; hairpin = heading change > 120° within 60 m |
| Minimum turn radius 8 m | confirm, measured on the track axis (rider line) |
| Cross-slope ±4 % | confirm; 0 on straights, 4 % in turns R < 200 m, 20 m ramps |
| Axis length = Δs ± 0.5 % per 1 km | **change**: see 3.4 (piecewise mapping, local factor 1 ± 0.05; ±0.5 % only where no turn was widened) |
| Max segment 50 m, L ≥ 1 km, grade clamp ±25 %, closed threshold 50 m, 200 km in 2 s | confirm (Wuling ramps of 27 % get clamped; accepted) |

### 8.4. New fixtures and criteria proposed to requirements

| # | Proposal | Mark |
|---|---|---|
| 1 | "hairpin" fixture: 500 m north, a 180° right turn with raw radius 5 m, 500 m south (legs 10 m apart in data). After the build: min radius ≥ 8 m, axis within 10 m of the route, local factor 1 ± 0.05, no folded faces, camera yaw rate ≤ 150°/s at 60 km/h, rider in frame | `[авто]` |
| 2 | "stack" fixture: 3 hairpin legs at 8 % grade, 25 m apart horizontally. Terrain never above either road within its width; camera-to-rider line not blocked | `[авто]` |
| 3 | "overlap" fixture: 1 km north, the turnaround, 1 km back with the axis 2.8 m to the side. One road surface on the overlap (no coplanar asphalt triangles from two passes); a 0.5–5 m height conflict makes validation fail | `[авто]` |
| 4 | Turnaround on open routes: T_turn = 45 ± 5 m, coordinate held at the end point (change of p.6, Н-78 (г)) | `[авто]` |
| 5 | Closed routes: last point = first point; heading continuous at the seam ±3°, jump ≤ 0.05 m | `[авто]` |
| 6 | Landmarks on catalog routes: gap ≤ 1.5 km along s | `[авто]` |
| 7 | Streaming items 1–3 of section 7; floating origin within 4 km (3.2) | `[авто]` |
| 8 | Frames of the "hairpin" fixture at apex −40 / 0 / +40 m: the road visibly turns back on itself; parapet on the outside; no folds, gaps or trees inside the bend; checklist ≥ 10/12 | `[визуальная проверка]` |
| 9 | Each confirmed route, 5 frames of 9.4: checklist ≥ 10/12, no blocking items; set recognizable without a caption (karst towers / gorge walls / sea in frame) | `[визуальная проверка]` |

## 9. First catalog routes — shortlist for the owner (T-191, Н-80)

Status: **proposed 2026-10-10, waiting for the owner's confirmation** (Н-80). T-186 starts only
from the confirmed list. Figures are from published climb and travel sources. They differ
between sources by 5–15 % and are checked against the data in T-186.

### 9.1. Ranked shortlist

| # | Route | Region | Start → finish | Length | Gain | Grade | Set | Why it is spectacular |
|---|---|---|---|---|---|---|---|---|
| 1 | **Tianmen Mountain, 99 bends** (Tongtian Avenue) | Zhangjiajie, Hunan, China | base of the mountain (~200 m) → Tianmen Cave car park (~1 300 m) | ≈ 10.8–11 km | ≈ 900–1 100 m | avg ≈ 8–10 % | `env_karst` (cliff zone) | 99 hairpins stacked on a cliff under a natural arch in the rock; the sandstone pillar country that inspired Avatar's floating mountains |
| 2 | **Taroko Gorge** (Prov. Hwy 8) | Hualien, Taiwan (island) | Taroko Gate arch (~60 m) → Tianxiang (~480 m) | ≈ 19–20 km | ≈ 400–420 m | avg ≈ 2.2 % | `env_gorge` | the road is cut into marble cliffs hundreds of meters high, with half-tunnels, red bridges and a jade river below; easy grade, so it works for long workouts |
| 3 | **Yangshuo karst loop** (Yulong River, Ten-Mile Gallery, Moon Hill) | Guilin, Guangxi, China | Yangshuo → Yulong Bridge → Ten-Mile Gallery → Moon Hill → Yangshuo, road-only variant | ≈ 20–25 km, **closed loop** | ≈ 50–150 m (estimate) | flat | `env_karst` (paddy, river, village zones) | the "ink painting" landscape: rows of karst towers over rice paddies and a river; flat, so it is the everyday route for plan workouts |
| 4 | **Sa Calobra** (Ma-2141, Coll dels Reis) | Mallorca, Spain (island) | Port de sa Calobra (0 m) → Coll dels Reis (~680 m) | 9.4 km | ≈ 645–700 m | avg ≈ 7 % | `env_med_island` (new, ~70 % reuse) | the most famous cycling climb on an island: 26 hairpins in a limestone canyon and the 270° "tie knot" where the road passes under itself |
| 5 | **Taiwan KOM: Hualien → Wuling** | Hualien–Taichung, Taiwan (island) | Qixingtan coast (0 m) → Wuling pass (3 275 m) | ≈ 105 km | ≈ 3 300 m | avg ≈ 3 %, ramps to 27 % | `env_gorge` + alpine zone | sea level to 3 275 m in one road: the gorge, the cloud forest, then the alpine ridge; contains route 2. A later "epic" extension |
| 6 | **24-zig** (Twenty-Four Bends) | Qinglong, Guizhou, China | foot → top of the bends | ≈ 4 km | ≈ 260–300 m | avg ≈ 7 % | `env_karst` | 24 hairpins stacked on one slope, the iconic WWII supply road; very short (many turnarounds per hour); Guizhou is south-west rather than South China |
| 7 | **Teide** (TF-21) | Tenerife, Spain (island) | Puerto de la Cruz → El Portillo, Teide caldera | ≈ 47 km | ≈ 2 400 m | avg ≈ 5 % | `env_volcanic` (new) | a climb from the Atlantic through pine forest into a lunar lava caldera; needs a whole new set |
| 8 | **Tai Mo Shan** (Route Twisk + Tai Mo Shan Rd) | Hong Kong | Tsuen Wan → summit road end | ≈ 11 km (summit road ≈ 4.8 km) | ≈ 450 m on the summit road | ≈ 9–10 % | `env_gorge` (forest) | the highest climb in Hong Kong above the city; good data, but it looks the least "unreal" of the list |

Considered and dropped: Longji rice terraces (no reliable figures for the road; the terraces
become a zone of `env_karst`); Hainan Wuzhishan (pleasant jungle road but not "unreal");
High Island East Dam, Hong Kong (the hexagonal columns are off the road, cycling access
unclear).

### 9.2. Recommendation: first three

**Tianmen (1) + Taroko (2) + Yangshuo (3).** All three are in South China or on an island
(Taiwan). They need **two new sets**, and these sets share their subtropical core. They give
three different kinds of ride:

- **Yangshuo**: a flat closed loop for plan workouts (ERG, Н-78 (д)), the easiest road for
  the builder (few tight turns). Build it first: it proves the pipeline and `env_karst`.
- **Taroko**: a long gentle climb for endurance and SIM. It proves bridges, galleries
  (tunnels) and the river.
- **Tianmen**: the showpiece hard climb. It proves hairpins, stacks and the turnaround.

Alternative if the owner wants an island outside China: put **Sa Calobra (4)** instead of
Taroko. Its set is cheaper (reuse) and its OSM and DEM data are the best of the list. But it
needs the grade-separated self-crossing (section 4) on day one.

### 9.3. Data, licenses and fit with D3D-11 limits

OSM could not be queried from the design container: openstreetmap.org and the Overpass API
are not reachable from here. Coverage is therefore judged from indirect evidence: routing
services built on OSM (Komoot) route on the road, and the road has published climb data and
recorded rides. T-186 confirms coverage with the queries below. That is step 0 of T-186,
and a route that fails it is dropped.

| # | OSM coverage (evidence) | Reproducible check (Overpass, bbox S,W,N,E approx.) | Elevation source candidates | Fit with D3D-11 / road limits |
|---|---|---|---|---|
| 1 | expected: a single scenic-area road; no Komoot/Strava segment found → **verify first** | `way["highway"](29.02,110.44,29.08,110.52); out geom;` — look for `name~"通天大道"`; check `access=*` tags (the road is closed to private cars, which is fine for us) | Copernicus GLO-30; SRTM GL1 fallback. Steep cliff → DEM error: anchor at known heights (base, cave) | L ≥ 1 km ✓; 99 hairpins → widening to 8 m (3.3), up to ~8 % longer scene path (3.4); grade clamp not hit (avg ~10 %); turnaround at the cave (4) |
| 2 | good: a national highway, many recorded rides; tunnels and bridges tagged | `way["highway"]["ref"~"8"](24.14,121.47,24.20,121.64); out geom;` — continuity Taroko Gate → Tianxiang; check `tunnel=yes`, `bridge=yes` | Copernicus GLO-30; Taiwan MOI 20 m DEM (open government data — verify license); tunnels interpolated (8.2) | L ✓; gentle turns; galleries (3.6); real road closures after the 2024 earthquake do not matter for a virtual ride, but the OSM geometry may have changed (new tunnels) — use the current through-road |
| 3 | good: Komoot routes the Yulong River loops; Ten-Mile Gallery partly a path with steps → use the road variant (G321 / village roads) | `way["highway"~"primary|secondary|tertiary|unclassified|residential"](24.70,110.40,24.82,110.52); out geom;` — then route the loop on roads only | Copernicus GLO-30 (flat valley; the towers do not touch the road) | L ✓; closed loop → seam rule (4); lanes 5.5 m |
| 4 | very good (Spain, OSM dense; Climbfinder, PJAMM) | `way["ref"="Ma-2141"]; out geom;` | Copernicus GLO-30; Spain CNIG MDT05 (CC BY 4.0) | L ✓; 26 hairpins → widening; **self-crossing at the "tie knot" → grade-separated case (4) required** |
| 5 | good (Hwy 8 + 14A) | as 2 plus `way["ref"~"14"](24.05,121.20,24.20,121.50)` | as 2 | 105 km < 200 km ✓; ramps 27 % clamped to 25 % (p.4) |
| 6 | unknown → verify | `way["highway"](25.75,105.15,25.85,105.25); out geom;` near Qinglong county seat | Copernicus GLO-30 | 4 km ✓ but short; 24 hairpins (3.3) |
| 7 | very good | `way["ref"="TF-21"]; out geom;` | Copernicus; CNIG MDT05 | 47 km ✓ |
| 8 | good (Komoot climb exists) | `way["highway"](22.38,114.08,22.42,114.14); out geom;` — `name~"大帽山道|荃錦公路"` | Copernicus; HK Lands Dept DTM (verify license) | L ✓ |

Licenses (D3D-11 p.3, NFR-07 p.4; legal adequacy is the owner's call):

- **OSM, ODbL 1.0.** Route geometry is OSM-derived. The 3D world, the card and the FIT track
  are **Produced Works**: attribution «© OpenStreetMap contributors» with a link to the OSM
  copyright page, on the About/licenses screen and on each OSM-derived route card (p.3). The
  shipped route files (resampled, smoothed geometry plus elevation, zones, rivers) are a
  **Derivative Database**. A single route is under 100 features, which the OSMF "Substantial"
  guideline treats as insubstantial. But a catalog is a systematic extraction, so the
  conservative reading applies: the route database is offered under ODbL 1.0 (publish the
  route files and the preparation script, for example in a public repository linked from
  the licenses screen). This satisfies the share-alike obligation, and the route files hold
  no code or art of ours. The record goes to `docs/publishing/licenses.md` (T-186).
- **Elevation.** SRTM GL1 (USGS) is public domain: no obligations, so it is the
  simplest choice. Copernicus DEM GLO-30 is free worldwide. Modified data carries the
  "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space
  GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights
  reserved" notice plus the licence's no-liability sentence, on the same licenses screen.
  Commercial use and placing the derived heights inside an ODbL database must be confirmed
  against the licence PDF in T-186: the licence text could not be fetched here. Fallback:
  SRTM only. National DEMs (Taiwan MOI, Spain CNIG, HK Lands Dept) are better in gorges but
  need their own license check.
- **China mainland routes (1, 3, 6): flag for the owner.** PRC law restricts surveying and
  the publication of maps of China (maps distributed in China need a review approval
  number). We do not show a map, only a 3D road and a profile; whether a route-shape
  preview on the card (T-179) counts as a map is a legal question. Proposal: for mainland
  routes the card shows the elevation profile only, without the shape. The owner decides
  whether the app is offered in the China storefront at all.
- **Strava.** The uploaded track (STR-06) carries OSM-derived coordinates in the user's own
  activity. Attribution there is not possible. This is the same practice as other virtual
  ride apps. Noted, low risk; owner's call.

### 9.4. Frames per route

Filled after T-186 from the real data (s of start, sharpest hairpin, mid-climb, main
landmark, turnaround or seam).

### 9.5. Owner confirmation

- 2026-10-10: shortlist proposed (T-191). Confirmation: pending (Н-80).

## 10. Questions to the owner

- **Q1 (Н-80).** Confirm the first routes. Recommendation: Tianmen + Taroko + Yangshuo.
  Alternative: swap Taroko for Sa Calobra. Also: do "islands" mean islands in or near China
  (Taiwan, Hong Kong, Hainan), or any islands (Mallorca, Tenerife)?
- **Q2. Far horizon: stylized or real?** (a) Stylized relief from the set (phase 1
  recommendation: cheapest, fits the toon style). (b) Real DEM silhouettes, smoothed, under
  the toon shading: the real Tianmen cliff and the real Taroko walls; about +1 TA task and
  +0.5–1 MB per route. (c) Hybrid: the real DEM shape at 90 m resolution plus procedural
  karst detail. Recommendation: (a) now, (c) after the first route is seen on the Mac.
- **Q3. Two new environment sets** (`env_karst`, `env_gorge`; art-bible). This is new content
  in the same toon style, not a style change. Cost: TA L for the first set, M for the
  second. Confirm.
- **Q4. Turnaround at the end of an open route**: a turning circle with a 45 m coordinate
  hold (section 4) instead of the instant reversal of p.6 (Н-78 (г)).
- **Q5.** China storefront and the mainland route-shape preview (9.3).
