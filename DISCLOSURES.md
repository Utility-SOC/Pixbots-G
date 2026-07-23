# Pixbots-G Third-Party Licenses & Disclosures

This project is built using several open-source technologies. Below is a list of the third-party components, their licenses, and specific disclosures regarding their usage.

## 1. Godot Engine
- **License**: MIT License
- **Disclosure**: Pixbots-G is powered by the [Godot Engine](https://godotengine.org/). 
- **Obligation**: The MIT license requires that the copyright notice and permission notice be included in all copies or substantial portions of the Software. (You must include Godot's license in your final game credits).
- **Fulfilled**: Main Menu -> "Credits & Licenses" ([CreditsPanel.gd](scripts/ui/CreditsPanel.gd)) shows this notice in-game, not just here.

## 2. godot-rust (`gdext`)
- **License**: Mozilla Public License 2.0 (MPL-2.0)
- **Usage**: Used in `rust_ext/` to compile the high-performance GDExtension modules.
- **Disclosure & Stickiness**: The MPL-2.0 is a "file-level" copyleft license. 
  - **What this means for you**: You **can** keep your game (and the rest of your custom Rust code) closed-source and commercialize it. 
  - **Your Obligation**: If you modify the source code of the `godot-rust` library *itself*, you must make those specific modifications open-source. Simply *using* the library as a dependency (which is what you are doing in `Cargo.toml`) does not force your game code to be open-source.

## 3. Python 3.x
- **License**: Python Software Foundation License (PSF)
- **Usage**: Used strictly as a build/tooling dependency for scripts like `compile_dialogue.py` and `inject_monologues.py`.
- **Disclosure**: Since Python is a development tool and not bundled/distributed with the compiled game executable, there are no redistribution obligations for players.

## 4. Transitive Rust dependencies (`rust_ext/Cargo.lock`)
Audited 2026-07-23 via `cargo license` against the real lockfile (17 crates
beyond `rust_ext` itself) - not just the one direct `godot = "0.5.4"` entry
in `Cargo.toml`:
- **MPL-2.0** (8): `gdextension-api`, `godot`, `godot-bindings`, `godot-cell`,
  `godot-codegen`, `godot-core`, `godot-ffi`, `godot-macros` - the whole
  godot-rust family, covered by item 2 above.
- **MIT OR Apache-2.0** (6): `glam`, `heck`, `libc`, `proc-macro2`, `quote`,
  `nanoserde`
- **MIT** (2): `nanoserde-derive`, `venial`
- **(Apache-2.0 OR MIT) AND Unicode-3.0** (1): `unicode-ident` (the extra
  Unicode-3.0 component covers Unicode Character Database data tables it
  ships - a standard, permissive, non-copyleft license used across nearly
  every Rust proc-macro crate)
No GPL/AGPL or other strong-copyleft dependencies anywhere in the tree.

## Specific Disclosures
1. **Proprietary Code**: Unless otherwise stated in this repository, all gameplay scripts (`.gd`), configuration files (`.json`), markdown documents, and Rust logic (`rust_ext/src/*`) are the proprietary property of the project owner.
2. **Assets**: All gameplay art, music, and sound effects are generated procedurally at runtime (see the "Purely procedural 2D visuals" ruling and `scripts/audio/ProceduralSynth.gd`) - confirmed 2026-07-23 that no font, audio sample, or image asset files are bundled anywhere in the repository, so there are no third-party asset licenses to track today. If that ever changes (a bundled font, a licensed sample, purchased art), add it here before shipping.
