# Archived attack prototypes

These 10 scripts (AcidBall, ExplosionBlast, FireProjectile, FireResidue,
IceCone, KineticBeam, LightningChain, PierceRay, VampiricBat, VortexSwirl)
predate the current unified `Projectile.gd` hit pipeline. A full-codebase
audit (2026-07-17) confirmed zero references to any of them anywhere in
`scripts/` - `Projectile.gd` reimplements FIRE/ICE/PIERCE/POISON/LIGHTNING/
VAMPIRIC/VORTEX handling internally, and `MortarShell.gd`'s own design
comment notes it spawns a real `Projectile` "so chain lightning arcs,
explosion AoE, vampiric lifesteal... fire from the landing zone with zero
reimplementation" - i.e. these standalone per-element scripts were
superseded rather than removed at the time.

Removed from `scripts/attacks/` on 2026-07-18 and kept here for reference
only. Not part of the active build - nothing in the game loads or
`preload()`s anything in this folder.
