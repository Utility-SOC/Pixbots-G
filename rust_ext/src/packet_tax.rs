use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

type VDict = Dictionary<Variant, Variant>;

// Batches the per-shot tax/jamming/ambush scaling Mech._shoot_impl() and
// HexTile._fire_combined_projectile() used to do inline, one FFI-free
// GDScript loop at a time, per armed weapon mount. A mech firing several
// mounts in one _shoot() call paid this scaling cost (a Dictionary
// iteration + multiply per synergy key, replicated 3x for tax/jamming/
// ambush) once per mount; this collects every ready-to-fire mount's
// (magnitude, synergies, tax, jammed_synergies, ambush_mult) tuple for the
// WHOLE _shoot_impl() call and resolves them all in one batched call,
// mirroring the register/collect/one-call pattern ProjectileManager.gd and
// ProjectileBroadphase.gd already established for the flight-math and
// hit-broadphase ports (see Status.md's Phase 4 section for the profiling
// that led here - this specific arithmetic measured real but modest, so
// this is a "every shred counts" batching win, not expected to be dramatic
// on its own).
//
// Replicates exactly:
//   magnitude *= tax
//   for k in synergies: synergies[k] *= tax
//   for jammed_id in jammed_synergies:            (Mech._apply_synergy_jamming)
//       if synergies.has(jammed_id):
//           suppressed = synergies[jammed_id] * 0.9
//           magnitude = max(0.0, magnitude - suppressed)
//           synergies[jammed_id] *= 0.1
//   magnitude *= ambush_mult
//
// Gameplay logic (which mounts are armed/charged, bank/siphon decisions,
// consolidation buffering, actually constructing and firing a Projectile)
// is untouched - this module is purely "given these raw numbers, what's
// the final scaled packet," same division of labor as every other
// Rust-ported system in this codebase.

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct PacketTaxRs {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for PacketTaxRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

fn get_f(d: &VDict, k: &str) -> f64 {
    d.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0)
}

#[godot_api]
impl PacketTaxRs {
    // `requests`: one Dictionary per ready-to-fire mount this _shoot_impl()
    // call - keys: magnitude (f64), synergies (Dictionary int->float), tax
    // (f64), jammed_synergies (PackedInt32Array, may be empty), ambush_mult
    // (f64).
    // Returns: one Dictionary per request, same order - keys: magnitude
    // (f64), synergies (Dictionary int->float).
    #[func]
    fn batch_scale_packets(&self, requests: Array<Variant>) -> Array<Variant> {
        let mut results: Array<Variant> = Array::new();
        for req_variant in requests.iter_shared() {
            let req: VDict = req_variant.try_to().unwrap_or_default();
            let tax = get_f(&req, "tax");
            let ambush_mult = get_f(&req, "ambush_mult");
            let mut magnitude = get_f(&req, "magnitude") * tax;

            // Dictionary is a reference type across the FFI boundary same as
            // in GDScript - `input_synergies` here shares its backing data
            // with the CALLER's Dictionary (which for a real _shoot_impl()
            // call is the PERSISTENT precalculated packet's synergies dict,
            // reused across every future shot until the next grid recalc).
            // Mutating it in place would silently corrupt that shared state
            // exactly like forgetting packet.copy() would in GDScript - so
            // this only ever READS from input_synergies and builds a brand
            // new `synergies_out` Dictionary for the result, never writing
            // back into the input.
            let input_synergies: VDict = req
                .get("synergies")
                .and_then(|v| v.try_to().ok())
                .unwrap_or_default();
            let mut synergies_out: VDict = Dictionary::new();
            for (key, value) in input_synergies.iter_shared() {
                let scaled = value.try_to::<f64>().unwrap_or(0.0) * tax;
                synergies_out.set(&key, scaled);
            }

            if let Some(jammed) = req
                .get("jammed_synergies")
                .and_then(|v| v.try_to::<PackedInt32Array>().ok())
            {
                for jammed_id in jammed.as_slice() {
                    let key = Variant::from(*jammed_id);
                    if let Some(v) = synergies_out.get(&key) {
                        let current = v.try_to::<f64>().unwrap_or(0.0);
                        let suppressed = current * 0.9;
                        magnitude = (magnitude - suppressed).max(0.0);
                        synergies_out.set(&key, current * 0.1);
                    }
                }
            }

            magnitude *= ambush_mult;

            let mut out: VDict = Dictionary::new();
            let _ = out.insert("magnitude", magnitude);
            let _ = out.insert("synergies", &synergies_out);
            results.push(&out.to_variant());
        }
        results
    }
}
