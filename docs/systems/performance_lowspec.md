# Low-spec pass (round three): getting playable on integrated Intel graphics

Target hardware, confirmed: **Dell Latitude 5411, integrated Intel graphics
only, no discrete GPU.** Reported frame rate before this pass: **~5-6 fps**,
after rounds one and two of cuts (`docs/systems/performance_notes.md`).

This document records what round three changed, what each change is expected
to buy and why, and — separately and explicitly — **what was and was not
actually verified**, because those are two different lists.

---

## 0. What the integration agent needs to apply (scene/asset-level)

None of the following are in this pass's file scope. They are listed first
because the first item is probably worth more than anything else in this
document.

### 0.1 Terrain textures ship with NO MIPMAPS and NO VRAM compression — fix this first

`assets/textures/terrain/{grass,rock,sand}/*.import` all contain:

```
compress/mode=0          # Lossless — i.e. uncompressed RGBA8 in VRAM
mipmaps/generate=false   # No mip chain at all
```

Nine 1024x1024 textures, uncompressed, with no mip chain, sampled by the
single heaviest shader in the project across an island that fills the middle
of every god-view frame. Consequences, in order of severity:

1. **Every minified fetch is a texture-cache miss.** Without mips, a fragment
   covering several metres of terrain samples one arbitrary texel out of a
   1 K texture, and the neighbouring fragment samples a texel far away in
   memory. This is close to the worst possible access pattern for a GPU that
   shares system memory bandwidth with the CPU.
2. **~37 MB of VRAM** for these nine textures (1024·1024·4·9) instead of the
   ~6 MB a mipmapped BC-compressed set would take, on a GPU with no dedicated
   VRAM at all.
3. **It is also a visible bug, not only a cost.** The heavy speckled noise
   over the island in every god-view render of this scene is textbook
   no-mipmap minification aliasing.

Recommended change to all nine `.import` files, then reimport:

```
compress/mode=2          # VRAM Compressed
mipmaps/generate=true
```

```
# apply + reimport
sed -i 's/^compress\/mode=0$/compress\/mode=2/; s/^mipmaps\/generate=false$/mipmaps\/generate=true/' \
  assets/textures/terrain/*/*.import
godot --headless --path . --import
```

Not done here because `assets/` is outside this pass's scope. It is the
single highest-value item on this page.

### 0.2 `world/god_view.tscn`

| Node | Property | Now | Recommended | Why |
|---|---|---|---|---|
| `OceanSurface` | `subdivisions` | 160 | **64** | 800 m plane at 160 subdivisions is 25,921 vertices each running a six-wave Gerstner sum. `ocean_surface.gd` already *caps* this to 64 on the low-spec path, so this is cosmetic honesty rather than a functional change — but the scene should say what it actually gets. |
| `Sun` (`DirectionalLight3D`) | `directional_shadow_mode` | unset (= `SHADOW_PARALLEL_4_SPLITS`) | **`SHADOW_ORTHOGONAL` (0)** | Four parallel splits means the entire shadow-casting scene is re-rendered **four times per frame**. One split is enough for a god-view camera that never gets close to the ground. `environment/graphics_preset.gd` already forces this at runtime, but setting it in the scene means frame 1 is cheap too. |
| new child | instance `environment/graphics_preset.tscn` | — | **add it** | Nothing in this pass is wired into a scene. Without this node the project runs at whatever the checked-in `.tres`/`project.godot` values are — which *are* the LOW values, so it is not broken without it, but the preset can then never be changed at runtime. |
| — | runtime key | — | bind one key to `GraphicsPreset.cycle()` | LOW -> MEDIUM -> HIGH -> LOW. `cycle()` returns the new preset int; `GraphicsPreset.preset_name(i)` gives "Low"/"Medium"/"High" for a debug label. |

Deliberately **not** recommended: reducing `Island.resolution` (161) or
`VILLAGERS_PER_VILLAGE` (5, i.e. 15 villagers total). The island mesh is
~51 K triangles and the villagers are 15 small meshes; neither is close to
being the bottleneck on a fragment-bound, bandwidth-bound integrated GPU,
and cutting them would cost real content for a saving that is probably not
measurable. Rounds one and two named "draw distance and crowd counts" as a
last-resort lever — it still is, and this pass still did not need it.

