# KCut — Part thickness investigation notes

Nov 3, 2026 · @Alex

## Context

Nothing is decided yet. These notes record what we found, so we can investigate further areas before choosing changes to KCut, our fork of OpenCutList (OCL).

- **Goal under study:** let a component's dynamic `LenZ` override the thickness OCL lists, only when detect axes (auto-orient) is off. We rarely use detect axes.
- **Test model:** Old Gulph Testbed (mm units): 5,956 component definitions, 29,557 instances, of which OCL treats about 2,716 as parts. The Dynamic Components extension is loaded.
- **Method:** read-only Ruby queries run in SketchUp, using OCL's own bounding-box helper (`BoundingBoxHelper#_compute_faces_bounds`) so the numbers match what OCL computes. Nothing in the model was changed.
- **Simplification:** scale was taken from each instance's own transform only; we confirmed no parts with `lenz` sit inside a scaled parent.

## How OCL computes thickness today

OCL measures faces, not the component's definition bounds, and with detect axes on, thickness is the smallest dimension rather than Z.

1. **Measure** (`_fetch_useful_instance_infos`, `cutlist_generate_worker.rb`): bounding box of the definition's visible faces only. It skips hidden entities, hidden tags and edges, and includes faces in nested groups and in **cut-opening (hole-cutter) children**. Nested components are not included; they become parts of their own. The box is scaled by the whole transform path.
2. **Orient** (`Size3d.create_from_bounds`): with detect axes on, the three dimensions are sorted and the smallest becomes thickness. With it off, or with axes locked by Smart Axes (`orientation_locked_on_axis`), thickness is Z.
3. **Adjust** (about line 387): subtract veneer thickness, divide by `thickness_layer_count`, then match to the material's standard thicknesses.

The raw `instance_info.size` also feeds the part ID hash (`PartDef.generate_part_id`) and edge-banding width (line 551). Any override must be applied where that size is created, not at line 387. Drawings, DXF/SVG export, the 3D view, Smart Axes overlays and final-area detection read real geometry and would not follow an override.

## Finding 1: hole cutters inflate OCL's thickness

The "larger components inside" are cut-opening components (for example the `Prado Single Ful…` cutouts). OCL counts their faces in the board's bounding box, so a cutter that sticks out past the board sets the thickness.

| Component | OCL thickness (mm) | Board's own faces (mm) | LenZ (mm) | Cause |
| --- | --- | --- | --- | --- |
| Stile#2 | 40.5 | 19.05 | 19.05 | 40.5 mm cutter |
| electric walnut panel#4 | 40.5 | 19.13 | 18.44 | 40.5 mm cutter |
| electric walnut panel#5 | 40.5 | 18.44 | 18.44 | 40.5 mm cutter |
| Center Divider #2, #3, #4, #25 | 9.53 | none | 18.44 | Only faces are a 9.5 mm cutter |

- **Phantom parts:** `Center Divider` has no faces of its own, only a nested `Shaker Panel` component and a 9.5 mm cutter. OCL lists the cutter as a 9.53 mm part.
- This affects every axis and works the same with detect axes on or off; it is a measurement issue, not a `LenZ` issue.
- Including cutters in the bounds is deliberate upstream OCL behaviour, so changing it is a behaviour choice.

## Finding 2: LenZ is often stale

Applied blindly, a `LenZ` override fixes 3 of 4 cutter-inflated parts but changes 397 other parts (about 15%) away from their real geometry.

| Outcome of a plain LenZ override | Parts |
| --- | --- |
| No change (LenZ equals OCL) | 2,225 |
| Changes thickness away from real geometry | 397 |
| No `lenz` value | 72 |
| `lenz` is 0 | 19 |
| Fixes a cutter-inflated part | 3 of 4 |

- **Whole value set is stale:** in most of the 397, LenX and LenY are wrong too. `V Drawer Panel#2` is 421 × 350 × 19.05 mm in geometry; its dynamic values say 719 × 413 × 18.44 mm. Formulas such as `parent!DrawerTh` changed but the component was never redrawn.
- **Axis swap:** `Slide Packout#1` geometry is 533 × 31.75 × 50.8 mm; dynamic values are 419 × 50.8 × 31.75 mm, so Y and Z appear swapped.
- **Freshness guard tested:** trust LenZ only when LenX and LenY match geometry (0.05 mm tolerance). It rejects 290 stale parts but still overrides 109, and only 1 of those is a cutter fix.

