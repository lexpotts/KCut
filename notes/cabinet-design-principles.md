# Cabinet DC design principles and the KCut core-box scaling plan

Surveyed 2026-11-05 on `Old Gulph Testbed` (read-only, model left unmodified).
Raw dump: 36k lines of formulas for every top-level DC type (Base Cabinet ×24,
Curved Cabinet ×4, Wall Cabinet, Full End Panel, Complete Toe Kick, Rail …).

## 1. Patterns the existing cabinets use

### 1.1 Sibling "space" boxes (spatial references)
A cabinet's parts are sized from invisible sibling boxes, not from the cabinet
itself. Formulas refer to them by name (`BB!`, `IB!`, `REV BOX!`, `FB!`):

| Box | Role | Derived from |
|---|---|---|
| `Cab Bounding Box` (BB) | the carcass envelope, **the real size driver** | `lenx = parent!lenX`, but leny/lenz have no formula (see §2.1) |
| `INNER BOUNDS` (IB) | interior volume: BB minus walls, toe, back, door inset | BB, wallTh, toeH, backTh, innerSetback |
| `Box Opening` | face-frame opening | BB, FFW, FFH, rev |
| `REVEAL INNER BOX` (REV BOX) | door/drawer-face envelope after reveals | BB, revLeft/Right/Top/Bot, inset, FF |
| `FF Bounding Box` | face frame; hidden when `FF=0` | BB, FFTH |
| `Door Face Bounding Box`, `Drawer Bounding Box` | the same idea, one level down | parent |