### 0.3 Two things found while investigating that are somebody else's to fix

- **The island renders almost black.** Verified pre-existing: rendering
  `world/god_view.tscn` with the *original*, unmodified triplanar shader
  produces a pixel-for-pixel equally dark island, so it is not caused by
  anything in this pass. Combined with the mean albedo of the source
  textures (grass is a mid olive, sRGB 96/109/48), the island should read
  olive-green, not near-black. Leading suspects, in order: the terrain's
  vertex normals (if they face downward, `n.y < 0` makes the shader's slope
  mask pick *rock* everywhere and direct sun contributes nothing, leaving
  ambient-only lighting), then the no-mipmap aliasing in §0.1. Owner:
  `world/terrain/` (package B) with `world/god_view.tscn`.
- **`docs/rendering.md`'s screenshot command silently uses the wrong
  renderer.** It says to run `godot --rendering-driver vulkan`. Verified
  by running it: passing `--rendering-driver` explicitly makes Godot 4.3
  re-derive the rendering *method* and it comes up **Forward+** even though
  `project.godot` now says `mobile`. Dropping the flag (Vulkan is the
  default anyway) gives "Forward Mobile" correctly. Any screenshot taken
  with the documented command is not a picture of what ships.

---

## 1. What was actually verified, and how

This sandbox has **no GPU**. It does, however, have Mesa's `lavapipe`
software Vulkan implementation, which is a real, spec-complete Vulkan
driver — so while **no frame time here means anything at all**, it *can*
answer correctness questions that previous rounds had to guess at.

Verified by actually running it
(`VK_ICD_FILENAMES=…/lvp_icd.json xvfb-run -a godot --path . …`):

- ✅ **The Mobile renderer initialises and renders this project.** Banner:
  `Vulkan 1.4.318 - Forward Mobile`. `world/god_view.tscn` was rendered to a
  PNG under it. It is not a black screen.
- ✅ **Every shader in the shipping scene compiles under Mobile**, with zero
  shader errors in the log: the ocean (both quality variants), the triplanar
  terrain, the Reach border ring, the Hand, and the Naklon-reactive material
  shader.
- ✅ **`hint_screen_texture` and `hint_depth_texture` DO work on the Mobile
  renderer** — the high-quality ocean variant, which declares both, compiled
  and rendered with no error. This retires round two's stated worry directly.
  (The path is still off by default: it *works*, it is just expensive.)
- ✅ **The runtime-generated high-quality ocean shader compiles**, including
  its `#include` of `gerstner_common.gdshaderinc` and the injected `#define`.
- ✅ **`GraphicsPreset` applies LOW, MEDIUM and HIGH with no runtime errors**,
  and cycles back. Every `RenderingServer` call, `Sky` constant and
  `Viewport` constant it uses is real.
- ✅ **The rewritten triplanar terrain shader is visually identical to the
  original.** A/B: same scene, same camera, original shader vs. rewritten
  shader — the two PNGs are indistinguishable.
- ✅ **The rewritten ocean shoreline is visually close to the depth-buffer
  version it replaces.** A/B: the shallow-water band follows the real,
  irregular coastline in both. (An earlier attempt at this, an analytic
  circular coast ring, was *rejected on the evidence* — it put a bright
  white foam ring in open water 40 m offshore. That is why the shipped
  solution bakes real terrain depth instead. See §3.2.)
- ✅ `godot --headless --path . --check-only --quit-after 3` is clean.

**Not verified, and cannot be from here:**

- ❌ **Any frame rate, frame time, or speedup figure.** There is no GPU.
  Every "expected win" below is an argument from what the work *is*, not a
  measurement. This document does not contain a single performance number
  presented as measured, because there are none.
- ❌ **That the Mobile renderer is faster than Forward+ on this specific
  Intel part.** Software rasterisation says nothing about that.