Parts the guard would still override; for each, which value is right is unknown:

| Component | Count | Geometry Z (mm) | LenZ (mm) | LenZ formula |
| --- | --- | --- | --- | --- |
| Door Plate | 56 | 6.7 | 6.5 | `0.65` |
| Divider walls | 37 | 38.11 | 18.44 | `parent!wallTh` |
| Support Tri | 8 | 20.59 | 18.8 | `parent!slatTh` |
| Island Back Panel | 2 | 19.05 | 18.8 | `0.74` |
| CURVE RADIUS (3 defs) | 3 | 94.9–113.9 | 50.8 | none |
| Curve support bracket | 1 | 16.58 | 18.69 | `0.736"` |
| Island Counter | 1 | 28.58 | 30.0 | none |
| electric walnut panel#5 | 1 | 40.5 (cutter) | 18.44 | `0.726"` |

## Finding 3: other pitfalls, confirmed or ruled out

| Pitfall | Result in test model | Implication |
| --- | --- | --- |
| Values stored as text | Confirmed: 62 parts (102 instances model-wide) | Parse with `to_f` as inches; `to_l` on a string uses model units (mm here) |
| Zero values | Confirmed: 19 parts, e.g. `IF(Hidden, 0, …)` | Never treat 0 as an override |
| Same geometry, different LenZ per copy | Confirmed: 4 definitions (`Slide Packout` 31.75 vs 53.97 mm; `Prado Single Meat Cut` 6 values; `Oil Seperator`; `Slide Packout Left#1`) | Part ID hash must include the override, or rows merge |
| Where values live | Formulas on the definition (4,943 have `_lenz_formula`); values on instances (28,548 of 29,557) | Read instance first, then definition |
| "Has a formula" as the signal | Ruled out: almost every component has one | Need a different opt-in signal |
| `_lenz_units` | Blank everywhere | Not usable |
| `_lenz_nominal` | Present but 0 | Not usable |
| `_lenz_error` | Holds display HTML, not errors | Not usable as an error flag |
| Scaled parent groups | Ruled out: 0 parts with `lenz` inside a scaled parent | Low risk in this model |

## Finding 4: a DC redraw does not fix the stale parts

Redrawing every mismatched component barely changed the numbers: plain-override mismatches fell from 396 to 392, and all 1,307 instances with a mismatched LenX, LenY or LenZ stayed mismatched.

**Method:** `$dc_observers.get_latest_class.redraw(instance, false)` on each of the 1,307 instances, inside one SketchUp operation, measured, then aborted. After the abort the model reported unmodified and every number matched the baseline.

| Measure | Before redraw | After redraw |
| --- | --- | --- |
| Parts OCL sees | 2,716 | 2,724 |
| LenZ equals OCL thickness | 2,226 | 2,238 |
| Plain override changes thickness vs geometry | 396 | 392 |
| Guard rejects as stale | 288 | 284 |
| Guard still overrides | 108 | 108 |
| Cutter-inflated parts | 4 | 4 |
| Definitions with differing LenZ per copy | 4 | 3 |
| Instances with any mismatched Len value | 1,307 | 1,307 |

- **The values aren't stale, the geometry is:** the redraw recalculated each LenZ from its formula and got the same value, but did not resize the part. `Door Plate`: formula `0.65` in the component's own units (`_lengthunits` = CENTIMETERS) gives 6.5 mm; the geometry stays 6.7 mm at scale 1.0. `Divider walls` keeps LenZ 18.44 mm (`parent!wallTh`) against 38.1 mm geometry.
- **Why it doesn't resize is still unknown.** A missing `_lenz_nominal` was ruled out: 1,599 parts that match also lack it (338 mismatched lack it, 57 mismatched have it).
- **Side effects seen:** 76 redraws failed with `undefined method 'name' for nil` (for example `Oil Seperator`, `Blum 9" Tandem`). The redraw also added 8 parts OCL counts, likely from components being made unique.
- **Formula units vary per component:** `_lengthunits` is set per dynamic component (CENTIMETERS, INCHES). Stored Len values are inches regardless.

