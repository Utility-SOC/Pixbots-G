use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use std::collections::HashMap;

type VDict = Dictionary<Variant, Variant>;

// Task #33 ("batch homing-target search + vortex pull queries into Rust") -
// backs ProjectileTargetingBatcher.gd, which replaces Projectile.gd's two
// throttled per-projectile PhysicsShapeQueryParameters2D.intersect_shape()
// calls (_find_homing_target, _pull_nearby_items) with batched calls into
// this module. Measured baseline (ProjectileTargetingPerfCheck.gd, 100
// projectiles/60 targets): ~24us/call for homing, ~4us/call for vortex,
// ~32ms/sec of aggregate real physics-server query cost at that population -
// the exact "100+ live projectiles" scenario the code's own pre-existing
// comment already flagged as the actual per-projectile cost driver.
//
// A general radius-query primitive (not two separate modules) - both
// _find_homing_target and _pull_nearby_items reduce to the same underlying
// shape ("which candidate points are within radius R of query point Q"),
// just with different candidate pools and different GDScript-side handling
// of the results (homing picks one target and caches it; vortex applies a
// pull to every hit). Same point-distance-vs-shape-overlap approximation
// tier as separation.rs (mech/loot bodies aren't points, but this is a
// soft-heuristic query, not hit detection) - the actual per-target GAME
// RULES (is_player, vortex immunity/protection, apply_damage dispatch)
// stay in GDScript, same "Rust computes geometry, GDScript owns game
// rules and Node mutation" discipline as every other port this session.
//
// Grid-bucket spatial hash (same idiom as hexgrid_sim.rs/
// projectile_broadphase.rs/separation.rs), but unlike separation.rs's
// fixed radius, query radii vary a lot here (homing's min_dist scales with
// Vampiric/Lightning ratio, vortex's pull radius scales with Vortex ratio
// AND total_power) - candidates are bucketed once at a cell size derived
// from the query set's own median radius, and each query scans however
// many cells its own radius actually needs instead of a fixed 3x3
// neighborhood.

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ProximityQueryRs {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for ProximityQueryRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

fn get_i(d: &VDict, k: &str) -> i64 {
    d.get(k).and_then(|v| v.try_to::<i64>().ok()).unwrap_or(0)
}

fn get_f(d: &VDict, k: &str) -> f64 {
    d.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0)
}

fn get_vec2(d: &VDict, k: &str) -> Vector2 {
    d.get(k).and_then(|v| v.try_to().ok()).unwrap_or(Vector2::ZERO)
}

fn cell_of(pos: Vector2, cell_size: f64) -> (i64, i64) {
    (
        ((pos.x as f64) / cell_size).floor() as i64,
        ((pos.y as f64) / cell_size).floor() as i64,
    )
}