- ❌ **Intel Vulkan driver behaviour.** lavapipe compiled every shader; a
  particular Intel driver could still differ. This is the residual risk on
  the renderer switch, and §2.1 gives the one-line revert.

---

## 2. Changes, in expected order of value

### 2.1 `scaling_3d/mode`: FSR2 -> bilinear (`project.godot`)

**Probably the single biggest win in this pass, and it is zero-risk.**

The project was running `scaling_3d/mode=2`, which is **FSR 2.2** — Godot's
own project-setting hint for that enum literally reads
`Bilinear (Fastest), FSR 1.0 (Fast), FSR 2.2 (Slow)`. FSR2 is a temporal
upscaler: per frame it wants motion vectors, then runs a chain of passes
(depth clip, previous-depth reconstruction, lock, luminance pyramid,
reactive-mask autogen, accumulate, RCAS sharpen — the engine ships a
separate compute shader for each, visible in the binary as
`Fsr2DepthClipPassShaderRD`, `Fsr2LockPassShaderRD`,
`Fsr2AccumulatePassShaderRD`, `Fsr2RcasPassShaderRD`, …), most of them at
**output** resolution, plus a full-resolution history buffer.

The scene was being rendered at 0.5 scale (960x540) specifically to save
work — and then handed to an upscaler whose own cost is a function of the
1920x1080 output, not of the cheap 960x540 input. On a GPU with a handful of
execution units and no dedicated memory, it is entirely plausible that FSR2
cost more than the scene it was upscaling.

Now `scaling_3d/mode=0` (bilinear): one stretched blit. `scaling_3d/scale`
stays at 0.5. FXAA stays on because at half resolution the edges need
something and FXAA is one cheap full-screen pass.

