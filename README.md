# PIXBOTS-G: TECHNICAL MANUAL & SANDBOX GUIDE

Welcome to the Pixbots-G operations manual. This document details the technical specifications of your Mech, the component modules at your disposal, and the AI routines governing enemy units. 

Currently, Pixbots-G is in an active **Sandbox / Toy** phase. While formal progression mechanics (like a campaign) are still under construction, the game features a robust procedural energy-routing engine and an AI director that allows for infinite hours of tinkering, limit-testing, and chaotic battles.

---

## 1. INSTALLATION & SETUP INSTRUCTIONS

To get started with the Pixbots-G sandbox, you will need the Godot Engine and a local copy of this repository.

### Prerequisites
- **Godot Engine**: Download and install Godot Engine **v4.2 or higher** (Standard version, .NET not required) from the [official website](https://godotengine.org/download).
- **Git**: Ensure Git is installed on your system if you plan to clone the repository.

### Installation Steps
1. **Clone the Repository**:
   Open your terminal/command prompt and run:
   ```bash
   git clone https://github.com/Utility-SOC/Pixbots-G.git
   ```
   *(Alternatively, you can download the project as a .zip file from GitHub and extract it).*
2. **Open the Project in Godot**:
   - Launch the Godot Engine.
   - Click the **Import** button.
   - Navigate to the cloned `Pixbots-G/godot` directory and select the `project.godot` file.
   - Click **Import & Edit**.
3. **Run the Game**:
   - In the top right corner of the Godot editor, click the **Play** button (or press `F5`).
   - The Main Menu will appear. Click **Start Game** to deploy!

---

## 2. HOW TO PLAY IT AS A TOY (SANDBOX MODE)

Pixbots-G is currently designed to be an engineering sandbox. The most fun you can have right now is by pushing the procedural energy grid to its absolute breaking point. 

### The Debug Menu
During gameplay, press **`~` (Tilde)** or **`F3`** (or whatever key is bound to the Debug Menu) to open the Sandbox Controls. This menu allows you to break all the rules:
- **Give AMPED Grid**: Instantly replaces your Torso grid with an insanely complex, pre-built loop of Legendary Splitters and Amplifiers. Warning: Firing this weapon may cause excessive screen shake and frame drops due to the sheer volume of projectiles spawned!
- **Upgrade Core**: Instantly sets your core reactor to Legendary rarity, allowing it to output maximum energy across all faces.
- **Reactor Override**: Force your core to output specific elemental synergies (e.g., Vortex, Ice, Kinetic) regardless of what components you actually have installed.
- **Spawn Specific Enemies**: Want to test your build against a specific threat? Use the debug buttons to instantly drop a Brawler, Scout, or Sniper right on top of you.
- **Spawn Boss**: Test your mettle against a massive, 5x-scaled Boss mech with extreme health pools and unique drop tables.
- **Restore Components**: Instantly heal your mech to 100% and revive any destroyed component grids.

### Limit Testing
The engine is robust, but you can try to break it! 
- **The Speed Demon**: Try filling your Legs and Torso exclusively with `Jumpjet Tiles` and `Actuator Tiles`, feed them pure KINETIC energy, and see if you can make your mech move so fast it phases through the environment!
- **The Black Hole**: Stack multiple VORTEX elemental packets into a highly amplified weapon mount. The resulting projectile will create a gravity well so strong it will permanently stick enemy squads to the walls!
- **The Infinite Loop**: Try to build a closed circuit using `Reflector Tiles` and `Amplifier Tiles` without a Weapon Mount attached. Open the Garage Menu and click **Simulate Energy Flow** to watch the energy packets multiply until they crash the mathematical float limits of the engine (producing a massive negative integer overflow)!

*(Screenshots to be added here: `![Garage Simulation](assets/images/garage_sim.png)`, `![Battlefield Chaos](assets/images/battlefield.png)`)*

---

## 3. COMPONENT HEX TILES

Your Mech's capabilities are determined by the Hex Tiles installed on its grid. Understanding the flow of energy packets through these tiles is essential for optimization. 

### Power Generation & Storage
- **Core Tile**: The primary power source. Energy originates here and flows outward through active faces.
- **Microcore Tile**: A secondary, localized power generator. Provides supplementary energy but has limited output faces.
- **Accumulator Tile**: Stores excess energy packets. Discharges them when the primary draw exceeds generation, serving as a buffer.

### Routing & Modulation
- **Splitter Tile**: Receives an energy packet and duplicates it, sending it out across multiple faces. Crucial for powering multiple weapons simultaneously.
- **Directional Conduit Tile**: Forces energy to flow in one specific direction, preventing backflow and ensuring packets reach their intended destination.
- **Amplifier Tile**: Modulates the packet, increasing the final output value (e.g., weapon damage or shield strength) at the cost of durability.
- **Filter Tile**: Acts as a gateway that only allows specific elemental energy (e.g., FIRE or ICE) to pass through, blocking unmatched packets.
- **Catalyst Tile**: Converts standard kinetic energy into elemental energy, allowing you to trigger Synergies without a specialized Core.
- **Reflector Tile**: Bounces energy packets back in the direction they came from, useful for complex closed-loop routing.
- **Resonator Tile**: Increases efficiency if multiple packets of the same element pass through it consecutively.
- **Infuser Tile**: Consumes two different elemental packets to output a combined, higher-tier elemental packet.

### Utilities & Combat
- **Weapon Mount Tile**: The terminal node for energy. Converts incoming packets into offensive projectiles based on the energy's element.
- **Shield Generator Tile**: Converts incoming packets into a defensive barrier, absorbing incoming damage before it hits your hull.
- **Actuator Tile & Jumpjet Tile**: Mobility modules that consume energy to increase the base speed and traversal capabilities of your Mech.

---

## 4. COMPONENT RARITY & SYNC ADJUSTMENT

Hex Tiles are classified into four rarities: **COMMON, UNCOMMON, RARE, and LEGENDARY**.

Higher rarity tiles are not just structurally superior; they possess a variance in their **Sync Adjustment**. This adjustment modifies how efficiently the tile links with adjacent components:
- **COMMON & UNCOMMON**: Standard specification. No sync adjustment (0).
- **RARE**: Has a 40% probability of exhibiting a minor sync deviation (+1 or -1).
- **LEGENDARY**: Highly volatile prototypes. Has an 80% probability of exhibiting a significant sync deviation (+1, -1, +2, or -2).

---

## 5. ELEMENTAL SYNERGIES

When specific elemental energy packets reach a Weapon Mount, they trigger unique subroutines. Combining elements creates uniquely tinted projectiles with blended physical properties!
- **KINETIC**: Standard armor-piercing projectile that maintains a straight trajectory.
- **FIRE**: Ignites the impact zone and experiences high air resistance ("The Plume").
- **ICE**: Heavy, crystalline mass that resists steering and slows target processing speeds.
- **POISON**: Corrosive acid that arches in a gravity-affected lob ("The Mortar").
- **LIGHTNING**: Arcs to secondary targets within a localized radius.
- **VAMPIRIC**: Actively curves its trajectory to seek and hunt down enemy units ("The Hunter").
- **VORTEX**: Generates a localized gravity well, pulling nearby units out of formation.

---

## 6. SQUAD DIRECTOR (AI ROUTINES) & ENEMIES

The enemy forces are not randomized; they are controlled by the **Squad Director**, an AI that dynamically allocates resources to defeat you.

### Chassis Specifications
- **SCOUT**: Low HP (80), extremely high mobility (220 Speed). Engages at 250 units.
- **BRAWLER**: High HP (150), moderate mobility (130 Speed). Engages at close range (100 units).
- **SNIPER**: Fragile (60 HP) but maintains maximum distance (450 units). Low fire rate but high accuracy.
- **AMBUSHER**: Standard chassis (90 HP, 180 Speed). Engages at 180 units with a high fire-rate burst capability.
- **FLAMETHROWER**: Heavy chassis (120 HP). Closes in to 150 units to deploy area-of-effect damage.

### Tactical Assembly & Link-ups
The Director spawns units based on weighted templates (e.g., "Sniper Team", "Ambushers"). It actively searches the map for "wild bots" (unassigned units) and recruits them into squads to fulfill required roles. If a squad takes heavy casualties, it will broadcast a link-up request to any other broken squad within a 1000-unit radius, merging them to maintain a full tactical formation of up to 12 units.

### Reactive Resistance Profiling
The Director monitors the elemental damage it sustains. Once you deal over 500 total damage, the Director evaluates your elemental usage. If you rely on a single element for more than 40% of your damage output, the Director will deploy specialized, element-resistant Mechs with visual dampeners!

*(Screenshots to be added here: `![Auto-Equipped Limbs](assets/images/auto_equip.png)`)*

---

## 7. HEX GRID DESIGN SUGGESTIONS & ENGINEERING BEST PRACTICES

To maximize the efficiency of your Mech's hex grid, consider the following routing configurations:

- **The Closed Loop (Resonator + Reflector):** Route energy through a Resonator, into a Reflector, and back through the Resonator. This allows you to stack efficiency multipliers before splitting the packet off to your weapon systems.
- **Elemental Dual-Wielding (Elemental Infuser + Splitter):** Use a Splitter early in your grid to divide your Core's kinetic output. Route one packet into a Elemental Infuser (e.g., FIRE) and the other into a different Elemental Infuser (e.g., LIGHTNING). This bypasses the Squad Director's Reactive Resistance Profiling by keeping your elemental damage ratios balanced.
- **Burst Buffer (Accumulator + Amplifier):** Place an Accumulator right before an Amplifier and Weapon Mount. Allow the Accumulator to store energy during downtime. When engaging an enemy, the stored energy will rapidly push through the Amplifier, creating a massive opening burst attack before settling into a sustained fire rate.
- **Shield Priority Routing (Directional Conduit):** Always use Directional Conduits when routing to Shield Generators. If a component is damaged or disabled, you do not want energy backflowing away from your critical defensive systems.

---

## 8. CORE GAMEPLAY LOOP

Understanding the operational flow of Pixbots-G is essential for sustained success on the battlefield:
1. **The Garage Phase:** You begin in the Garage. Here, you will install Hex Tiles into your Mech's chassis. Your primary goal is to ensure that energy packets generated by your Cores are efficiently routed through modifiers (like Amplifiers and Catalysts) and safely deposited into Weapon Mounts and Shield Generators.
2. **Deployment:** Once your systems are online, you deploy to the battlefield. The environment is procedurally generated with varying biomes and obstacles. Every time you leave the garage, the game will automatically create an `autosave.json` backup of your configuration!
3. **The Engagement:** The Squad Director will spawn continuous waves of enemy bots. You must maneuver your Mech, manage your energy reserves, and eliminate the hostile forces. 
4. **Escalation & Adaptation:** As you fight, the Director analyzes your tactics and deploys counter-measures. You must adapt your combat style on the fly to survive the increasingly difficult waves.
5. **Re-calibration:** After a successful engagement (or a catastrophic failure), you will return to the Garage. You can redesign your energy grids, test new synergistic combinations, and prepare for the next deployment.

*(Screenshots to be added here: `![Component Infusion](assets/images/infusion.png)`)*

---

## 9. RECENT SYSTEM UPDATES (CHANGELOG)

- **Performance Overhaul:** Significantly improved the Big O complexity of Weapon Mount projectile spawning. Packets are now cleanly merged by traversal step, preventing infinite frame-freezes on Amped grids.
- **Peripheral Auto-Equip:** The Auto-Equip solver now properly hooks into external energy feeds from the Torso, allowing it to seamlessly snake pipes across Arms, Legs, and Heads!
- **Squat Head Geometry:** Fixed the procedural generation for the Head component so it builds vertically and wide, rather than leaning at an acute angle.
- **Debug Sync:** Fixed the Reactor Override dropdown to accurately push Vampiric/Seeking synergies without falling back to Poison.
- **Loot System Restored:** Defeated enemy Mechs will now drop components and tiles for the player to collect!
- **Pacifist AI Subroutines Patched:** Enemy AI will now properly route their Weapon Mounts and actively fire on the player.
- **Component Infusion Added:** Players can now destroy components to grant XP to other components, levelling them up and granting stat modifiers.
- **Component Swapping Added:** Players can now swap components on their Mech in the Garage.
- **AI War Room & Persistent Learning:** The AI Director now saves its learned strategies between sessions! You can view its evolving squads and lineage in the new War Room UI (press `TAB`), and even export/import profiles to swap trained AI with friends.
- **Modding Support (Phase 1):** You can now define and load custom baseline squad packs via `config/default_squads.json`. See `MODDING.md` for full documentation!
- **Minimap Added:** A new minimap overlay helps you track terrain and enemy squad movements.
- **Environmental & Tactical Additions:** Destructible Ruin Obstacles have been added. Furthermore, jumpjets now automatically activate and sustain when traversing water hazards!
- **Visual Improvements:** The cloaking effect has been redesigned with a new distortion-circle shader, and lightning strikes now use an instant stylized polyline effect.
- **Roadmap & Docs:** `FEATURE_ROADMAP.md` has been added with all upcoming design decisions (including the scrap economy and lightweight heat system).
