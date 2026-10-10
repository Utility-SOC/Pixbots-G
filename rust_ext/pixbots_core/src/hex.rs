//! Axial hex coordinates (the grid every energy simulation runs on). Pure maths, no engine types.

#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub struct HexCoord {
    pub q: i32,
    pub r: i32,
}

/// Same direction order as `HexCoord.get_direction_offsets()` in GDScript (index 0 = +q, then clockwise).
pub const DIRECTIONS: [HexCoord; 6] = [
    HexCoord { q: 1, r: 0 },
    HexCoord { q: 0, r: 1 },
    HexCoord { q: -1, r: 1 },
    HexCoord { q: -1, r: 0 },
    HexCoord { q: 0, r: -1 },
    HexCoord { q: 1, r: -1 },
];

impl HexCoord {
    pub const fn new(q: i32, r: i32) -> Self {
        Self { q, r }
    }

    pub fn neighbor(&self, dir: usize) -> HexCoord {
        let d = DIRECTIONS[dir % 6];
        HexCoord { q: self.q + d.q, r: self.r + d.r }
    }

    pub fn distance(&self, other: &HexCoord) -> i32 {
        let dq = self.q - other.q;
        let dr = self.r - other.r;
        let dz = -dq - dr;
        (dq.abs() + dr.abs() + dz.abs()) / 2
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn neighbors_are_one_step_away() {
        let o = HexCoord::new(3, -2);
        for d in 0..6 {
            assert_eq!(o.distance(&o.neighbor(d)), 1);
        }
    }

    #[test]
    fn opposite_directions_cancel() {
        let o = HexCoord::new(0, 0);
        for d in 0..6 {
            assert_eq!(o.neighbor(d).neighbor(d + 3), o);
        }
    }

    #[test]
    fn direction_index_wraps() {
        let o = HexCoord::new(1, 1);
        assert_eq!(o.neighbor(7), o.neighbor(1));
    }

    #[test]
    fn distance_is_symmetric_and_hex_shaped() {
        let a = HexCoord::new(0, 0);
        let b = HexCoord::new(2, -1);
        assert_eq!(a.distance(&b), b.distance(&a));
        assert_eq!(a.distance(&HexCoord::new(2, 2)), 4);
    }
}
