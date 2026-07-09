// Pure-Rust proof-of-concept port of Pixbots-G's hex-grid math and the
// procedural component-shape generator (scripts/core/ComponentEquipment.gd's
// generate_procedural_shape/_grow_primitive/_try_add_hex - the "recursive
// grid building" workload named in the original Rust-port wishlist item).
//
// No Godot/GDExtension integration here on purpose - this is step 1 of the
// plan: prove the logic ports cleanly and measure raw execution speed
// before investing in the GDExtension/cross-compilation plumbing (which
// needs to happen on a Windows machine or via cross-compilation - see the
// toolchain discussion). This file is not wired into the build; it's a
// reference artifact from the POC, compiled and run standalone.
//
// Build: rustc -O hexgrid.rs -o hexgrid_bench
// Run:   ./hexgrid_bench
//
// See scripts/debug/RustBenchComparison.gd for the matching in-engine
// GDScript benchmark of the identical algorithm, for a real (not Python
// stand-in) apples-to-apples number.

use std::collections::HashMap;
use std::time::Instant;

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
struct HexCoord { q: i32, r: i32 }

const DIRECTIONS: [HexCoord; 6] = [
    HexCoord { q: 1, r: 0 },
    HexCoord { q: 0, r: 1 },
    HexCoord { q: -1, r: 1 },
    HexCoord { q: -1, r: 0 },
    HexCoord { q: 0, r: -1 },
    HexCoord { q: 1, r: -1 },
];

impl HexCoord {
    fn new(q: i32, r: i32) -> Self { HexCoord { q, r } }
    fn add(&self, other: &HexCoord) -> HexCoord { HexCoord::new(self.q + other.q, self.r + other.r) }
    fn neighbor(&self, direction_idx: usize) -> HexCoord { self.add(&DIRECTIONS[direction_idx % 6]) }
    fn distance(&self, other: &HexCoord) -> i32 {
        let dq = self.q - other.q;
        let dr = self.r - other.r;
        let dz = -dq - dr;
        (dq.abs() + dr.abs() + dz.abs()) / 2
    }
}

struct Rng(u64);
impl Rng {
    fn new(seed: u64) -> Self { Rng(seed ^ 0x9E3779B97F4A7C15) }
    fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13; x ^= x >> 7; x ^= x << 17;
        self.0 = x; x
    }
    fn randi_range(&mut self, n: u32) -> u32 { (self.next_u64() % n as u64) as u32 }
    fn randf(&mut self) -> f64 { (self.next_u64() >> 11) as f64 / ((1u64 << 53) as f64) }
    fn randf_range(&mut self, lo: f64, hi: f64) -> f64 { lo + self.randf() * (hi - lo) }
}

#[derive(Clone, Copy, PartialEq)]
enum Archetype { Line, Hook, Block }

struct ShapeBuilder {
    valid_hexes: Vec<HexCoord>,
    valid_hex_set: HashMap<(i32, i32), bool>,
}

impl ShapeBuilder {
    fn new() -> Self { ShapeBuilder { valid_hexes: Vec::new(), valid_hex_set: HashMap::new() } }

    fn try_add_hex(&mut self, h: HexCoord) -> bool {
        if h.q.abs() > 12 || h.r.abs() > 12 { return false; }
        if self.valid_hex_set.contains_key(&(h.q, h.r)) { return false; }
        self.valid_hexes.push(h);
        self.valid_hex_set.insert((h.q, h.r), true);
        true
    }

