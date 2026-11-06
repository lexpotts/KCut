# KCut framework architecture (draft)

2026-11-05 · proposal, not decided. Covers the problems in
`notes/feature-list.md` with one model so new features plug in instead of
forcing refactors.

## The one idea

**The recipe is the source of truth; geometry is a disposable cache.**

Today a part *is* its geometry: cutters, DC formulas and painted faces all live
inside SketchUp entities, so behavior gets lost when SketchUp copies or makes
things unique. Instead, every KCut object stores a small, versioned **recipe**
(parameters + an ordered list of features) as data. A **regenerator** rebuilds
the geometry from the recipe whenever an input changes. Edit the recipe, never
the geometry.

```
            ┌─────────────── pure Ruby (no SketchUp; runs anywhere) ───────────────┐
 Recipe ──► │ Scope resolve ─► Feature.evaluate ─► Ops (data) ─► Validate / Report │
 (attrs)    │  (variables)      (per type)          cut/bore/      cutlist, BOM,   │
            │                                       sweep/place    edge checks     │
            └──────────────────────────────┬─────────────────────────────────────┘
                                           ▼
                           SketchUp adapter (thin): build geometry,
                           Booleans, tags, observers, undo
```

## Layers

### 1. Geometry kernel — pure Ruby, no SketchUp — `kcut/geom/`
2D/3D math in plain Ruby objects, testable outside SketchUp on Mac and Windows.
- `ArraySpacing`: count/positions from length + mode (#13). **Built.**
- `Polygon`: point-in-polygon, distance to edge, inward offset of outlines with
  arcs (#11 banding offset, #14 edge awareness, #15 curve stock).
- `Profile`: parametric 2D profiles, i.e. router bits, fillet radius (#4).
- `Arc`/`Ring`: curved-part math: blank size, stacked-ring layers (#15).

### 2. Parameters and scope — `kcut/core/scope.rb` — (#3) **Built.**
A **scope chain** follows the instance path: part → … → cabinet → project
(model root). Lookup finds the nearest scope that defines a name, so a value
set on the project is visible deep inside every cabinet, and a cabinet can
override it for its own children. Named references (`@cab12.toe_kick`) reach
across structures. Values can be literals or expressions; expressions use OCL's
existing safe `FormulaParser`. Cycles are detected.

Scopes are read from a `kcut` attribute dictionary (instance first, then
definition) and from the model's own dictionary for the project. Dynamic
Component values are readable as a fallback, so existing DC models keep working.

### 3. Features — `kcut/core/feature.rb` — **Built (records + registry).**
A feature is `{ type, id, params, anchor, scope }`:
- `type`: registered kind (`bore`, `pocket`, `slot`, `boolean_cut`, `fillet`,
  `edge_profile`, `hinge`, `array`, `banding`, `annotation`, …).
- `params`: values or expressions resolved through the scope chain.
- `anchor`: the host face the feature sits on (host path + plane in host
  coordinates). Motion is limited to that plane (#2).
- `scope`: **`:definition` (shared by every copy) or `:instance` (this copy
  only)**. Explicitly choosing where data lives fixes #10 and #12: a shared biscuit slot
  is one definition-level feature; the board inside one shelf gets
  instance-level banding without touching the other shelves.

Each type implements `evaluate(params, ctx) → [Op]` (pure). Ops are plain data:
`Cut(profile, plane, depth|through)`, `Bore(center, dia, depth)`,
`Sweep(profile, path)`, `Place(catalog_id, transform)`,
`Annotate(kind, geometry, tag)`, `Band(edge_ids, material)`.
New features = new type + evaluate. Nothing else changes.

### 4. Regenerator — SketchUp adapter — `kcut/sketchup/` (next)
- Builds base part + applies ops into a managed child group (`KCut generated`)
  flagged so KCut and OCL know it's a cache.
- **Booleans are never permanent.** The part's base shape is kept untouched
  (as recipe data, or as a hidden base group). Cuts are applied only to the
  generated copy. On any change (resize, moved cutter, new param) the copy
  is thrown away and rebuilt as base shape + all cuts, in order. Removing a
  feature removes its cut; resizing never leaves stale holes or broken
  faces. Cutters stay editable objects/records, never consumed.
- **Booleans:** through cuts on all faces, back faces and nested geometry
  (#1). Use the Solid Tools API where present (Pro); fall back to KCut's own
  2D-profile + push/pull for prismatic cuts (most CNC ops are prismatic).
- **Arrays apply their ops to every copy** because copies come from
  re-evaluating the recipe, not from duplicating geometry (#13).
- **Dirty tracking:** recipes carry a hash of their resolved inputs; only
  hosts whose hash changed regenerate. One `start_operation(…, true)` per edit
  keeps undo clean. This is the main performance lever.
- **Detail levels:** hardware and display-only geometry use simplified meshes;
  cut geometry stays exact. Curve segment count comes from a tolerance, not a
  fixed number.

### 5. Catalog and BOM — `kcut/catalog/` (#5, #8, #9)
- Catalog items are data files (JSON): dimensions, adjustment ranges, mounting
  pattern (e.g. hinge cup 35 mm @ 22.5 mm, plate holes on 32 mm), suppliers
  with price, URL and lead time, and refresh date.
- A `Place` op references `catalog_id`, so the model holds no copied prices.
- BOM collector walks recipes, counts catalog items + sheet goods + banding
  length, and feeds the existing OCL estimate (builds on hardware unit price
  `ce8471a42` and single-item reporting `b6b1d3b04`).
- Price/lead-time refresh is a separate, explicit step per supplier.

### 6. Presentation (tags/LayOut) — `kcut/present/` (#6, #7)
- One **tag scheme** (`KCut/Door Swing`, `KCut/Drawer Pullout`,
  `KCut/Fronts`, …). `Annotate` ops land in their own group carrying the tag;
  raw edges inside stay Untagged (pending the LayOut tag test).
- LayOut-side text and scale use the LayOut Ruby API later; SketchUp only
  exports anchor points + data, not 3D text.

## How this resolves each problem

| # | Problem | Resolved by |
|---|---|---|
| 1 | Cuts only on one face | `Cut` op + regenerator Booleans |
| 2 | Attach to group faces, constrained motion | Feature `anchor` (host path + plane) |
| 3 | Variables only one level up | Scope chain |
| 4 | No parametric fillet/profile | `Profile` + `Sweep` op |
| 5 | Doors/hinges/32 mm | `hinge` feature + catalog mounting data + `ArraySpacing` grid snap |
| 6–7 | Tags/LayOut | `Annotate` op + tag scheme |
| 8–9 | Catalog, BOM | `Place(catalog_id)` + BOM collector |
| 10 | Copies lose shared behavior | Definition-scoped features + instance params; no DC make-unique |
| 11 | Banding on curves | `Polygon` inward offset + `Band` op |
| 12 | Banding hits all copies | Instance-scoped `Band` |
| 13 | Arrays | `ArraySpacing` + ops re-evaluated per item |
| 14 | Edge awareness | `Polygon` distance/contains against true outline |
| 15 | Curves | `Ring` math + build-method switch |
| — | WYSIWYG sizes | Ops are exact; banding offset; thickness decisions per material |
| — | Performance | Dirty hashing, partial regen, detail levels |
| — | Mac + Windows | Pure kernel tested with plain minitest; adapter tested with TestUp on both |

## Rules that keep refactors away
1. Kernel and core never `require` SketchUp. Only `kcut/sketchup/` does.
2. Recipes are versioned (`"v": 1`); readers migrate old versions on load.
3. Ops are the only interface between features and geometry.
4. Each stored value lives in exactly one place: definition *or* instance, never copied.
5. Coexist with DC/OCL: read DC values, don't fight DC redraw; migrate
   models gradually.

## Testing
- `test/TC_Ladb_KCut_*.rb` run under TestUp in SketchUp **and** under plain
  `ruby -Itest` with minitest (they pick whichever is available). Kernel/core
  tests need no model.
- Adapter tests run in TestUp inside an aborted operation (repo rule).
- Mac: same suite in SketchUp for Mac; watch path separators, file encodings,
  and `UI` differences in the adapter only.

## Decisions (Alex, 2026-11-05)
- Every seat is SketchUp Pro or better: Solid Tools (`Group#subtract`) is
  available; no non-Pro Boolean fallback needed.
- Project variables: a shop-standards file seeds each new model; values then
  live in the model and travel with the .skp.
- Recipes are for new work. Existing DC cabinets are not migrated.
