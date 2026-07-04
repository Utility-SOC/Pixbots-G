# PIXBOTS-G: THE COMPREHENSIVE TECHNICAL MANUAL

Welcome to Pixbots-G, an engineering-focused Mech combat sandbox. This comprehensive manual details everything from the procedural energy-routing engine to the evolving AI that learns to defeat you.

## 1. INSTALLATION & SETUP

### Prerequisites
- **Godot Engine**: Download and install Godot Engine **v4.2 or higher** (Standard version, .NET not required) from the [official website](https://godotengine.org/download).
- **Git**: Ensure Git is installed on your system if you plan to clone the repository.

### Installation Steps
1. **Clone the Repository**:
   ```bash
   git clone https://github.com/Utility-SOC/Pixbots-G.git
   ```
2. **Open the Project in Godot**: Launch Godot, click **Import**, select `project.godot` inside the `Pixbots-G/godot` directory, and click **Import & Edit**.
3. **Run the Game**: Click the **Play** button (or press `F5`). 

---

## 2. THE GARAGE & UPGRADE ECONOMY

The Garage is your engineering bay. Here, you construct the energy grids that power your Mech. 

### The Garage Interface (Buttons & Toggles)
When you enter the Garage, you will interact with several controls:
- **Component Tabs**: Select which part of your Mech to edit (Torso, Left Arm, Right Arm, Left Leg, Right Leg, Head).
- **Swap Component**: Opens your inventory to replace the currently selected component with another one (e.g., swapping a damaged limb for a new one).
- **Infuse (Destroy part)**: Destroys a component from your inventory to grant XP to the currently equipped component, leveling it up and unlocking stat modifiers.
- **Simulate Energy Flow**: A crucial debugging tool. Clicking this button visualizes the BFS (Breadth-First Search) routing of energy packets through your grid, showing exactly what output your Weapon Mounts will receive.
- **Auto-Equip**: The solver automatically fills empty grid spaces with a mathematically optimal setup. It can even route energy feeds from your Torso across components, snaking pipes into your Arms, Legs, and Head seamlessly!
- **Clear Grid**: Wipes all tiles off the currently selected component.
- **Separate L/R Firing**: A toggle that dictates whether Left-click fires all weapons, or if Left-click fires Left Arm/Torso weapons and Right-click fires Right Arm weapons.
- **Show Static Paths**: Toggles the permanent visualization of energy pipes.

### The Black Market
The Black Market is a shop that offers specialized, high-tier components and tiles.
- **Rotation**: The shop rotates its inventory deterministically every 10 minutes of real time.
- **Purchasing**: You buy items using Scrap gathered from combat.
- **Equipping**: Once purchased, new tiles go to your inventory for grid placement, and new components can be swapped onto your chassis via the **Swap Component** button in the Garage. Beware: Black Market components often come with "forbidden-tile" drawbacks or unique cursed geometries!

---

## 3. HEX TILES, RARITIES, AND SYNC DEVIATIONS

Your Mech is built from Hex Tiles. Every tile belongs to a rarity tier that dictates its efficiency, volatility, and features.

### Rarity System & Sync Deviations
Higher rarity tiles offer massive multipliers, but they introduce **Sync Deviations**. 
In Pixbots-G, if two energy paths merge at a Weapon Mount, they only combine their power if they arrive on the EXACT same **Traversal Step** (the "latency" or "phase" of the packet). 
- **COMMON & UNCOMMON**: Standard specification. Reliable, with no sync adjustment (deviation of 0).
- **RARE**: 40% probability of exhibiting a minor sync deviation (+1 or -1 traversal step).
- **LEGENDARY**: Highly volatile prototypes. 80% probability of exhibiting a significant sync deviation (+1, -1, +2, or -2).
- **MYTHIC**: Game-breaking tiles with unique, rule-bending toggles (see tile descriptions below).

*Warning: If you split a packet into two parallel paths using Legendary tiles, their Sync Deviations might desync the packets, causing them to arrive at the weapon mount at different times, firing two weak shots instead of merging into one massive shot!*

### Exhaustive Tile Glossary

**Power Generation & Storage**
- **Core Tile**: The primary power source. Generates RAW energy packets. *Mythic Toggle*: Native Element (Core outputs a specific element instead of RAW).
- **Microcore Tile**: A secondary, localized generator with fewer output faces.
- **Accumulator Tile**: Stores excess energy. Discharges when primary draw exceeds generation. *Combat Mechanics*: Accumulators passively charge. You can left-click for standard fire (with a quality tax) or hold 1/2/3 to pre-prime and dump the full stored value in a massive volley.

**Routing & Modulation**
- **Splitter Tile**: Receives a packet and duplicates it. *Mythic Feature*: 6-face output and x2 multiplier!
- **Directional Conduit Tile**: Forces energy to flow in one specific direction (prevents backflow).
- **Amplifier Tile**: Modulates the packet, increasing its magnitude. *Overlimit Note*: Amplification has a hard mathematical ceiling of **150,000 magnitude**. If a packet exceeds this ceiling, it is clamped. *Mythic Toggle*: Focus (Condense amplification to a single extreme output).
- **Filter Tile**: Only allows specific elemental energy to pass through.
- **Catalyst Tile**: Converts standard energy into elemental energy. *Mythic Toggle*: `cycle_synergy()` (Invert or rotate the output element).
- **Reflector Tile**: Bounces energy packets back in the direction they came from.
- **Resonator Tile**: Increases efficiency if multiple packets of the same element pass through consecutively. 
- **Infuser Tile**: Consumes two different elemental packets to output a combined, higher-tier elemental packet.
- **Magnet Tile**: Alters the flow of packets based on rules. *Mythic Toggle*: Attract/Repel mode + Rarity Filter!

**Utilities & Combat**
- **Weapon Mount Tile**: Converts incoming packets into offensive projectiles based on the energy's element. *Mythic Feature*: Custom spread patterns.
- **Shield Generator Tile**: Converts packets into a defensive barrier that fully absorbs incoming damage while it holds.
- **Actuator Tile**: Consumes energy to increase base movement speed.
- **Jumpjet Tile**: Grants aerial evasion/traversal. *Mechanic*: If you traverse water hazards, jumpjets automatically activate and sustain to prevent drowning! *Mythic Toggle*: Blink (Instant teleportation).

---

## 4. ELEMENTAL SYNERGIES

When specialized energy packets reach a Weapon Mount, they trigger unique subroutines. Projectiles blend physical properties (speed, scale, lifetime, trails, and color) proportionally based on the synergy ratios in the packet.

- **RAW**: Baseline energy. Reliable but no special effects.
- **KINETIC**: Armor-piercing projectile maintaining a straight trajectory.
- **FIRE**: Ignites the impact zone. Experiences high air resistance.
- **ICE**: Heavy, crystalline mass that resists steering and slows target movement/processing speeds (Freezing).
- **POISON**: Corrosive acid that arches in a gravity-affected lob.
- **LIGHTNING**: Fires an instant stylized polyline that arcs to secondary targets within a localized radius, paralyzing them.
- **VAMPIRIC**: Actively curves its trajectory to seek and hunt down enemy units ("The Hunter"). Heals the shooter based on damage dealt.
- **VORTEX**: Generates a localized gravity well, pulling nearby units out of formation.
- **PIERCE**: Has a percentage chance to instantly execute ("cut in half") non-boss targets.
- **EXPLOSION**: Standard AoE blast damage on impact.

---

## 5. THE AI SYSTEM & SQUAD DIRECTOR

Pixbots-G doesn't use random spawns; you are fighting a learning AI called the **Squad Director**. 

### Enemy Chassis & Roles
The AI fields specialized bots tailored to counter you:
- **SCOUT**: Low HP, extreme mobility. Engages at max range. Often equipped with Jumpjets or Jammers.
- **BRAWLER**: High HP, moderate mobility. Engages at close range.
- **SNIPER**: Fragile, maintains maximum distance. Low fire rate, extreme accuracy.
- **AMBUSHER**: Uses Cloaking to sneak up and unleash high fire-rate bursts. 
- **FLAMETHROWER**: Heavy chassis built to close in and deploy AoE elemental damage.
- **SUPPORT**: Carries Heal Beacons and defensive auras to protect the squad.
- **JAMMER**: Specialized electronic-warfare mechs that disable your elemental synergies.
- **COMMANDER**: A high-tier leader unit that can carry up to 5 support modules to buff an entire squad!
- **BOSS**: A massive, 5x-scaled mech with extreme health pools and unique drop tables.

### The Squad Director & Persistent Learning
The AI merges wild bots into squads and actively mutates its templates based on fitness (combat success).
- **Persistent Evolution**: The AI Director **saves its learned strategies** to disk between sessions! If it learns that Snipers beat you today, it will spawn Snipers tomorrow. 
- **Reactive Resistance Profiling**: The Director tracks your elemental damage output. If you over-rely on FIRE, it will deploy Fire-resistant mechs and FIRE-Jammer modules.
- **Execute Counterplay**: If you over-rely on Piercing instant-kills, the Director logs your "kill methods" and will dynamically deploy **Piercing Jammers**. Units inside a Piercing Jammer's aura (along with Bosses and Commanders) are immune to executes!

### The War Room Interface
Press **`TAB`** in-game to access the War Room. 
- **Lineage Graphs & Fitness Logs**: View a visual log of the AI's evolving lineage, the current fitness scores of its Squad Templates, and what compositions it is favoring.
- **Export to Clipboard**: Copies the AI's current learned profile (as JSON text) so you can share it with friends!
- **Import from Clipboard**: Overwrites the AI's current state with a profile you pasted, allowing you to fight the exact AI your friend trained.

---

## 6. ENGINEERING BEST PRACTICES & SANDBOX FUN

The engine is robust, but you can try to break it!

### Routing Suggestions
- **The Closed Loop**: Route energy through a Resonator, into a Reflector, and back through the Resonator to stack efficiency multipliers before splitting the packet off to your weapons.
- **Elemental Dual-Wielding**: Split your Core's output and route them through two different Elemental Infusers. This bypasses the Squad Director's Resistance Profiling by keeping your elemental damage ratios perfectly balanced!
- **Burst Buffer**: Place an Accumulator right before an Amplifier and Weapon Mount. Store energy during downtime, then release a massive pre-primed volley (by holding 1/2/3) to unleash an opening burst attack.
- **The Speed Demon**: Try filling your Legs and Torso exclusively with Jumpjet and Actuator Tiles, feed them pure KINETIC energy, and phase through the environment.
- **The Black Hole**: Stack multiple VORTEX elemental packets into a highly amplified weapon mount to permanently stick enemy squads to the walls.

### Main Menu Interface
- **Difficulty Options**: The dropdown lets you set the baseline scaling. The highest difficulty forces the AI to remain peer-to-peer with your loadout strength.
- **Continue Game**: Loads the most recent autosave (which happens automatically every time you leave the garage).
- **New Campaign / Endless / Sandbox**: Different launch vectors for deploying your mech.

### Debug Controls
Press **`~` (Tilde)** or **`F3`** during gameplay to open the Sandbox Debug Menu. 
- **Give AMPED Grid**: Instantly injects a pre-built legendary loop into your torso.
- **Upgrade Core**: Maxes out your reactor's rarity.
- **Reactor Override**: Force your core to output specific elemental synergies (e.g., Vortex, Ice, Kinetic) bypassing your internal grid.
- **Spawn specific Enemies / Bosses**: Drops a custom threat right in front of you.
- **Restore Components**: Instantly heals your mech to 100% and revives any destroyed component grids.

---

## 7. MODDING & ROADMAP

Pixbots-G was built with an open architecture. 
- **Modding AI Squads**: You can define custom baseline squad packs by editing `config/default_squads.json`. See the `MODDING.md` file in the repository for full documentation on how to write custom JSON profiles and share them.
- **Future Development**: Check out `FEATURE_ROADMAP.md` for a comprehensive list of upcoming design decisions, including the Scrap Economy, Lightweight Heat System, and Melee/Mass Physics engine!