## Finding 5: formulas only resize parts that store a nominal size

Redrawing all 66 top-level cabinets left every mismatch in place (1,787 mismatched Len values before and after, across 221 definitions). The dynamic component system recomputes the values, but only resizes a part's geometry when that part stores a nominal size (`_len?_nominal`).

**Method:** redrew the 66 top-level dynamic components above the 1,076 mismatched parts, then ran three controlled tests, all in one operation that was then aborted. The model reported unmodified afterwards, and the test changes were gone.

| Test | Part (formula) | Nominal stored | LenZ before → after | Geometry Z before → after |
| --- | --- | --- | --- | --- |
| Cabinet `wallTh` 18.44 → 25.4 mm | Divider walls (`parent!wallTh`) | No | 18.44 → 25.4 mm | 38.11 → 38.11 mm |
| Parent `botth` ×1.5 | Drawer Bottom (`parent!botth`) | No | 12.7 → 19.05 mm | 12.7 → 12.7 mm |
| Parent `wallth` ×1.5 | Drawer Back#23 (`parent!wallth`) | Yes | 12.7 → 19.05 mm | 12.7 → 19.05 mm |

- **No part is sized by instance scale:** all 12,768 formula-driven instances are at scale 1.0. When resizing does happen, it changes the definition's geometry (Drawer Back#23 stayed at scale 1.0).
- **Matches are mostly coincidence:** a part without a nominal matches only because it was modeled at the size its formula gives. Change the formula's inputs and it drifts silently.
- Finding 4's single-part redraw (`redraw(part)`) recomputes that part's own values but does not resize it; resizing is applied by the parent's redraw.

Why the 1,554 unapplied formula values remain:

| Cause | Nominal | No nominal |
| --- | --- | --- |
| Formula result not applied to geometry | 235 | 1,319 |
| No formula; value only records a size | 66 | 80 |
| Formula, but no dynamic parent to apply it | 3 | 55 |
| Value uses full bounds (edges, nested, hidden) | 24 | 0 |
| Cutter inflates OCL | 5 | 0 |

- **The 235 with a nominal are not explained yet.** Several take their size from a sibling component rather than the parent: `Wall Full Top Hangable` (`IB!LenX`, geometry 628 mm vs 382 mm) and `Base Bottom#11` (`BB!LenX - (parent!wallTh*2)`).

## Candidate approaches and open questions

None of these is chosen yet.

- **A. Exclude cutters from size:** ignore cut-opening children when measuring, and skip "parts" with no faces of their own. Fixes the cutter cases without relying on `LenZ`.
- **B. Opt-in LenZ override:** only with detect axes off; needs an explicit signal per component (signal not yet chosen).
- **C. Guarded automatic override:** apply LenZ when LenX/LenY match geometry; still changes 109 parts in this model.
- **D. Warning only:** flag parts where LenZ and geometry disagree, without changing the cut list.

Areas to investigate before deciding:

- [ ] Why does upstream OCL include cut-opening children in the bounds, and what breaks if we exclude them (edges, veneers, final area)?
- [ ] In the stale cases, is the geometry or LenZ the intended size? Spot-check Divider walls, Door Plate and V Drawer Panel#2 by hand.
- [ ] Redraw explained (Findings 4–5): geometry only follows formulas when a nominal size is stored. Why do 235 parts with a nominal still not resize (sibling references like IB!LenX)?
- [ ] What explicit signal should mark a deliberate LenZ override?
- [ ] Is LenZ the total thickness or per layer, and should veneer thickness still be subtracted?
- [ ] How should the 4 definitions with differing LenZ per copy appear in the parts list?

* [ ] Where do the missing nominals come from: how the components were built, copied or made unique? Could they be restored safely, so the formulas drive the geometry again?
* [ ] In each mismatch, which number is the real intent: the formula's or the modeled geometry?