Generalized: **a box = parent box − named insets on 6 sides, + a hidden flag.**
Reveals are just insets: `revLeft = revHalf + revHalf*adjCabLeft` (a full reveal
when there's no neighbour cabinet, a half when there is).

### 1.2 Features that disappear when zeroed
- `notoe = IF(OR(ToeRecess=0, ToeH=0),1,0)`; `toedepth = IF(toeRecess<>0, …, 0)`.
- Toe cutters (`Toe Hole Outer/Inner/Bot/Front`) use `hidden` and collapse to 0.
- `Cab Toe Packout`: `hidden = OR(NoBottom, toeH=0, NOT(isFlush))`,
  `lenz = IF(Hidden,0,…)`.
- `BackDadoD = (wallTh/2)*BackIntoSides`: a boolean multiplied into a dimension.

Generalized: **every optional feature = (enable flag) × (size)**. A size of zero,
or the flag off, means hidden and zero-sized, so the feature drops out of the cutlist.

### 1.3 Operations are cutting components
Pilot holes, shelf-pin and slide holes (`Multipurpose Holes`), biscuits
(`Biscuit 20 Locator`), `JOINT`, the hinge cup (`Hinge Door Plate`) and the toe
notches are all `cuts_opening` components that live inside the part they machine.

### 1.4 Objects that bring their own cutters
The `Blum Overlay Hinge` carries a `Hinge Door Plate` cutter; `ADJ Shelf` carries
`FIX` and pins; the `V Door Face` carries bumper cutters. Dropping the hardware in
brings its machining with it.

### 1.5 Chained cutters (child cuts grandparent)
`Pilot Hole Array` (cuts) → `Pilot Holes` (cuts) → `cut hole` (cuts). Each level
is a glue/cut component, so the innermost hole cuts through to the panel two
levels up. SketchUp only cuts the face a cutter is glued to, which is why each
level has to be a cutter.

### 1.6 Joints and scaling
`JOINT`, `Pilot Hole Array` and the hinges set `scaletool` (92/124/63), which
locks some scale handles. The joint length follows the parent
(`lenx = parent!lenX - jointPad*2`) and the cross-section stays fixed
(`leny = wallTh - backSub`). Generalized: **a joint stretches along its edge
and keeps its profile.**

### 1.7 Repeated features
```
copies   = FLOOR(L/minSpacing, 1)
spacing  = (L - minSpacing*copies)/(copies+1) + minSpacing
x        = copy*spacing
```
Shelf pins snap to a 32 mm grid: `ROUND((userZ-start)/interval)*interval+start`.
Hinges snap to the nearest system hole the same way.

## 2. Errors found

### 2.1 Cabinet Len and BB have drifted apart (25 of 29 cabinets)
`Cab Bounding Box` has `lenx = parent!lenX` but **no formula on leny/lenz**, so
depth and height come from whatever SketchUp scaling last did to BB. The
cabinet's own `lenx/leny/lenz` (what the DC dialog and KCut show) no longer
describe the carcass. Examples (cabinet L×D×H vs BB):

| Cab # | Cabinet | BB |
|---|---|---|
| 22 (and 23, 24, 26, 27, 28) | 15.5 × 18 × 39.23 | 16.5 × 12.25 × 39.25 |
| 36 | 32 × 13.25 × 33.5 | 46 × 12.37 × 33.67 |
| 14 | 31 × 25.25 × 34.25 | **18** × 24.5 × 34.82 |
| 29 | 31.5 × 25.25 × 34.25 | 31.5 × 24.5 × **23.62** |
| 31 | 31.5 × 25.25 × 21.75 | 31.5 × 24.5 × **72.4** |
| Curved 1 | 32 × 18 × 34.83 | 17.24 × 17.25 × 34.83 |

Even the BB `lenx` disagrees with its own `parent!lenX` formula, which means the
cabinet was scaled and never redrawn. Only Curved 15/18/22 are consistent.

### 2.2 Bounds include things outside the core box
Cabinets #29 and #31 have model bounds about 73" tall. Scaling them with SketchUp's
Scale tool scales against that envelope, not the carcass. This is the problem you
described: open drawers or hardware sticking out change the scale reference.

### 2.3 Repeat spacing doesn't reach the end
With `copies+1` holes over `copies` gaps, dividing the leftover by `copies+1`
leaves the last hole `leftover/(copies+1)` short of the end. For example, Back pilot
holes: L = 32.216, last hole at 32.173. The intent seems to be either holes at both
ends (`spacing = L/copies`) or margins equal at both ends. Pick one per feature.

### 2.4 Smaller inconsistencies
- Left End `botrry` subtracts `BB!Y`; Right End doesn't. Left End `shelfpinend`
  reads `IB!`; Right End reads `parent!`.
- `rrsty` evaluates to −0.75 (back stretcher behind the end panel).
- `Cab Number Display` has `lenx = … *2.54`, a unit mix-up baked into a formula.
- A hinge on cab 22 has `adjoptionholenum = -2`: it snapped below the first system hole.
- 76 redraws already fail with `undefined method 'name' for nil` (CLAUDE.md).

## 3. Plan: KCut core-box scaling

The goal is to scale a **core box** owned by KCut, never SketchUp's bounds, and
to drive everything else from formulas.

1. **Core box = `Cab Bounding Box`** (already present). KCut makes its
   lenx/leny/lenz the single source of truth and writes the same values to the
   cabinet's `lenx/leny/lenz`, so the two can't drift.
2. **KCut Scale tool** (`tool/core_scale_tool.rb`): it draws grips on the core
   box faces only, ignoring geometry outside it (open drawers, hinges, cutters).
   Dragging sets the new L/D/H (with VCB numeric entry and snap to standard
   widths) and moves the origin when dragging −X/−Y/−Z faces. Then it sets the
   attributes and calls `redraw`. No `Transformation.scaling` is ever applied
   to the instance, so nested parts larger than the box behave the same as
   smaller ones.
3. **Repair command** "Sync cabinet size from core box": a one-time fix for
   §2.1. Choose which side wins (BB or cabinet attributes) per cabinet, and
   preview a diff first.
4. **Lint panel** in the KCut UI: lists cabinets where Len≠BB, instances with
   non-unit scale, repeated features whose spacing misses the end, and redraw
   errors.
5. **Feature library helpers** (Ruby, then Smart Draw UI): `add_space_box(parent,
   insets)`, `add_optional_feature(flag, size)`, `add_cutter(target, chain:)`,
   `add_repeat(len, min_spacing, mode: :ends|:centered)`. Each writes the DC
   formulas above, so the result is still a plain DC that other SketchUp users can open.

Open decisions for Alex:
- For §2.1, which wins: the current BB geometry (what's drawn) or the cabinet attributes?
  I'd suggest BB, since parts are built from it.
- §2.3 repeat mode: holes at both ends, or equal margins?
- Should the scale tool redraw on every drag frame or only on release? DC redraw is slow.
  I'd suggest a ghost box while dragging and one redraw on release.

## 4. Decision and first implementation (2026-11-05)

**Alex: the bounding box wins.** The drawn `Cab Bounding Box` is the cabinet's
size. The cabinet's LenX/Y/Z are a stale record. They are often the overall
envelope including doors or drawers, e.g. depth 25.25 against a 24.5 carcass.

`utils/core_box_utils.rb` (`CoreBoxUtils`), test `TC_Ladb_Utils_CoreBoxUtils` (11 tests, passing):
- `core_box`, `core_size` (from the box geometry), `drift`, `sync_from_core_box`.
- `resize(cabinet, [x,y,z], anchor:)`: sets the cabinet's and core box's Len,
  sizes the core box geometry, moves the origin for anchored faces, then
  redraws. The cabinet instance is never scaled.

Learned on cab 14 (aborted operation):
- The DC extension evaluates `parent!LenX` as the **definition's
  `_lenx_nominal` × the instance scale**. Writing the instance `lenx` alone is
  undone by redraw, so `resize` writes the definition (after `make_unique`).
- Redraw does **not** resize the core box geometry (no formula on leny/lenz),
  so `resize` sets the box's scale itself.
- 18×24.5×34.82 → 24×20×30: ends, back, stretchers, bottom, inner bounds,
  reveal box and drawer face all follow. Redraw takes about 6.5 s per cabinet.
- Model-wide: 41 components have a core box and 38 have drifted. 9 Full End
  Panels have no Len attributes at all; cabs 29 and 32 have a 73" core box
  (tall units recorded as 34.25 / 21.75).

Scale tool (`tool/core_scale_tool.rb`, `CoreScaleTool`), test
`TC_Ladb_Tool_CoreScaleTool` (8 tests, passing):
- Open it from right-click > KCut > Resize Cabinet (Core Box), or from the
  Extensions > KCut menu (then click a cabinet). Grips sit on the 6 core-box faces.
- Press-drag-release or click-move-click. An orange dashed preview box shows
  while dragging, and one DC redraw runs on release, as one undo step. The
  opposite face stays put. Sizes snap to 1/16", with a 1" minimum.
- Measurements box: type a length for the hovered or last grip's axis, or
  "W,D,H" (an empty value keeps that axis).
- Right-click > KCut > Sync Size from Core Box on drifted cabinets.
- Not yet exercised by hand in SketchUp: the tool's own commit path changes
  the model, so it wasn't run on the test model. Menu labels are hardcoded
  English (no i18n/gulp rebuild needed).

Not done yet: a check panel in the KCut dialog listing drifted cabinets, and the
§2.3 and §2.4 formula fixes.