Related: `use_taa` was `true` and was **silently doing nothing**, because the
engine disables TAA internally whenever FSR2 is active ("FSR 2 is not
compatible with TAA. Disabling TAA internally."). With FSR2 gone it would
have quietly switched itself on — motion vectors plus a full-resolution
history resolve. Explicitly set to `false`.

### 2.2 The ocean stops being a transparent surface (`world/ocean/ocean.gdshader`)

The shader ended with `ALPHA = 1.0;`. In Godot 4, *writing* `ALPHA` at all is
what flags a spatial shader as alpha-using, which puts the surface in the
**transparent render list**: no depth prepass, no early-Z rejection,
back-to-front sorting, and (on Forward+) membership in the pass that needs
the screen copy.

This is an **800 m x 800 m plane that fills most of a god-view frame**, and
it was never actually see-through — the alpha was a hard-coded 1.0. It was
paying the entire transparent-pass tax for nothing.

`ALPHA` is no longer written and `blend_mix` was dropped from `render_mode`.
The ocean is now an ordinary opaque surface: it writes depth, it gets
early-Z, and — with `driver/depth_prepass/enable=true` — it occludes the sea
floor and everything else behind it *before* their fragment shaders run.

### 2.3 The ocean no longer requests a screen copy or a depth copy

`ocean.gdshader` declared:

```glsl
uniform sampler2D depth_texture  : hint_depth_texture, …;
uniform sampler2D screen_texture : hint_screen_texture, …;
```

Godot decides whether to perform a full-render-resolution back-buffer copy
and a depth-buffer copy by inspecting whether the compiled shader
**declares** those samplers. A runtime `uniform bool` around the sampling
would not have helped — the copies happen regardless of the branch. So the
switch had to be **compile-time**, and it is: the samplers, and the code that
uses them, live inside `#ifdef OCEAN_HIGH_QUALITY`.

As checked in, the file compiles *without* that symbol. Loading
`ocean.gdshader` as a resource — which is what any `.tscn` material
reference does — always gets the cheap path. `OceanSurface` defines the
symbol, by reading the shader source and injecting `#define
OCEAN_HIGH_QUALITY` after the `shader_type` line, only when
`high_quality_water` is true. If that read ever fails it falls back to the
plain cheap shader with a warning: worst case is low-spec water on a
high-spec machine, never a broken material.

What the copies cost, reasoned rather than measured: at 0.5 scale the colour
copy is a 960x540 RGBA16F blit (~4 MB read + 4 MB write) plus a depth copy,
every frame, on hardware whose memory bandwidth is shared with the CPU — and
critically, a mid-frame copy **breaks the render pass**, forcing a flush of
whatever the GPU had in flight. That structural cost is usually worse than
the bytes.

### 2.4 Terrain triplanar: 27 texture fetches per fragment -> typically 3

`terrain_triplanar.gdshader` unconditionally did **3 triplanar axes x 3
material sets (grass/rock/sand) x 3 maps (albedo/normal/roughness) = 27
anisotropically-filtered texture fetches per fragment**, over the island that
occupies the middle of every frame. Every one of those 27 was fetched even
when its blend weight was exactly zero, which is the common case twice over:

- **Axis weights** are `pow(abs(normal), 4)` renormalised. On ground flatter
  than ~40° the xz-plane axis carries >0.95 of the weight and the other two
  are numerically irrelevant. Two of three axes are wasted on most of a
  heightfield island.
- **Material weights** are mutually exclusive except in the narrow crossover
  bands. Open grassland has `rock_amount == 0.0` and `beach == 0.0`
  *exactly* — and was still sampling six rock and sand textures.

Both are now skipped with real branches, so flat grass costs 3 fetches
instead of 27. Worst case (a steep, beach-height cliff face where all three
axes and two material sets genuinely contribute) is the original 18-27, so
this is never slower than before.

Correctness detail: sampling inside non-uniform control flow makes the
implicit screen-space derivatives that select the mip level undefined in
GLSL, which can show as mip seams along branch boundaries. So the
derivatives are computed **once, up front, in uniform control flow**
(`dFdx`/`dFdy` of the world position) and handed to `textureGrad`
explicitly — about six extra ALU ops to make the branches correct by
construction rather than by luck. Verified: the rewritten shader is
visually indistinguishable from the original.

Filtering also changed from `filter_linear_mipmap_anisotropic` to
`filter_linear_mipmap`, and `textures/default_filters/anisotropic_filtering_level`
is now `0` project-wide. Anisotropy multiplies the texels a single fetch
touches (up to 16x) precisely at the grazing angles a god-view camera looks
at terrain from. Distant terrain gets blurrier; that is the trade. **Note
that this only really pays off together with §0.1** — anisotropic filtering
of a texture that has no mipmaps was largely wasted effort anyway.

### 2.5 Renderer method: `forward_plus` -> `mobile` (`project.godot`)

Round two deferred this over "custom shader compatibility this sandbox has
no way to verify". This round actually investigated it, two ways.

**Static inspection of the engine binary** (the same method
`performance_notes.md` used to verify property names) for every
"only available when using the Forward+ …" diagnostic string. The complete
list of *shader* features Godot 4.3 gates to Forward+ is:

- subsurface scattering,
- light transmittance,
- `hint_normal_roughness_texture`.

**No shader in this repository uses any of them.** Notably there is *no*
such gate for `hint_screen_texture` or `hint_depth_texture` — the exact
worry round two named. The Forward+-only *project* features that were in use
are FSR1/FSR2 and TAA, all three of which this pass was removing anyway for
cost reasons (§2.1).

**Then it was run.** Under lavapipe the project comes up as
`Forward Mobile`, every shader compiles, and `world/god_view.tscn` renders
(§1). The remaining unknown is whether a real Intel Vulkan driver agrees —
which is exactly the kind of thing that cannot be settled from here.

Why it should help: Mobile is a single-pass forward renderer with no
clustered light-culling compute pass, fewer and smaller intermediate render
targets, and reduced-precision math. Everything this project loses by moving
to it (SDFGI, volumetric fog, SSAO/SSIL/SSR) was **already disabled** in
round two, so the switch costs nothing that was still turned on.

> **Revert, if it comes up wrong on the real machine:** set
> `renderer/rendering_method="forward_plus"` and
> `config/features=PackedStringArray("4.3", "Forward Plus")` in
> `project.godot`. That is the whole revert; it is called out in a comment
> at the top of the `[rendering]` block too. Everything else in this pass is
> a quality knob that can make the game uglier but cannot stop it rendering.

### 2.6 The graphics preset system (`environment/graphics_preset.gd`)

A small, non-autoload, instantiable `Node` following
`environment/naklon_environment_driver.gd`'s established pattern exactly:
tiny, idempotent `_ready()`, no required scene wiring, no exported
`NodePath`s, mutating the shared `world_environment.tres` in place (which
works because `ResourceLoader` caches by path, so `load()` returns the same
live instance the `WorldEnvironment` node already points at).

```gdscript
apply(preset)        # 0 = LOW, 1 = MEDIUM, 2 = HIGH. Idempotent.
apply_current()
cycle()              # LOW -> MEDIUM -> HIGH -> LOW; returns the new preset
current()
GraphicsPreset.preset_name(i)   # "Low" / "Medium" / "High"
preset_applied(preset)          # signal
```

**Defaults to LOW.** The checked-in values in `project.godot` and
`world_environment.tres` deliberately *match* LOW, so a machine booting
straight into LOW never renders a single frame of the expensive
configuration before the preset node runs.

| Knob | LOW | MEDIUM | HIGH |
|---|---|---|---|
| SDFGI / volumetric fog / SSAO / SSIL / SSR | off | off | on (Forward+ only) |
| Glow | off | on | on |
| Flat depth fog | on | on | on |
| Sky radiance | 128px, incremental | 128px, incremental | 256px, realtime |
| 3D scale / upscaler | 0.5 bilinear | 0.75 bilinear | 1.0, FSR2 on Forward+ |
| MSAA / FXAA / TAA / debanding | none / FXAA / off / off | none / FXAA / off / off | 2x / off / off / on |
| Directional shadow atlas | 1024, 16-bit | 2048 | 4096 |
| Shadow filter | hard | soft low | soft high |
| Directional shadow splits | 1 | 2 | 4 |
| Mesh LOD threshold | 4.0 | 2.0 | 1.0 |
| Ocean | cheap path | cheap path | screen refraction + depth fade |

Two details worth knowing:

- **HIGH does not ask for SDFGI/fog/SSAO/SSIL/SSR on the Mobile renderer.**
  The engine refuses them there and logs a warning *per property, per apply*.
  Verified by running it and reading the five warnings, then gating them.
- **`OS.get_current_rendering_method()` is not bound to GDScript in Godot
  4.3** (verified: calling it is a parse error). The preset reads the
  project setting instead, through a `has_method` probe so it will
  automatically use the real thing on 4.4+ where it *is* bound.

### 2.7 Ocean mesh: 25,921 vertices -> 4,225, six waves -> four, and no shadow casting

All in `world/ocean/ocean_surface.gd`, all on the low-spec path only:

- **`low_spec_subdivisions = 64`** caps whatever the scene asks for (160 in
  `god_view.tscn`). 800 m / 64 = 12.5 m per quad.
- **`low_spec_wave_count = 4`** sends only the four longest waves to the GPU.
  At 12.5 m per quad the mesh **cannot represent** the 5 m and 2.4 m
  wind-chop waves in `GerstnerWaveSet.default_ocean()` at all; paying for
  them in the vertex shader bought nothing but aliasing. The CPU-side
  `get_height()`/`sample_surface()` buoyancy queries deliberately still use
  the **full** set, so physics is unchanged; the two now disagree by the
  dropped waves' combined amplitude, which is under 20 cm.
- **`cast_water_shadows = false`.** A flat sheet at sea level lit from above
  casts its shadow onto a sea floor nobody sees — and every shadow split
  re-ran the whole six-wave Gerstner vertex program over the whole mesh. With
  the default four splits that was four extra full passes over 25,921
  vertices per frame, for an invisible result.

### 2.8 Smaller things

- **Occlusion culling off.** There is not one `OccluderInstance3D` in the
  project, so it had nothing to occlude with and was paying for the
  software-rasteriser setup every frame regardless.
- **Sky radiance: 128px, `PROCESS_MODE_INCREMENTAL`** (in
  `world_environment.tres`). The sky cubemap is the only ambient fill light
  in the scene (`ambient_light_source = 2`, SDFGI off) and is what the very
  smooth ocean reflects. Refiltering it every frame is pointless for a sky
  that only moves when Naklon or the weather moves it; incremental spreads
  each refresh over several frames instead.
- **Glow off at LOW** (`glow_enabled = false` in the `.tres`). It is a
  mip-chain of downsample/blur/upsample passes over the whole 3D buffer,
  every frame. The art-direction pass's glow *values* are left in the file
  untouched — only the enable flag moved, and MEDIUM turns it back on.
- **16-bit directional shadow atlas, 1024 positional shadow atlas.** Halved
  bandwidth on every shadow write and read; and no positional light in this
  project casts shadows, yet the default 4096x4096 positional atlas was
  being allocated anyway.
- **A real bug fixed in `ocean.gdshader`:** the distance-based detail fade
  computed `length(VERTEX - CAMERA_POSITION_WORLD)`, mixing a **view**-space
  `VERTEX` (which is what a spatial shader's fragment stage always gets,
  regardless of `world_vertex_coords` — that only affects the vertex stage)
  with a **world**-space camera position. That expression was not a distance
  to anything. In view space the camera is at the origin, so it is now
  `length(VERTEX)`.

---

## 3. Two judgement calls worth arguing with

### 3.1 "AAA visuals" versus this laptop

The brief asks for a AAA visual ceiling. This hardware cannot render one.
Rather than silently picking a side, the preset system makes the choice
explicit: **LOW is the default and is tuned for the Latitude; HIGH restores
the entire stack the earlier passes built** (SDFGI, volumetric fog,
SSAO/SSIL, glow, four soft shadow splits, full resolution, FSR2, screen-space
water refraction) for hardware that can run it. The AAA path is not deleted,
it is behind a preset — and on the Mobile renderer HIGH honestly cannot
restore the Forward+-only parts, which the code states rather than pretends.

### 3.2 The cheap shoreline: an analytic ring was tried and rejected on the evidence

Removing the depth-texture read means the water no longer knows how far
below it the sea floor is — which is what drove both the shallow-water
colour band and the shoreline foam.

The first attempt was a purely analytic approximation: treat the coast as a
circle, and derive shallow/deep from horizontal distance to its centre. One
`length()` per fragment, no reads. Rendering it showed exactly why that was
wrong: the real coastline is irregular, so a circle put a **bright white
foam ring floating in open water roughly 40 m offshore**. Cheap, and worse
than what it replaced.

What shipped instead: **bake the answer once, on the CPU, at mesh build
time.** `OceanSurface` finds the terrain (duck-typed on
`sample_height(Vector2) -> float`, so `world/ocean/` keeps no hard
dependency on `world/terrain/`), queries the sea-floor height under every
ocean vertex, and writes the normalised depth into the mesh's vertex
colours. The fragment stage then reads the interpolated `COLOR.r` it was
going to interpolate anyway and runs *the same arithmetic the depth-buffer
path runs*. Per-fragment cost of the entire shoreline: one multiply.

Cost of the bake: 65 x 65 = 4,225 terrain height queries, **once**, at
startup. Nothing per frame. A mesh with no baked colours (a bare
`PlaneMesh`, or a scene with no terrain) gets white vertex colours, which
reads as "deep everywhere" — no shore band, no artifact.

Honest limitations, both consequences of it being baked:

- **It is static.** Real depth-buffer foam curls around anything the depth
  pass drew — a boat, a villager the Hand dropped in the surf. This only
  knows about the terrain, as it stood when the ocean was built. If dynamic
  object foam ever matters, that is the HIGH path's job.
- **Its resolution is the ocean mesh's vertex spacing** (12.5 m per quad at
  LOW), so the shore band is a soft ~10 m gradient rather than a crisp
  waterline. Fine at god-view altitude; it would not be at a beach-level
  camera.

