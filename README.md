# Pixbots-G

A Godot-based tactical 2D game focusing on Mech combat, hex-based component management, and energy routing. Build and customize your bots, route energy effectively, and engage in tactical skirmishes!

## Features

- **Hex-Grid Component Management**: Equip your mechs by placing and linking components on a hex grid.
- **Dynamic Energy Routing**: Route energy between cores, accumulators, and weapons to optimize your combat capabilities.
- **Tactical Combat**: Field customizable mechs with unique weapons, shields, and movement capabilities.
- **Loot System**: Collect and equip new components dropped during engagements.

## Installation

1. **Install Godot**: Download and install [Godot Engine 4.x](https://godotengine.org/download) (ensure you match the minor version used by the project if applicable).
2. **Clone the Repository**:
   ```bash
   git clone https://github.com/Utility-SOC/Pixbots-G.git
   ```
3. **Open the Project**:
   - Open the Godot Engine.
   - Click on **Import**.
   - Navigate to the cloned `Pixbots-G` directory and select the `project.godot` file.
   - Click **Import & Edit**.

## Gameplay Instructions

1. **Garage & Customization**: Use the Garage UI to modify your Mechs. Place hex tiles (like Microcores, Accumulators, and Weapon Mounts) onto your mech's grid.
2. **Energy Routing**: Ensure your components are properly linked. Energy must flow from Cores to Weapons and Shields to activate them.
3. **Combat**: Deploy your customized mechs. Position them tactically, manage energy consumption, and use your weapons to defeat enemy squads!

## Debugging & Testing

The project includes several testing scenes to isolate and test specific mechanics:
- `test_combat.gd` / `test_combat.tscn`: For testing entity interactions and damage calculation.
- `test_energy_routing.gd`: For validating hex grid links and energy packet distribution.
- `test_garage.gd`: For testing the component equipping UI and logic.
- `test_build.gd`: For testing mech assembly.

**To run a specific test**:
1. Open the `.tscn` file corresponding to the test you want to run.
2. Press `F6` (or click "Play Current Scene" in the top right corner).
3. Check the Output console for debug logs, which will output energy routing status, combat events, and component linking validations.

---

