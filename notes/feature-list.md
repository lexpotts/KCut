# KCut feature list — pain points in SketchUp / OpenCutList

Started 2026-11-05. Each entry: the problem as experienced, then candidate
approaches. Nothing here is decided — investigate on real models first.

Status key: `idea` · `investigating` · `decided` · `in progress` · `done`

---

## Design goals (apply to every feature)

- **What you see is what you get.** Every object in SketchUp is the exact real
  size of the thing it represents: what's modeled is what comes off the CNC,
  gets edge banded and gets built. No "close enough" geometry.
- **Find every place where real sizes don't match the model, and decide each one.** For example:
  face frame stock vs. plywood thickness, real sheet thickness vs. nominal (e.g. 3/4"
  ply at ~18 mm / 23/32"), edge banding thickness added to panel size, veneer.
  Each case gets a written decision on how it's modeled and cut (see
  `notes/thickness-investigation.md`).
- **Hardware is modeled exactly.** Catalog items carry full real dimensions and
  their adjustment ranges (hinge overlay/depth adjust, slide extension and
  side clearance, etc.) built into the component.
- **Stay fast.** Accurate where it matters (cut outlines, bores, mounting
  points) but no more detailed than needed. Hardware uses simplified display geometry,
  curves use sensible segment counts, regeneration only touches what changed.
- **Mac and Windows.** Everything runs on both. The test suite runs on both
  platforms (TestUp in SketchUp on each OS, plus pure-Ruby tests outside SketchUp).

---

## 8. Hardware catalog with full specs, price and suppliers — `idea`

**Wants.**
- Each catalog item researched thoroughly: every dimension, adjustment ranges,
  bore/mounting requirements, part number, manufacturer.
- Price and merchant(s) stored on the component (where to buy, at what price).
- Automatic lookup of cheapest price and best lead time across suppliers.

**Approaches.** Build on the existing hardware-materials unit price
(commit `ce8471a42`). Catalog data in attributes/definition files; price
refresh as a separate step (supplier sites/APIs — check what's actually
possible; some vendors require accounts).

## 9. Complete bill of materials in the estimate — `idea`

**Wants.**
- Full BOM at the end: every hinge, shelf pin, slide, drawer box (SVW),
  insert, push-to-open, outlet, and anything else that has to be bought.
- Each line has quantity, unit price, merchant; all of it rolls into the
  estimate total.
- Nothing purchasable left untracked — flag items that have no price.

## 10. Shared operations that stay shared — `idea`

**Problem.** The same operation (e.g. a biscuit slot with a hole on each side)
appears all over the model. You'd want to edit one and have it update all of them,
or deliberately not, but in practice copies go unique and stop sharing behavior.
Dynamic Component formulas don't keep the shared behavior once copies take on
their own values.

**Wants.**
- A shared operation definition (geometry + rules) with per-use parameters.
  Editing the definition updates every use; per-use values stay per-use.
- Explicit choice: "edit this one only" vs "edit all", never a silent split.

**Why it happens (see "How SketchUp inheritance works" below):** DC stores
sizes on the definition, so when one copy needs a different size, DC
makes it unique, which creates a new definition. From then on it no longer
shares edits with the others.