#[godot_api]
impl ProximityQueryRs {
    // `queries`: one Dictionary per request - keys: id (i64), pos (Vector2),
    // radius (f64). `candidates`: one Dictionary per candidate - keys: id
    // (i64), pos (Vector2). Returns one Dictionary per query, SAME ORDER as
    // `queries` - keys: id (i64, echoes the query's own id), hits (Array of
    // {id, dist}, sorted by dist ASCENDING so GDScript can take hits[0] for
    // "closest" or the last element for "furthest" without re-sorting).
    #[func]
    fn batch_radius_query(&self, queries: Array<Variant>, candidates: Array<Variant>) -> Array<Variant> {
        let query_entries: Vec<(i64, Vector2, f64)> = queries
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                Some((get_i(&d, "id"), get_vec2(&d, "pos"), get_f(&d, "radius")))
            })
            .collect();

        let cand_entries: Vec<(i64, Vector2)> = candidates
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                Some((get_i(&d, "id"), get_vec2(&d, "pos")))
            })
            .collect();

        let mut results: Array<Variant> = Array::new();
        if cand_entries.is_empty() {
            for (qid, _, _) in &query_entries {
                let mut out: VDict = Dictionary::new();
                let _ = out.insert("id", *qid);
                let _ = out.insert("hits", &Array::<Variant>::new().to_variant());
                results.push(&out.to_variant());
            }
            return results;
        }

        // Cell size from the query set's median radius - keeps the
        // per-query cell-span reasonable regardless of whether this batch
        // is mostly small homing-range queries or mostly large vortex-pull
        // queries.
        let mut radii: Vec<f64> = query_entries.iter().map(|(_, _, r)| *r).collect();
        radii.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let cell_size = if radii.is_empty() { 150.0 } else { radii[radii.len() / 2].max(32.0) };

        let mut buckets: HashMap<(i64, i64), Vec<usize>> = HashMap::with_capacity(cand_entries.len());
        for (i, (_, pos)) in cand_entries.iter().enumerate() {
            buckets.entry(cell_of(*pos, cell_size)).or_default().push(i);
        }

        for (qid, qpos, radius) in query_entries.iter() {
            let (qcx, qcy) = cell_of(*qpos, cell_size);
            let span = ((*radius / cell_size).ceil() as i64).max(1);
            let mut hits: Vec<(i64, f64)> = Vec::new();
            for dx in -span..=span {
                for dy in -span..=span {
                    let Some(indices) = buckets.get(&(qcx + dx, qcy + dy)) else {
                        continue;
                    };
                    for &i in indices {
                        let (cid, cpos) = cand_entries[i];
                        if cid == *qid {
                            continue; // self-exclusion safety - a query and a candidate sharing an id (e.g. future reuse) never matches itself
                        }
                        let d = (cpos - *qpos).length() as f64;
                        if d <= *radius {
                            hits.push((cid, d));
                        }
                    }
                }
            }
            hits.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());

            let mut hits_arr: Array<Variant> = Array::new();
            for (cid, d) in hits {
                let mut h: VDict = Dictionary::new();
                let _ = h.insert("id", cid);
                let _ = h.insert("dist", d);
                hits_arr.push(&h.to_variant());
            }
            let mut out: VDict = Dictionary::new();
            let _ = out.insert("id", *qid);
            let _ = out.insert("hits", &hits_arr.to_variant());
            results.push(&out.to_variant());
        }
        results
    }

    // Homing-target-search candidate: batch_radius_query's full sorted
    // hits-array-per-query is real, unnecessary FFI/marshalling overhead
    // when the caller only ever consumes ONE result (closest or furthest) -
    // a same-process A/B (ProjectileTargetingABCheck.gd) measured the
    // full-hits-array version 103% SLOWER than the old unbatched per-
    // projectile physics queries for exactly this reason. This returns only
    // the single best match per query - no hits array, no per-candidate
    // Dictionary allocation for anything that isn't the winner.
    //
    // `queries`: one Dictionary per request - keys: id (i64), pos
    // (Vector2), radius (f64), prefer_furthest (bool, default false).
    // `candidates`: same as batch_radius_query. Returns one Dictionary per
    // query, SAME ORDER as `queries` - keys: id (i64, echoes the query's
    // own id), found (bool), best_id (i64, meaningful only if found),
    // dist (f64, meaningful only if found).
    #[func]
    fn batch_find_best(&self, queries: Array<Variant>, candidates: Array<Variant>) -> Array<Variant> {
        let query_entries: Vec<(i64, Vector2, f64, bool)> = queries
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                let prefer_furthest = d.get("prefer_furthest").and_then(|v| v.try_to::<bool>().ok()).unwrap_or(false);
                Some((get_i(&d, "id"), get_vec2(&d, "pos"), get_f(&d, "radius"), prefer_furthest))
            })
            .collect();

        let cand_entries: Vec<(i64, Vector2)> = candidates
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                Some((get_i(&d, "id"), get_vec2(&d, "pos")))
            })
            .collect();

        let mut results: Array<Variant> = Array::new();
        if cand_entries.is_empty() {
            for (qid, _, _, _) in &query_entries {
                let mut out: VDict = Dictionary::new();
                let _ = out.insert("id", *qid);
                let _ = out.insert("found", false);
                results.push(&out.to_variant());
            }
            return results;
        }

        let mut radii: Vec<f64> = query_entries.iter().map(|(_, _, r, _)| *r).collect();
        radii.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let cell_size = if radii.is_empty() { 150.0 } else { radii[radii.len() / 2].max(32.0) };

        let mut buckets: HashMap<(i64, i64), Vec<usize>> = HashMap::with_capacity(cand_entries.len());
        for (i, (_, pos)) in cand_entries.iter().enumerate() {
            buckets.entry(cell_of(*pos, cell_size)).or_default().push(i);
        }

        for (qid, qpos, radius, prefer_furthest) in query_entries.iter() {
            let (qcx, qcy) = cell_of(*qpos, cell_size);
            let span = ((*radius / cell_size).ceil() as i64).max(1);
            let mut best: Option<(i64, f64)> = None;
            for dx in -span..=span {
                for dy in -span..=span {
                    let Some(indices) = buckets.get(&(qcx + dx, qcy + dy)) else {
                        continue;
                    };
                    for &i in indices {
                        let (cid, cpos) = cand_entries[i];
                        if cid == *qid {
                            continue;
                        }
                        let d = (cpos - *qpos).length() as f64;
                        if d > *radius {
                            continue;
                        }
                        let better = match best {
                            None => true,
                            Some((_, bd)) => if *prefer_furthest { d > bd } else { d < bd },
                        };
                        if better {
                            best = Some((cid, d));
                        }
                    }
                }
            }

            let mut out: VDict = Dictionary::new();
            let _ = out.insert("id", *qid);
            match best {
                Some((cid, d)) => {
                    let _ = out.insert("found", true);
                    let _ = out.insert("best_id", cid);
                    let _ = out.insert("dist", d);
                }
                None => {
                    let _ = out.insert("found", false);
                }
            }
            results.push(&out.to_variant());
        }
        results
    }
}