    fn grow_primitive(&mut self, attach: HexCoord, archetype: Archetype, budget: i32, rng: &mut Rng) -> i32 {
        let mut added = 0;
        match archetype {
            Archetype::Line => {
                let dir = rng.randi_range(6) as usize;
                let mut cur = attach;
                for _ in 0..budget {
                    cur = cur.neighbor(dir);
                    if self.try_add_hex(cur) { added += 1; }
                }
            }
            Archetype::Hook => {
                let dir = rng.randi_range(6) as usize;
                let bend_at = ((budget as f64 * rng.randf_range(0.3, 0.6)) as i32).max(1);
                let mut cur = attach;
                for _ in 0..bend_at {
                    cur = cur.neighbor(dir);
                    if self.try_add_hex(cur) { added += 1; }
                }
                let turn: i32 = if rng.randf() < 0.5 { 1 } else { -1 };
                let new_dir = (((dir as i32 + turn) % 6 + 6) % 6) as usize;
                for _ in 0..(budget - bend_at) {
                    cur = cur.neighbor(new_dir);
                    if self.try_add_hex(cur) { added += 1; }
                }
            }
            Archetype::Block => {
                let mut frontier: Vec<HexCoord> = vec![attach];
                let mut attempts = 0;
                while added < budget && !frontier.is_empty() && attempts < budget * 20 {
                    attempts += 1;
                    let idx = rng.randi_range(frontier.len() as u32) as usize;
                    let cell = frontier[idx];
                    let d = rng.randi_range(6) as usize;
                    let n = cell.neighbor(d);
                    if self.try_add_hex(n) {
                        frontier.push(n);
                        added += 1;
                    } else if rng.randf() < 0.3 {
                        frontier.remove(idx);
                    }
                }
            }
        }
        added
    }

    fn generate(&mut self, rarity: i32, is_torso: bool, rng: &mut Rng) {
        self.valid_hexes.clear();
        self.valid_hex_set.clear();

        let hex_budget = [10, 18, 28, 48, 72, 100];
        let mut budget_tier = rarity.clamp(0, 4);
        if is_torso { budget_tier += 1; }
        let base_count = hex_budget[budget_tier as usize];

        let start = HexCoord::new(0, 0);
        self.valid_hexes.push(start);
        self.valid_hex_set.insert((start.q, start.r), true);

        let num_primitives = match rarity {
            0 => 1, 1 => 2, 2 => 3, _ => 4,
        };

        let archetypes = [Archetype::Line, Archetype::Hook, Archetype::Block];

        let mut remaining = base_count - 1;
        for p in 0..num_primitives {
            if remaining <= 0 { break; }
            let slots_left = num_primitives - p;
            let budget = (((remaining as f64) / (slots_left as f64)).ceil() as i32).max(2);
            let attach = self.valid_hexes[rng.randi_range(self.valid_hexes.len() as u32) as usize];
            let archetype = archetypes[rng.randi_range(3) as usize];
            let added = self.grow_primitive(attach, archetype, budget, rng);
            remaining -= added;
        }
    }
}

fn main() {
    let iterations: u32 = 100_000;
    let configs: [(i32, bool); 5] = [(2, false), (3, false), (4, false), (3, true), (4, true)];

    let mut rng = Rng::new(12345);
    let mut builder = ShapeBuilder::new();
    let mut total_hexes: u64 = 0;

    let start = Instant::now();
    for i in 0..iterations {
        let (rarity, is_torso) = configs[(i as usize) % configs.len()];
        builder.generate(rarity, is_torso, &mut rng);
        total_hexes += builder.valid_hexes.len() as u64;
    }
    let elapsed = start.elapsed();

    println!("Rust: {} component shapes generated in {:.4}s ({:.2} us/shape, avg {:.1} hexes/shape)",
        iterations, elapsed.as_secs_f64(),
        elapsed.as_secs_f64() * 1_000_000.0 / iterations as f64,
        total_hexes as f64 / iterations as f64);

    let math_iterations: u32 = 5_000_000;
    let start2 = Instant::now();
    let mut acc: i64 = 0;
    let mut c = HexCoord::new(0, 0);
    for i in 0..math_iterations {
        c = c.neighbor((i % 6) as usize);
        acc += c.distance(&HexCoord::new(0, 0)) as i64;
    }
    let elapsed2 = start2.elapsed();
    println!("Rust: {} neighbor+distance ops in {:.4}s ({:.2} ns/op) [checksum {}]",
        math_iterations, elapsed2.as_secs_f64(),
        elapsed2.as_secs_f64() * 1_000_000_000.0 / math_iterations as f64, acc);
}
