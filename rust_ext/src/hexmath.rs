use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use std::time::Instant;
use pixbots_core::hex::HexCoord;

// gdext 0.5's Dictionary is generic over key/value type now - VDict is the
// untyped (Variant/Variant) form matching the old Dictionary-of-anything API.
type VDict = Dictionary<Variant, Variant>;

// Validates the whole GDExtension pipeline end-to-end (compiles on Windows,
// loads via .gdextension, callable from GDScript) using the exact same
// neighbor+distance workload already benchmarked standalone in
// rust_poc/hexgrid.rs and in-engine in scripts/debug/RustBenchComparison.gd.
// This is step 1 - proving the toolchain actually works - before porting
// anything that matters gameplay-wise.

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct HexMathBench {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for HexMathBench {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl HexMathBench {
    // Runs the identical neighbor+distance loop as RustBenchComparison.gd's
    // second benchmark, from inside the actual running Godot process (not a
    // standalone rustc binary) - the real, final number for the
    // GDExtension-call-overhead-included comparison.
    #[func]
    fn run_benchmark(&self, iterations: i64) -> VDict {
        let start = Instant::now();
        let mut acc: i64 = 0;
        let mut c = HexCoord::new(0, 0);
        let origin = HexCoord::new(0, 0);
        for i in 0..iterations {
            c = c.neighbor((i % 6) as usize);
            acc += c.distance(&origin) as i64;
        }
        let elapsed = start.elapsed();
        let ns_per_op = elapsed.as_secs_f64() * 1_000_000_000.0 / (iterations as f64);

        let mut result = VDict::new();
        result.set("elapsed_sec", elapsed.as_secs_f64());
        result.set("ns_per_op", ns_per_op);
        result.set("checksum", acc);
        result.set("iterations", iterations);
        result
    }
}