**Approaches.** Keep the operation's definition shared and fixed; store
per-use parameters on the *instance* only; generate the variable geometry
(e.g. a Boolean, #1) from the parameters instead of from a resized definition.

## 11. Edge banding on curved edges — `idea`

**Problem.** OCL offsets an edge inward by the banding thickness only on the
part's outer bounding-box edges. Curved/arbitrary edges can't be banded this
way. Mosaic could band any edge, curved included.

**Wants.**
- Band any edge of the part outline, straight or curved.
- Banded edges are offset inward by banding thickness so the finished part is
  the exact modeled size (design goal: WYSIWYG).
- CNC export uses the offset outline; cutlist reports banding length
  including curves.

## 12. Per-instance edge banding — `idea`

**Problem.** Applying banding to one part often applies it to every copy, e.g.
banding the board inside one adjustable shelf bands every adjustable shelf.

**Why.** OCL stores edge banding as a material painted on the part's faces.
Those faces live in the board's *definition*, and the board is nested inside
the shelf component, which every shelf copy shares. So every shelf contains the
same board definition, and painting it once paints all of them.

**Wants.** Control over whether banding belongs to the definition (all
copies) or to one specific placement. Possibly store banding per instance
path and have OCL read it from there.

## 13. Parametric arrays with spacing modes — `idea`

**Problem.** SketchUp arrays (copy + `x5`, or `/5` to divide a distance evenly) only work
well with a fixed spacing. Working out the spacing for other behaviors means
hand-written formulas each time.

**Wants.** An array whose count and spacing come from a length and a mode:
- **Item at each end:** first and last item sit exactly at the ends.
- **Padding first:** set end padding, then items.
- **Min spacing:** as many items as fit with at least X between them.
- **Max spacing:** as few items as possible with no more than X between them.
- **Fixed spacing, centered:** spacing X, leftover split evenly as end padding.
- **Even spacing, padding equal to the gaps:** N items, leftover spread so the end
  padding equals the gaps.
- Optional snapping to a grid, e.g. 32 mm, for shelf pins and hinges (#5).
- Count/spacing update when the host length changes.

**Problem 2.** New copies created by an array don't get the cutting
operation applied. Added holes don't actually cut. Each new copy must
trigger its Boolean/cut (#1) automatically.

## 14. Edge awareness for features inside a part — `idea`

**Problem.** Detecting "on an edge" currently means on the edge of a SketchUp
object's bounding box. Dog-boned openings (e.g. in the hood) can hide
their dog bones at an edge, but there's no general mechanism that works on geometry
*inside* a part.

**Wants.**
- A feature (pocket, slot, dog-bone corner, hole) can ask "is this corner/side
  touching or past the part's real outline?", meaning the actual face boundary,
  not the bounding box, including curved outlines and other cutouts.
- Behavior rules per feature: hide dog bones on open sides, extend a pocket
  through an edge, skip holes that would break out, warn when a hole comes closer
  to an edge than a minimum distance.
- Re-evaluate when the part outline or feature position changes.

**Approaches.** Test the feature's corners against the part's actual 2D outline
in the face plane (point-in-polygon / distance-to-edge), instead of against
bounds. Shares the plane/host model with #2.

## 15. Parametric curved parts — `idea`

**Problem.** SketchUp can't make a truly parametric curve. Current workaround
(hood; 24/24 East Norris banquette): a square block with
cutting components on top and bottom acting as inner and outer radius. East
Norris adds flat panels on the left and right that extend the curve with straight
sections. These don't report their real size up: the cutlist doesn't
show the blank you'd actually need to cut the curve from.

**Wants.**
- A curved-part object driven by inner/outer radius, sweep angle, height and
  optional flat extensions at each end.
- Reports the true stock needed: the blank that spans the curve (curve
  cuts), not the square block or the bounding box.
- Switchable build methods for the same curve:
  - **Cut from solid blank:** report blank size.
  - **Stacked plywood rings:** convert to layers of plywood (segments
    nested to save sheet), optionally with dowels through the stack; report
    each layer as a CNC part plus dowel count/length in the BOM (#9).
  - Possibly kerf-bent or bent lamination later.
- Edge banding on the curved faces (#11), edge awareness for features (#14).

**To review.** Alex is adding the component library (stacked-ply curve
examples) and cabinet library to the workspace. Study these before designing.

## 16. Parent values with sensible fallbacks when a part stands alone — `idea`

**Problem.** A part inside a cabinet takes its size and position from the
cabinet (`parent!…`, `REV BOX!X`, `revBet`, …). Take it out of the cabinet
(e.g. drag a door out, or place it loose from the library) and those
references have nothing to read. DC treats them as 0 or errors, so the door
snaps to the origin and/or collapses in size.

**Wants.**
- Parts inherit values from their parent when the parent sets them (as now).
- When the part isn't inside a parent that sets a value, it either:
  - **falls back to a default** (its own stored value, a library default, or
    the last value it had), or
  - **drops the setting** so it no longer applies, e.g. position formulas
    stop driving X/Y/Z and the part stays exactly where it is.
- Example: removing a door from a cabinet leaves the door where it was, at
  its last size. It doesn't jump to the origin.
- Putting it back into a cabinet picks the parent's values up again.

**Approaches.** Related to #3 (scoped lookup with a fallback chain: parent →
ancestors → model root → part default). Options to test: write defaults into
the part's own attributes and have formulas use them when the parent value is
missing (DC has no `ISBLANK`-style test for a missing `parent!` reference, so
check what a missing reference actually returns); or an observer that detects
a part leaving its parent and freezes/removes its placement formulas, then
restores them when it's placed back in a parent.

---

## How SketchUp inheritance works (reference)

- A **component definition** holds the geometry and everything nested inside it,
  including nested components, materials painted on inner faces and attributes
  on the definition.
- A **component instance** is one placement of that definition. It holds only its
  position/rotation/scale (transformation), a material painted on the instance
  as a whole, its tag, and its own attributes.
- Editing *inside* a component edits the definition, so **every instance
  changes**. That includes nested parts: a board inside a shelf is one
  definition shared by all shelves.
- Things set *on the instance* (material on the instance, scale, instance
  attributes) affect only that copy. A material on an instance only shows on
  faces inside that are left with the default (unpainted) material.
- **Make Unique** copies the definition so that one instance gets its own.
  Dynamic Components do this automatically when a copy's size or values change in a way
  that needs different geometry, and that is where shared behavior breaks.
- **Groups** are components underneath too. SketchUp makes a copied group
  unique as soon as you edit it.
- There's no "inherit but override" layer between definition and instance.
  That gap is the root of #10 and #12.

---

## 1. Boolean cuts that work inside SketchUp's model — `idea`

**Problem.** SketchUp's cutting components only cut the single face they glue
to. They don't cut through the sides of a part, don't cut the back face (needs
a second cutting component glued to the back), and can't cut geometry inside a
group/component they're placed on.

**Wants.**
- True Boolean operations (subtract / union / intersect) that still live inside
  SketchUp's entity system (result is ordinary faces/edges, OCL can measure it).
- Cuts pass fully through a part where they should (side and back faces too).
- Non-destructive: the cutter stays an editable object; the result regenerates
  when the cutter or target changes.
- **Reversible/temporary.** Parts are parametric, so a Boolean must never
  permanently change the base geometry. Resizing a part re-applies its cuts
  to the new size instead of stretching old cut geometry; deleting a cutter
  restores the uncut part.

**Approaches to evaluate.**
- SketchUp Pro's native `Group#subtract` / `#trim` / `#intersect` (Solid Tools
  API) — destructive and needs manifold solids; could be run on a hidden copy
  so the original + cutter remain editable ("live Boolean" by regenerating).
- Store target + cutter refs in attributes; observer re-runs the Boolean on edit.
- Check OCL measurement (`_fetch_useful_instance_infos`) still sees correct
  thickness after a Boolean.

## 2. Attach to faces of groups/components, constrained to that surface — `idea`

**Problem.** Gluing only works on bare geometry faces, not on the face of a
group/component from outside.

**Wants.**
- Attach an object to a face of a group or component (any nesting depth).
- When attached to a group/component, the attached object can Boolean-cut its
  geometry (ties into #1).
- Attached object follows the host surface: its degrees of freedom are limited
  to moving/rotating within that plane. Host moves → attached object moves.

**Approaches.** Custom tool that records host instance path + face plane in
attributes; a move tool / observer that projects motion onto the plane.

## 3. Scoped / global variables across the hierarchy — `idea`

**Problem.** DC formulas can only reach one level up (`Parent!X`). No way to
set a value at project level and use it deep inside cabinets, or share values
between sibling structures.

**Wants.**
- Project-level (model root) variables, e.g. material thickness, reveal gaps,
  hinge type, toe-kick height.
- Cabinet-level variables visible to everything below the cabinet.
- Lexical scope lookup: nearest ancestor defining the name wins, falling back
  to the model root.
- Cross-structure references (cabinet A reading a value from cabinet B).

**Approaches.** Model-level attribute dictionary as the root scope; a resolver
that walks the instance path upward; push resolved values into DC attributes
before DC redraw (see DC notes in `CLAUDE.md`). Needs care around redraw cost
and the known `undefined method 'name' for nil` redraw errors.

## 4. Parametric fillets, rounds, and profiles — `idea`

**Problem.** No native fillet/round tool. Follow Me works but is fiddly and not
parametric — can't change a radius later.

**Wants.**
- Fillet / round-over / chamfer on edges with an editable radius.
- Parametric profiles for Follow Me paths, editable after the fact.
- Router-bit library: profile represents a bit run along an edge; swap the bit
  and the edge regenerates (round-over, ogee, cove, chamfer, roman ogee…).

**Approaches.** Store path edges + profile definition (bit id, size) in
attributes; regenerate geometry on change. Profiles defined as parametric 2D
curves in Ruby rather than drawn geometry.

## 5. Doors, hinges, and the 32 mm system — `idea`

**Wants.**
- Doors open/close without changing the bounding size of the cabinet they're on.
- Hinges auto-placed at set intervals based on hinge type; control of distance
  from top/bottom edges, count, spacing.
- Door is attached to its hinges; hinges swing the full range (e.g. 110°).
- Hinge plate snaps to the nearest 32 mm system holes inside the cabinet (same
  way drawer slides pick holes) — so both the cup position on the door and the
  plate position in the box are known.
- Hinge attaches to the back of the door so it can apply operations there
  (35 mm cup bore — ties into #1 Booleans).
- Door swing indicators visible/hidden on demand.

## 6. Tags for LayOut: swings, pull-outs, fronts — `idea`

**Wants.**
- Door swings (the dashed "V" open markers), drawer pull-out indicators and
  drawer fronts each on their own tag, toggleable per viewport in LayOut.
- Everything we generate for LayOut lives on predictable tags.

**To verify — tag/parent behavior.** Alex's recollection: LayOut misbehaves
when geometry has its own tag rather than sharing its parent's. What SketchUp
documents: an entity is visible only if its own tag *and every ancestor
container's tag* are visible. Hiding a parent's tag always hides its contents;
hiding a tag that's only on raw edges/faces inside a container is the fragile
case (and SketchUp's best practice is: raw geometry stays Untagged, tag the
groups/components). Need a test model to confirm which way the LayOut problem
goes before choosing a convention. Likely convention: put swing/indicator
geometry in its own group, tag the group, leave its edges Untagged.

## 7. LayOut-native text and scale — `idea`

**Wants.**
- Annotations made in SketchUp for LayOut (labels, swing markers, notes) use
  LayOut fonts and text scaling rather than 3D text baked into the model.
- A clean scale indicator on each LayOut page.
- Dimension tool scale always matches the page; all viewports on a page share
  one scale unless explicitly overridden.

**Approaches.** LayOut Ruby API (`Layout::Document`) to generate/sync labels
and scale notes; SketchUp side may export anchor points/attributes rather than
geometry text. Needs investigation of what the LayOut API can automate.

---

## Already done (for reference)
- Report components as single items (drawer boxes ordered from supplier).
- Hardware materials with unit price in the estimate.
- Smart Draw default DC attributes; "CabNum - Name" part names.
- See `notes/work-log.md`.