Verified: the resulting shallow-water band follows the real, irregular
coastline, closely matching the depth-buffer version it replaces.

---

## 4. Scoped out — deliberately not done

- **No measured numbers, anywhere.** No GPU. Stated once per claim above
  rather than buried here.
- **`world/ocean/river.gdshader` was not touched.** It still declares
  `hint_screen_texture` and `hint_depth_texture` and therefore still costs a
  screen copy and a depth copy wherever it is used. It is outside this
  pass's scope, and — checked — it is **not used in `world/god_view.tscn`**;
  only `world/ocean/ocean_demo.tscn` instances a `RiverSurface`. So it costs
  the shipping scene nothing today. If a river is ever added to the main
  scene, it needs the same `#ifdef` treatment `ocean.gdshader` just got, and
  `river_surface.gd` needs the same `high_quality_water` toggle.
- **Villager count, island resolution, draw distance untouched.** See §0.2
  for why.
- **Variable Rate Shading** (`rendering/vrs/mode`) not attempted. Intel Xe
  and later support it and it could be a real win on a fragment-bound scene,
  but it needs an authored VRS density texture and there is no way to
  evaluate the visual cost of a shading-rate map without a GPU.
- **`rendering/shading/overrides/force_vertex_shading`** not enabled. It is a
  genuinely large win (per-vertex instead of per-pixel lighting) and a
  genuinely large visual downgrade. Named here as the next lever if
  everything above still is not enough, rather than applied unasked.
