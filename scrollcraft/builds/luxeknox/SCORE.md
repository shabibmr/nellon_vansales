# The Score: LuxeKnox

## 1. Selected Grammar: Continuous World (`worldflight`)

The page is constructed as **one unbroken architectural flight** through LuxeKnox. 
- **Mechanism:** `data-sc-mode="worldflight"`, one fixed stage (`data-sc-world`), one copy layer (`data-sc-world-copy`), and a single spacer (`data-sc-spacer`).
- **No act blocks, no section seams, no unsticking stages.**
- **Navigation:** An architectural HUD sector radar fixed at top-right/center with real-time waypoint coordinates (`AZIMUTH`, `LEVEL 01–05`, `SECTOR NAME`).
- **Arrival / Hero:** The Obsidian Monolith Cold Open with Neon Blade Ignition.
- **Close:** The Black Titanium Keycard resting in private vault downlight with interactive biometric tier selection.

---

## 2. The Signature Move: "Kinetic Architecture Assembly"

As the visitor scrolls into **Zone 7 (The Assembly)**, the surrounding architectural environment responds physically:
- Massive brutalist concrete louvers pivot 90° from vertical baffles into horizontal light canopies.
- Overhead neon light tracks energize and sweep across the ceiling grid.
- Custom biomechanical gym machines assemble from exploded CAD wireframe vectors into monolithic milled titanium.
- Pointer position (`--sc-mx`, `--sc-my`) controls inertial spatial tilt across 3 distinct parallax depth planes.

---

## 3. Fingerprint Gate: 6-Dimension Uniqueness Check

The plan is evaluated against the 12 existing builds in `FINGERPRINTS.md`:

| Dimension | `descent` | `orrery` | Prior Filmic Builds (`perkform`, etc.) | **LuxeKnox (This Build)** | Cleared? |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Grammar** | Continuous world | Continuous world | Filmic one-shot / Editorial / Poster | **Continuous world** | Distinct from 10/12 |
| **2. Nav Treatment**| Left-edge depth gauge | Bottom-left bearing dial | Fixed minimal bar (wordmark + 1 CTA)| **Top-Center Architectural HUD Radar & Sector Key** | **Distinct from ALL** |
| **3. Hero Device** | Dawn sky band, 0m depth | Model globe push-in, large h1 | Full-bleed video scrub, lead corner | **Obsidian Monolith with Neon Blade Ignition** | **Distinct from ALL** |
| **4. Sequence Shape**| 9 legs (8.18vh) | 10 legs (11.97vh) | 6–7 acts, 13.6–13.8vh | **8 Waypoint Zones, 10.4vh film / 11.4vh spacer, Peak owns 2.4vh** | **Distinct from ALL** |
| **5. Close Pattern**| Ascent to surface blue, plate | Return to workbench, card | Pinned 1.15vh spotlight + magnet CTA | **Vault Arrival: Floating Black Titanium Card with Biometric Tier Selector** | **Distinct from ALL** |
| **6. Signature Move**| The dark that answers (lamp)| Elsewhere field (streak freeze) | None / Accord / Split-flap / Heatprint | **Kinetic Architecture Assembly (Wall pivot + machine assembly)** | **Distinct from ALL** |

**Result:** Differs from `descent` on 5 of 6 dimensions. Differs from `orrery` on 5 of 6 dimensions. Differs from all other 10 builds on 5 or 6 dimensions. **Gate Passed.**

---

## 4. The Waypoint Score & Pacing

| Zone / Waypoint | Weight (`data-sc-w`) | Linger (`data-sc-linger`) | Device / Scene Mechanism | Energy Level |
| :--- | :--- | :--- | :--- | :--- |
| **1. Atrium** | `1.00vh` | `0.30` | The Monolith: Dark void, obsidian monolith, neon ignition pulse | Low / Awe |
| **2. The Blade** | `1.10vh` | `0.15` | Architectural Gateway: Dual portal slabs open, gold/cyan light rays | Rising / Wonder |
| **3. Crucible** | `1.10vh` | `0.20` | Philosophy: Monolithic concrete pillars with locked typography | Calm / Focus |
| **4. The Forge** | `1.20vh` | `0.22` | Training Arena: Biomechanical rigs, Olympic platforms, specular steel | Rising / Tension |
| **5. The Vault** | `1.20vh` | `0.25` | Hydrothermal Sanctum: Deep basalt pools, steam ribbons, amber wash | Low / Pure Luxury |
| **6. Vanguard** | `1.10vh` | `0.20` | Master Trainers: High-contrast chiaroscuro silhouettes, discipline tags | Building / Respect |
| **7. Assembly (PEAK)**| **`2.40vh`** | `0.45` | **The Signature Move:** Full spatial transformation, louver rotation, machine assembly | **MAX INTENSITY** |
| **8. Sanctum** | `1.30vh` | `0.35` | Vault Arrival: Black Titanium Keycard, membership selector, final CTA | Calm Resolve |

- **Total Segment Weight:** `10.40vh`
- **Total Spacer Height:** `11.40vh` (Segment sum + 1.0vh terminal dwell)
- **Peak Ownership:** `2.40vh` (~23% of total travel, double the weight of any other zone).

---

## 5. Token Philosophy & Design Floor

```css
:root {
  --sc-canvas: #040608;          /* Deep void black */
  --sc-surface: #0B0F15;         /* Brutalist graphite */
  --sc-surface-lift: #141A23;    /* Milled titanium */
  --sc-ink: #F2F5F8;             /* Pure platinum */
  --sc-ink-soft: #8492A6;        /* Architectural concrete */
  --sc-accent-gold: #D4AF37;     /* Liquid gold / brass */
  --sc-accent-cyan: #00F0FF;     /* Tron laser cyan */
  --sc-accent-emerald: #10B981;  /* Biometric pulse */
  
  --sc-font-display: "Cinzel", "Syne", "Inter", -apple-system, sans-serif;
  --sc-font-text: "Plus Jakarta Sans", "Inter", sans-serif;
  --sc-font-mono: "JetBrains Mono", monospace;
}
```
