use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use std::time::Instant;

// Validates the whole GDExtension pipeline end-to-end (compiles on Windows,
// loads via .gdextension, callable from GDScript) using the exact same
// neighbor+distance workload already benchmarked standalone in
// rust_poc/hexgrid.rs and in-engine in scripts/debug/RustBenchComparison.gd.
// This is step 1 - proving the toolchain actually works - before porting
// anything that matters gameplay-wise.

#[derive(Copy, Clone)]
struct HexCoord {
    q: i32,
    r: i32,
}

const DIRECTIONS: [HexCoord; 6] = [
    HexCoord { q: 1, r: 0 },
    HexCoord { q: 0, r: 1 },
    HexCoord { q: -1, r: 1 },
    HexCoord { q: -1, r: 0 },
    HexCoord { q: 0, r: -1 },
    HexCoord { q: 1, r: -1 },
];

impl HexCoord {
    fn neighbor(&self, dir: usize) -> HexCoord {
        let d = DIRECTIONS[dir % 6];
        HexCoord { q: self.q + d.q, r: self.r + d.r }
    }
    fn distance(&self, other: &HexCoord) -> i32 {
        let dq = self.q - other.q;
        let dr = self.r - other.r;
        let dz = -dq - dr;
        (dq.abs() + dr.abs() + dz.abs()) / 2
    }
}

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
    fn run_benchmark(&self, iterations: i64) -> Dictionary {
        let start = Instant::now();
        let mut acc: i64 = 0;
        let mut c = HexCoord { q: 0, r: 0 };
        let origin = HexCoord { q: 0, r: 0 };
        for i in 0..iterations {
            c = c.neighbor((i % 6) as usize);
            acc += c.distance(&origin) as i64;
        }
        let elapsed = start.elapsed();
        let ns_per_op = elapsed.as_secs_f64() * 1_000_000_000.0 / (iterations as f64);

        let mut result = Dictionary::new();
        result.set("elapsed_sec", elapsed.as_secs_f64());
        result.set("ns_per_op", ns_per_op);
        result.set("checksum", acc);
        result.set("iterations", iterations);
        result
    }
}