- **No LOD meshes.** All the geometry in this project is generated at
  runtime as `ArrayMesh`es, which have no automatic LOD (Godot only
  generates LODs at import time for imported meshes), so
  `mesh_lod_threshold` currently has nothing to act on. Raising it in the
  LOW preset is free and forward-looking, not an active saving.
- **No per-frame quality adaptation.** No dynamic-resolution or
  frame-time-driven auto-downgrade. That needs a real frame-time signal to
  tune against, which does not exist here.
- **`world/god_view.tscn` / `world/god_view.gd` untouched** — owned by
  another pass this round. Everything needing them is in §0.2.

---

## 5. Per-frame cost this pass ADDS

Close to nothing, and worth stating precisely:

- **`GraphicsPreset` does no per-frame work at all.** No `_process`, no
  `_physics_process`, no polling, no signal subscriptions. It writes a few
  dozen properties when `apply()` is called and is otherwise completely
  inert.
- **`OceanSurface`'s shore bake is startup-only** — 4,225 terrain height
  queries once, in a deferred call, then never again. Nothing was added to
  its `_process`, which still only accumulates elapsed time as before.
- **In the shaders, the only added per-fragment arithmetic is in the
  terrain**: six `dFdx`/`dFdy` components and two `step`/normalise pairs,
  spent to remove up to 24 texture fetches. The trade is roughly ten ALU ops
  against two dozen memory round-trips, which is not a close call on a
  bandwidth-bound part.
