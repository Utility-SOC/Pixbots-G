# PIXBOTS-G: THE AAA VISION & MASTER PERFORMANCE ROADMAP

> **Document Status:** Comprehensive Technical & Strategic Analysis  
> **Target Architecture:** Pixbots-G (Godot 4.6 + Rust GDExtension)  
> **Long-Term Horizon:** 2D Tabletop Miniature -> 3D Tactical Fighting Mecha (MechWarrior / Armored Core Style)  
> **Created:** August 2026

---

## 1. Executive Summary & Vision Statement

What separates an ambitious indie simulation from a game that **feels AAA** (such as *No Man's Sky*, *Hades*, *Risk of Rain 2*, or *Armored Core VI*) is **not** a $100M budget or photorealistic textures.

**"Feels AAA" is defined by five perceptual attributes:**
1. **Frictionless Cohesion:** Zero "developer seams", seamless screen transitions, unified typography, and zero unstyled text or debug popups.
2. **Audio-Visual Tactility ("Juice"):** Every action—firing a laser, snapping a hex tile into a torso grid, or destroying an enemy chassis—leaves physical weight in the world (screen recoil, directional impact flashes, bass-heavy audio response, particle sparks, shell debris).
3. **Atmospheric Lighting & World Framing:** Lighting that binds entities to the world, dynamic bloom, volumetric particles, and environmental depth of field.
4. **Diegetic UI & Responsive Micro-Animations:** Interfaces that feel like high-tech military operating systems or physical hardware rather than software drop-downs.
5. **Pervasive Physicality:** Heavy, momentum-driven combat physics where hits freeze time for micro-seconds, armor chips off, and lasers burn environmental scars into the ground.

Currently, **Pixbots-G** possesses **exceptional mechanical depth**:
* A native **Rust GDExtension core** (`rust_ext.dll`).
* A procedural hex-grid energy routing engine with traversal-step phase merging.
* An evolving genetic/neural AI Director (`SquadDirector.gd`, `BossEvolution.gd`).
* Complex late-game progression (Overclocking prestige, Chip Splicing).
* Async PvP Champion Card steganography.

**However, there is a distinct gap between Pixbots-G's deep mechanics and a "Feels AAA" presentation, alongside performance challenges when all complex systems run simultaneously at scale.** This document provides the complete roadmap to bridge that gap in both the current 2D engine and the future 3D MechWarrior-style vision.

---

## 2. The 5 Pillars of "Feels AAA" (2D Era)

```
+-----------------------------------------------------------------------------------+
|                                 THE "FEELS AAA" GAP                               |
+--------------------------+--------------------------+-----------------------------+
| 1. AUDIO TACTILITY       | 2. LIGHTING & DIORAMA    | 3. CAMERA & "JUICE"         |
| • Multi-layer gunshots   | • Tabletop framing       | • Hitstop / frame-freeze    |
| • Tactile UI micro-clicks| • WorldEnvironment Bloom | • Camera kick & directional |
| • Dynamic audio ducking  | • Real-time 2D lights    |   velocity lead             |
+--------------------------+--------------------------+-----------------------------+
| 4. DIEGETIC UI / UX      | 5. CINEMATIC LOOP & HUB  |                             |
| • Frictionless transitions| • Drop-pod deployment   |                             |
| • Glowing plasma conduits| • Paint/decal garage     |                             |
| • Custom typography      | • Hobby shop diorama hub |                             |
+--------------------------+--------------------------+-----------------------------+
```

### Pillar I: Audio Tactility & Dynamic Soundscape (The 50% Rule)
*AAA games invest half of their emotional impact into sound design.*
* **Multi-Layered Impact Design:** Every weapon firing sound should combine four discrete frequency layers:
  1. *Mechanical Transient:* High-frequency metal bolt/breech snap (`0-15ms`).
  2. *Punch:* Mid-range explosive energy impulse (`15-100ms`).
  3. *Sub-Bass Thump:* Heavy low-end frequency (`20Hz - 60Hz`) that provides physical weight.
  4. *Environmental Tail:* Reverb/echo decaying across open terrain or indoors.
* **Tactile Mechanical UI Audio:** Snapping a hex tile into the component grid should produce a heavy neodymium magnet lock sound (`clack-crunch`). Rotating a tile should emit a crisp mechanical gear click.
* **Dynamic Audio Ducking (Sidechaining):** When an Accumulator dumps 150,000 magnitude energy or a Boss detonates, background music and ambient sounds should duck by `-6dB` to `-12dB` for 150ms to emphasize the impact.
* **Diegetic Radio Chatter:** Rival taunts (*Arthur*, *Leo & Luna*) should feature pitch-shifted radio static garble or metallic vocal synthesis cues accompanying dialogue text boxes.

### Pillar II: Visual Polish, Lighting, & Tabletop Art Direction
Currently, mechs render as sleek 2D procedural shapes (`MechRenderer.gd`), but combat occurs on a relatively flat 2D tilemap.
* **Tabletop Diorama Framing (Embracing Lore):**
  * Pixbots-G's lore establishes combat as a **20mm tabletop miniature game on Frank's hobby shop mat**.
  * Elevate this fantasy by applying a **tilt-shift depth-of-field blur shader** to top/bottom screen edges, soft overhead desk-lamp lighting, subtle corner vignettes, and tabletop margins displaying measuring tapes, dice, or coffee mugs outside the 4x8ft boundary.
* **HDR Bloom & Real-Time 2D Lighting:**
  * Add a `WorldEnvironment` node with **Glow / HDR Bloom** enabled (`threshold: 1.0`, `exposure: 1.2`).
  * Attach `PointLight2D` nodes to energy packets, laser beams, thumping thrusters, and exploding husks. As energy conduits route in the Garage or a Lance Beam fires across the battlefield, neon colors will cast real-time light and shadows.
* **Particle Density & Micro-VFX:**
  * Heat refraction shaders around flamethrowers and vortex wells.
  * Directional armor plating debris and metallic shell casings bouncing off the floor.
  * Scorched earth decals left on the map after heavy plasma impacts.

### Pillar III: Game Feel ("Juice"), Recoil, & Camera Motion
* **Impact Hitstop (Frame Freeze):** Pause execution for `2 to 4 frames` (`0.03s - 0.06s`) on massive critical hits, Piercing executes, or boss explosions via `Engine.time_scale = 0.05`.
* **Dynamic Recoil & Camera Kick:** Firing capital mounts (e.g., Lance Beams or 3-Hex Orbiting Arrays) should kick the camera backward along the vector opposite to the firing trajectory.
* **Velocity Lead & Dynamic Zoom:**
  * *Velocity Lead:* Smoothly offset the camera target ahead of the player's movement and aiming vector.
  * *Dynamic Zoom:* Zoom out during multi-squad engagements or Boss fights to reveal tactical scale, then pull in tight when inspecting mechs in the Garage.

### Pillar IV: Diegetic UI Architecture & Micro-Animations
* **Cohesive Sci-Fi Typography:** Replace default Godot fonts with clean font pairings (e.g., *Rajdhani* for headers, *JetBrains Mono* / *Inter* for grid telemetry).
* **Animated Panel Transitions:** Replace instantaneous UI visibility toggles with smooth `Tween` interpolations (`TRANS_CUBIC`, `EASE_OUT`) for slide-ins, fades, and scale-ups.
* **Animated Energy Conduits:** Show glowing plasma energy packets physically sliding down hex conduits in real-time within the Garage UI, pulsing brighter as packet magnitude scales up.

### Pillar V: Metagame Loop & Immersion Framing
* **Hangar-to-Battlefield Transition:** Replace abrupt scene switching with a drop-pod impact transition landing onto the tabletop map.
* **Frank's Hobby Shop Meta-Hub:** Transform the main menu into an interactive tabletop room interface featuring plastic sleeve displays for Champion Cards, trophy shelves, and a glass display case for the Black Market.
* **Visual Mech Customization:** Add shader parameters for custom paint finishes (metallic, carbon fiber, matte finish) and sponsor decal stencils on mech limbs.

---

## 3. Comprehensive Codebase Performance Audit (2D Engine)

An analysis of the codebase (`scripts/core/`, `scripts/entities/`, `scripts/ai/`, `rust_ext/src/`, `FpsCounter.gd`, `Status.md`) reveals the primary bottlenecks when all complex systems run simultaneously in intense combat (e.g., 60-90 mechs, 500+ live projectiles, active jammer fields, heal beacons, status effects, and grid energy loops).

```
+-----------------------------------------------------------------------------------+
|                            HOTSPOT BREAKDOWN AT SCALE                             |
+------------------------------------+----------------------------------------------+
| HOTSPOT SYSTEM                     | PRIMARY BOTTLENECK CAUSE                     |
+------------------------------------+----------------------------------------------+
| 1. Spatial Ability Queries         | O(N*M) un-indexed spatial sweeps per frame   |
|    (Jammers, Healers, Magnets)     | for active aura nodes                        |
+------------------------------------+----------------------------------------------+
| 2. GDScript <-> Rust FFI Churn     | Array/Dictionary construction overhead per   |
|    (Projectile Flight & Targets)   | tick when marshaling data across FFI         |
+------------------------------------+----------------------------------------------+
| 3. Projectile Visual Subtree Churn | Instantiating/destroying Node2D visual trees |
|    & Firing Math Consolidation     | on shot creation during heavy volley bursts  |
+------------------------------------+----------------------------------------------+
| 4. UI Redraw Churn                 | Un-gated queue_redraw() calls on HUD bars   |
|    (MechStatusBars & Overlays)     | during continuous damage ticks               |
+------------------------------------+----------------------------------------------+
```

### Hotspot 1: Un-Indexed Spatial Ability Queries ($O(N \times M)$ Scans)
* **Code Locations:** [JammerModuleSystem.gd](file:///j:/pixel_bots/godot/scripts/entities/JammerModuleSystem.gd), [HealBeaconSystem.gd](file:///j:/pixel_bots/godot/scripts/entities/HealBeaconSystem.gd), [MagnetSystem.gd](file:///j:/pixel_bots/godot/scripts/entities/MagnetSystem.gd), [AegisShieldPulseSystem.gd](file:///j:/pixel_bots/godot/scripts/entities/AegisShieldPulseSystem.gd).
* **The Problem:** 
  * Each active jammer, heal beacon, and magnet system iterates through `EntityCache.get_group("enemy")` or global node lists every tick or sub-interval to check radial distances (`global_position.distance_to(...)`).
  * With 60+ mechs, dozens of drones, and 10+ active jammer/healer mechs, this results in hundreds of un-indexed distance calculations per frame.
* **Remediation:** 
  * Unify spatial aura queries into [ProximityQueryRs](file:///j:/pixel_bots/godot/rust_ext/src/proximity_query.rs) using spatial grid buckets.
  * Instead of each mech executing independent spatial queries, a centralized `AuraBatcher` autoload should register all active aura origins, execute **one batched spatial bucket query in Rust**, and dispatch target lists back to GDScript.

### Hotspot 2: GDScript $\leftrightarrow$ Rust FFI Marshalling Overhead
* **Code Locations:** [ProjectileManager.gd](file:///j:/pixel_bots/godot/scripts/core/ProjectileManager.gd), [ProjectileTargetingBatcher.gd](file:///j:/pixel_bots/godot/scripts/core/ProjectileTargetingBatcher.gd), [rust_ext/src/projectile_flight.rs](file:///j:/pixel_bots/godot/rust_ext/src/projectile_flight.rs).
* **The Problem:**
  * While Rust computes projectile math rapidly, GDScript must construct dynamic arrays/dictionaries (`_perf_collect_usec`) to pass position, velocity, lifetime, and synergy data across the GDExtension boundary every frame.
  * At 500+ live projectiles, marshaling polymorphic structures across the FFI boundary consumes a significant portion of the frame budget.
* **Remediation:**
  * **Packed Flat Float Arrays / Struct Buffers:** Pass a single contiguous `PackedFloat32Array` across FFI instead of arrays of Objects/Dictionaries. Structure layout: `[x, y, vx, vy, lifetime, max_lifetime, flags, ...]`. Rust reads and mutates this buffer directly in shared memory.

### Hotspot 3: Projectile Visual Subtree Churn & Firing Math
* **Code Locations:** [HexTile.gd](file:///j:/pixel_bots/godot/scripts/core/HexTile.gd#L1400) (`_fire_combined_projectile`), [Projectile.gd](file:///j:/pixel_bots/godot/scripts/entities/Projectile.gd).
* **The Problem:**
  * When weapons fire, `_fire_combined_projectile` evaluates synergy consolidation math and constructs a fresh `Node2D` visual subtree (`_build_visuals()`).
  * Destroying and rebuilding node subtrees on high fire-rate weapons (e.g. Gatling mounts or multi-pellet shotguns firing 30+ shots/sec) creates Node allocation churn.
* **Remediation:**
  * **Visual Subtree Caching:** Cache visual subtrees by elemental synergy hash (`KINETIC_FIRE_RARE`, etc.). Reusing identical visual mesh/line subtrees eliminates Node allocation overhead during high-volume firing.

### Hotspot 4: UI Redraw Churn (`MechStatusBars.gd`)
* **Code Locations:** [MechStatusBars.gd](file:///j:/pixel_bots/godot/scripts/visuals/MechStatusBars.gd).
* **The Problem:**
  * Status bars call `queue_redraw()` on health or shield changes. In large battles with damage-over-time (Poison, Fire) or high fire-rate weapons, dozens of off-screen or far mechs trigger canvas redraws simultaneously.
* **Remediation:**
  * Status bars already enforce off-screen culling via `VisibleOnScreenNotifier2D`. Extend this by throttling redraw rates for non-player/non-boss mechs to `15Hz` during combat, completely skipping redraws when HP changes are below `1%`.

---

## 4. The 3D MechWarrior Horizon Analysis

The long-term goal for Pixbots-G (or *Pixelbots 2*) is to transition from 2D tabletop combat to a **3D first/third-person/top-down strategic fighting mecha game** (feeling like *MechWarrior* / *Armored Core*), while preserving 100% of the mechanical depth (hex-grid routing, traversal step phase alignment, evolving AI Director, chip splicing, and elemental rock-paper-scissors).

```
         2D TABLETOP SCHEMATIC                     3D VOXEL CHASSIS VOLUME
     +---------------------------+             +---------------------------+
     |   [H] [Core] [Amp] [W]    |  =======>   |   / \ / \ / \ (3D Voxel   |
     |   [Hex Grid Flat View]    |             |  |---|---|---| Volume     |
     +---------------------------+             |   \ / \ / \ / Grid)       |
                                               +---------------------------+
```

### 1. Translating Hex-Grid Routing to 3D Voxel Volumes
* **The Voxel-Cube Projection:**
  * Section 1a of `Status.md` establishes that a 2D hex grid represents the **unfolded planar projection of a 3D axial cube/voxel volume**.
  * In 3D, garage customization zooms into a 3D model of the selected limb (Torso, Left Arm, Right Arm, Legs, Head, Backpack). The player builds routing grids using 3D hex-column/cube volumes inside the mech's internal chassis.
* **Locational Damage & Penetration Physics:**
  * In 2D, damage hits a component's outer edge. In 3D MechWarrior-style combat, incoming projectiles strike specific 3D chassis surface coordinates.
  * **Armor Penetration Depth:** High-velocity Pierce or Kinetic rounds penetrate through external armor into the internal 3D voxel grid, damaging or destroying the specific hex tiles (Core, Conduit, Weapon Mount) located along the entry trajectory!

### 2. 3D Camera Modes & Perspective Strategy
* **1st Person Diegetic Cockpit:**
  * Holographic 3D hex-grid energy routing monitors mounted on the cockpit dashboard.
  * Dynamic glass reflections, rain/oil splatters on the canopy, cockpit shaking under heavy autocannon fire, and heat blur venting outside the glass.
* **3rd Person Action Camera:**
  * Armored Core-style chase camera with dynamic spring-arm dampening.
  * Camera kick on heavy weapon discharge, thruster ignition flare, dynamic motion blur, and spatial sound positioning.
* **Top-Down Holographic Tactical Command (RTS View):**
  * Allows seamless switching between direct piloting and a tabletop tactical command view, preserving the original tabletop fantasy as a holographic war room projection.

### 3. 3D Audio Landscape
* **HRTF 3D Spatial Audio:** Sound sources positioned in full 3D space with distance attenuation and obstacle occlusion (e.g. explosions behind ruins sound muffled).
* **Cockpit Sound Dampening:** Cockpit interior view dampens external high-frequency audio while amplifying internal mechanical sounds (hydraulic servos, reactor hum, warning klaxons, structural metal stress creaks).

### 4. 3D Engine & Rendering Architecture (Godot 4 3D / Jolt)
* **Jolt 3D Physics Engine:** Godot 4.6 integrates Jolt 3D Physics. Broadphase projectile sweeps and mech movement will utilize Jolt's multithreaded 3D spatial queries.
* **MultiMeshInstance3D Procedural Mesh Batching:**
  * Procedurally generated mechs comprised of voxel cubes must not use individual `MeshInstance3D` nodes per tile.
  * Instead, combine internal hex-cube geometry into unified procedural meshes (`ArrayMesh`) using vertex colors and PBR material maps generated natively via Rust (`rust_ext`).

---

## 5. Master Implementation Roadmap

```
+-----------------------------------------------------------------------------------+
|                             MASTER EXECUTION PHASES                               |
+--------------------------+--------------------------+-----------------------------+
| PHASE 1: 2D POLISH       | PHASE 2: UI & AUDIO      | PHASE 3: 3D EXTRACTION      |
| • WorldEnvironment HDR   | • Multi-layer Audio      | • Extract pixbots_core Rust |
| • Hitstop & Camera Kick  | • Animated Sci-Fi UI     | • 3D Voxel Grid Prototype   |
| • Spatial Query Batching | • Flat FFI Array Buffers | • Jolt 3D Integration       |
+--------------------------+--------------------------+-----------------------------+
```

### Phase 1: Immediate 2D Visual Polish & Performance Fixes (Current Engine)
- [x] **WorldEnvironment HDR Bloom:** Added programmatically in `Main._setup_pixel_viewport()` (2026-08-06) rather than hand-edited into `main.tscn` - a malformed `.tscn` edit risks the whole scene failing to load. Conservative defaults per spec; inert until projectile/packet colors are actually pushed into HDR range, which is a real follow-up, not yet done.
- [x] **Hitstop & Frame Freeze Manager:** `scripts/core/HitstopManager.gd` (2026-08-06), autoload, wired into Pierce executions and boss deaths. Self-restoring via an `ignore_time_scale` recovery timer - verified headless in `AAAPolishPhase1Check.gd`.
- [x] **Camera Kick & Recoil:** `CameraShake.kick()` (2026-08-06), additive with the existing omnidirectional `shake()`. Wired into Lance Mount and Orbiting Array fire() (player shots only).
- [x] **Tabletop Diorama Shader:** Already shipped (`e1baa1d`/`74238e6`, prior session) - predates this doc.
- [ ] **Batch Spatial Ability Queries:** Not attempted in the 2026-08-06 autonomous pass - a correctness-sensitive refactor across live Jammer/Healer/Magnet combat behavior that needs an actual playtest to verify, not just a headless check. Left for a supervised session.

### Phase 2: Audio Elevation & FFI Optimization
- [ ] **Multi-Layered Weapon Audio:** Not attempted (2026-08-06 pass) - audio synthesis quality can't be judged without actually hearing it, deliberately left for a supervised session.
- [ ] **Tactile UI Audio Cues:** Same reasoning as above - skipped, not a code-risk call, a "can't verify by ear" call.
- [ ] **Packed Float FFI Buffers:** Convert [ProjectileManager.gd](file:///j:/pixel_bots/godot/scripts/core/ProjectileManager.gd) $\leftrightarrow$ Rust GDExtension array transfers to packed float buffers.
- [ ] **Sci-Fi UI & Animated Conduits:** Integrate custom typography and animate energy flow paths inside the Garage UI. (Custom font files aren't available to source autonomously.)

### Phase 3: Long-Term 3D Extraction (*Pixelbots 2* / 3D Horizon)
- [ ] **Extract `pixbots_core` Crate:** Isolate hex-grid simulation, packet routing, and AI Director logic into an engine-agnostic Rust crate (`pixbots_core`).
- [ ] **3D Voxel Grid Surface Mapper:** Build axial-to-cube diagonal mapper projecting 2D hex layouts into 3D voxel volumes.
- [ ] **3D Prototype Scene:** Build Godot 4.6 3D test scene utilizing Jolt 3D Physics, 1st Person Cockpit view, 3rd Person Action view, and MultiMesh procedural chassis rendering.

---
*End of Master Technical & Strategy Roadmap.*


