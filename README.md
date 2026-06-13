# PIXBOTS-G: TECHNICAL MANUAL

Welcome to the Pixbots-G operations manual. This document details the technical specifications of your Mech, the component modules at your disposal, and the AI routines governing the enemy units. Please review these parameters prior to deployment.

*Note on current software version:* Loot drops are currently disabled and will not drop from enemies in this build. Furthermore, enemy weapon systems are currently offline for maintenance; they will track and approach you, but they do not shoot yet.

---

## 1. COMPONENT HEX TILES
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

## 2. COMPONENT RARITY & SYNC ADJUSTMENT
Hex Tiles are classified into four rarities: **COMMON, UNCOMMON, RARE, and LEGENDARY**.

Higher rarity tiles are not just structurally superior; they possess a variance in their **Sync Adjustment**. This adjustment modifies how efficiently the tile links with adjacent components:
- **COMMON & UNCOMMON**: Standard specification. No sync adjustment (0).
- **RARE**: Has a 40% probability of exhibiting a minor sync deviation (+1 or -1).
- **LEGENDARY**: Highly volatile prototypes. Has an 80% probability of exhibiting a significant sync deviation (+1, -1, +2, or -2).

## 3. ELEMENTAL SYNERGIES
When specific elemental energy packets reach a Weapon Mount, they trigger unique subroutines:
- **KINETIC**: Standard armor-piercing projectile.
- **FIRE**: Ignites the impact zone, leaving a residue that causes damage over time.
- **ICE**: Decreases the target's internal processing speed, lowering their movement rate.
- **POISON**: Corrosive acid that bypasses standard armor and damages the hull directly.
- **LIGHTNING**: Arcs to secondary targets within a localized radius.
- **VAMPIRE**: Absorbs structural integrity from the target and reroutes it to repair your Mech.
- **VORTEX**: Generates a localized gravity well, pulling nearby units out of formation.

## 4. ENEMY CHASSIS SPECIFICATIONS
You will encounter five distinct chassis types deployed by the enemy AI:
- **SCOUT**: Low HP (80), extremely high mobility (220 Speed). Engages at 250 units.
- **BRAWLER**: High HP (150), moderate mobility (130 Speed). Engages at close range (100 units).
- **SNIPER**: Fragile (60 HP) but maintains maximum distance (450 units). Low fire rate but high accuracy.
- **AMBUSHER**: Standard chassis (90 HP, 180 Speed). Engages at 180 units with a high fire-rate burst capability.
- **FLAMETHROWER**: Heavy chassis (120 HP). Closes in to 150 units to deploy area-of-effect damage.

## 5. SQUAD DIRECTOR (AI ROUTINES)
The enemy forces are not randomized; they are controlled by the **Squad Director**, an AI that dynamically allocates resources to defeat you.

### Wave Escalation
The Director operates in waves. For every wave completed, the maximum HP and Shield HP of all newly spawned enemies increases exponentially by a multiplier of `1.10^(Wave - 1)`.

### Tactical Assembly & Link-ups
The Director spawns units based on weighted templates (e.g., "Sniper Team", "Ambushers"). It actively searches the map for "wild bots" (unassigned units) and recruits them into squads to fulfill required roles. If a squad takes heavy casualties, it will broadcast a link-up request to any other broken squad within a 1000-unit radius, merging them to maintain a full tactical formation of up to 4 units.

### Reactive Resistance Profiling
The Director monitors the elemental damage it sustains. Once you deal over 500 total damage, the Director evaluates your elemental usage. If you rely on a single element for more than 40% of your damage output, the Director will deploy specialized, element-resistant Mechs. These Mechs take 50% less damage from your favored element and deploy visual dampeners (e.g., a "Grounded" yellowish tint against Lightning, or an "Anti-Heal" red tint against Vampire attacks).

## 6. ENGINEERING BEST PRACTICES (BUILD SUGGESTIONS)
To maximize the efficiency of your Mech's hex grid, consider the following routing configurations:

- **The Closed Loop (Resonator + Reflector):** Route energy through a Resonator, into a Reflector, and back through the Resonator. This allows you to stack efficiency multipliers before splitting the packet off to your weapon systems.
- **Elemental Dual-Wielding (Elemental Infuser + Splitter):** Use a Splitter early in your grid to divide your Core's kinetic output. Route one packet into a Elemental Infuser (e.g., FIRE) and the other into a different Elemental Infuser (e.g., LIGHTNING). This bypasses the Squad Director's Reactive Resistance Profiling by keeping your elemental damage ratios balanced.
- **Burst Buffer (Accumulator + Amplifier):** Place an Accumulator right before an Amplifier and Weapon Mount. Allow the Accumulator to store energy during downtime. When engaging an enemy, the stored energy will rapidly push through the Amplifier, creating a massive opening burst attack before settling into a sustained fire rate.
- **Shield Priority Routing (Directional Conduit):** Always use Directional Conduits when routing to Shield Generators. If a component is damaged or disabled, you do not want energy backflowing away from your critical defensive systems.

## 7. CORE GAMEPLAY LOOP
Understanding the operational flow of Pixbots-G is essential for sustained success on the battlefield:
1. **The Garage Phase:** You begin in the Garage. Here, you will install Hex Tiles into your Mech's chassis. Your primary goal is to ensure that energy packets generated by your Cores are efficiently routed through modifiers (like Amplifiers and Catalysts) and safely deposited into Weapon Mounts and Shield Generators.
2. **Deployment:** Once your systems are online, you deploy to the battlefield. The environment is procedurally generated with varying biomes and obstacles.
3. **The Engagement:** The Squad Director will spawn continuous waves of enemy bots. You must maneuver your Mech, manage your energy reserves, and eliminate the hostile forces. 
4. **Escalation & Adaptation:** As you fight, the Director analyzes your tactics and deploys counter-measures. You must adapt your combat style on the fly to survive the increasingly difficult waves.
5. **Re-calibration:** After a successful engagement (or a catastrophic failure), you will return to the Garage. You can redesign your energy grids, test new synergistic combinations, and prepare for the next deployment. *(Note: Once the Loot System is brought online, you will also use this phase to integrate recovered enemy components into your build).*

## 8. KNOWN BUGS & SYSTEM MALFUNCTIONS
Please be advised that the current build of Pixbots-G is undergoing active maintenance. You may encounter the following known issues:
- **Loot System Offline:** Defeated enemy Mechs currently do not drop loot or components. You cannot acquire new Hex Tiles during gameplay at this time.
- **Pacifist AI Subroutines:** An error in the enemy AI logic currently prevents them from firing their weapons. They will successfully spawn, form squads, track your location, and pursue you, but they will not shoot. 
- **Debug Overlays:** The Debug Menu remains accessible in the live build. Pressing the **`** (Tilde) key will open it, allowing you to manually spawn enemies or alter the map state.