- The ocean's cheap shoreline **removes** per-fragment work (a texture fetch,
  a depth linearisation and a matrix multiply become one multiply against an
  already-interpolated varying).

---

## 6. Files changed by this pass

| File | Change |
|---|---|
| `project.godot` | Mobile renderer; FSR2 -> bilinear; TAA off; occlusion culling off; anisotropy off; 16-bit shadows; smaller positional shadow atlas; explicit depth prepass |
| `environment/world_environment.tres` | Glow off (LOW default); SSR explicitly off; sky 128px + incremental |
| `environment/graphics_preset.gd` (new) | LOW/MEDIUM/HIGH preset system |
| `environment/graphics_preset.tscn` (new) | One-node wrapper, matching the other `environment/` drivers |
| `world/ocean/ocean.gdshader` | Opaque instead of transparent; screen/depth reads behind `#ifdef`; baked-depth cheap shoreline; fewer fbm octaves at LOW; view-space distance bug fixed |
| `world/ocean/ocean_surface.gd` | Quality toggle + runtime `#define` codegen; subdivision cap; wave-count cap; shadow casting off; CPU shore-mask bake; group registration |
| `world/terrain/terrain_triplanar.gdshader` | Weight-culled triplanar sampling with explicit `textureGrad` gradients; anisotropy -> trilinear |
| `docs/systems/performance_lowspec.md` (new) | This file |
