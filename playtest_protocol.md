# Playtest Protocol - Post Efficiency-Audit + New Features

Everything below was added or changed in this pass. Debug menu (backtick `` ` `` to open) has shortcuts called out where they save you a grind - use them, no need to earn your way to Mythic gear or a specific squad type by hand.

## 0. Fast setup

- Debug menu → **Inventory tab** → "Give MYTHIC Inventory (50x All Mythic)" - instantly gives you Mythic tiles of every type so you can test the new Mythic toggles (Resonator, Shield, Conduit, Actuator) without grinding drops.
- Debug menu → **Spawn tab** → squad dropdown → pick a template by name → "Spawn Selected Squad" - lets you force-spawn "Pierce Escort" or "Amphibious Recon" on demand instead of waiting for the AI to roll them naturally.
- Debug menu → **Player tab** → "Teleport to Garage" - quick way to hop in and out to re-equip mid-test.

There's no wave-skip button, so Rival Challenges (every 10 waves) and the Mythic drop-rate ramp need actual wave progress - say the word if you want a debug wave-jump button added.

## 1. New enemy variants

**Piercing Jammer** (squad template "Pierce Escort" - piercing_jammer + brawler + ambusher)
- Spawn it via debug menu. Visually: dark red, a ring of small spikes on the head instead of a satellite dish (that's the Warden jammer's look).
- Get a PIERCE hit through your shields on an enemy standing near the Piercing Jammer (or on the Jammer itself) - it should NOT execute/cut-in-half, even if your pierce-execution roll should've landed. Walk an enemy out of the aura radius and confirm executions work normally again outside it.
- Confirm it never expires/executes itself, either.

**Diver** (squad template "Amphibious Recon" - diver x2 + scout)
- Spawn it near a water tile (Water map type, or any map with lakes). Visually: teal color, a single fin on the head.
- Watch it path directly across water toward you instead of routing around like every other enemy does.
- It should visibly speed up while crossing water, and never drown.

## 2. Garage additions

**Synergy Codex**
- Garage → look for the "Synergy Codex" button near Swap/Infuse. Confirm all 9 synergies are listed with a color swatch that actually matches their in-game projectile color, and the text reads correctly (no missing descriptions).

**Mythic tile toggles** (equip a Mythic tile of each type - use the debug inventory - then click it in the Garage grid)
- **Resonator**: this one's subtle, it's a passive effect not a toggle. Build a small hex loop where one line (say, straight through E/W) crosses a Resonator that ALSO has a diagonal line (NW/SE or SW/NE) running through it carrying a different element (e.g. one line FIRE, the crossing line RAW/KINETIC). Fire and check: does the RAW/KINETIC line's hit apply a burning tick even though nothing on that line is actually FIRE? That's the "confer effect, not energy" behavior working. Also confirm damage numbers on that line don't jump up (no energy was actually added).
- **Shield Generator**: click the tile, cycle Aegis ↔ Deflector.
  - Aegis: take a big single hit while shields are up - damage taken in one hit should be capped (won't ever blow through a huge chunk of the shield bar in one go).
  - Deflector: let your shield hit 0 from overflow damage - instead of that overflow hitting your HP, you should take zero HP damage and see a burst/ring effect go off in a random direction, damaging anything nearby. Try it both surrounded by enemies (should hurt them) and alone (should just be a "wasted" burst with no HP loss to you either way).
- **Directional Conduit**: click it, cycle Two-Way ↔ One-Way Valve. With Valve on, rotate the conduit (E to rotate) and confirm energy only flows the direction it's pointing - feeding it from the back should dead-end (no output). Two-Way should behave exactly like before (either direction works) - if energy stops flowing on a normal Two-Way conduit, that's a bug, flag it.
- **Actuator**: click it, cycle Velocity → Ember → Balanced.
  - Velocity: noticeably faster movement, but ramming an enemy does less damage than normal.
  - Ember: noticeably slower movement, but ramming hits harder AND sets the target on fire (burning tick).
  - Balanced: normal-ish speed/damage, but a successful ram should knock the target back further than usual, and you should take reduced damage for a brief moment right after.

## 3. Oil Slick hazard

- Play a Desert or Volcano map. Look for dark puddle patches on the ground (sparse, not everywhere).
- Hit one with a FIRE-heavy shot (or lure an enemy to walk it through one, since enemies can trigger it too via their own fire shots). It should ignite - visibly change color/get ember particles - and tick damage to anyone standing in it for a few seconds, then burn out.
- Confirm it goes dormant after burning out and doesn't instantly re-ignite from the next stray spark (should have a brief cooldown).

## 4. Rival Challenges

- Play to wave 10, 20, or 30 (whichever's fastest to reach). A named enemy ("RIVAL: <Name>" floating text) should appear, noticeably larger than normal enemies, roughly matched to your own build strength - it shouldn't feel like a boss-tier bullet sponge, but also shouldn't die in one hit.
- Beat it - confirm you get a guaranteed component drop.
- If it happens to line up with a wave-25/50 megaboss wave, the megaboss should take priority (no rival that wave).

## 5. Mythic drop-rate ramp

- This one's a numbers thing, hard to "confirm" in one sitting - the honest test is just: does Mythic gear (on enemies, and as drops) feel essentially nonexistent in the first few waves, and does it start actually showing up by wave 25-35ish? If you're at wave 40+ and have never once seen an enemy in Mythic-tier gear, that's worth flagging.
- Faster check: debug-spawn a big army repeatedly at a high wave number (play up to wave 30+ first) and watch enemy gear colors - Mythic tiles should occasionally show up as the shiniest/rarest tint.

## 6. General regression pass (things that shouldn't have changed but touch a lot of code)

- Normal combat still feels right: shots land, damage numbers look sane, no console errors spamming.
- Garage: equipping/unequipping tiles, Simulate Energy Flow, Auto-Equip, saving/loading a build all still work.
- Ruins: shoot one down, confirm enemies path across the rubble afterward instead of detouring around a crater that isn't there anymore (this was a specific fix).
- Tutorial (if you haven't dismissed it on this save) still steps through correctly.
- Framerate/responsiveness with a full 80-enemy wave on screen - this is where the efficiency audit should actually be felt, if at all (it was mostly about not wasting cycles, not adding new visible speed).

## What to send back

For anything that misbehaves: what you did, what you expected, what actually happened, and the wave/map type if relevant. Screenshots help but aren't required - a one-line description is usually enough for me to find it in the code.
