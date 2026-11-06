# KCut work log (newest first)

## Done (not committed yet)

### Part designation "CabNum - Name" (2026-11-05)
- Parts with a DC `Name` (instance, else definition) are listed as that name,
  with `CabNum` in front when there is one: "12 - Left Side". Always on (no
  longer needs OCL's "Use the attribute Name" option). Different CabNum/Name →
  separate rows. `CabNum` = `parent!CabNum` is read from the parent in the
  path, so it's right before a DC redraw and when a definition is shared.
- Parts without both Name and CabNum get a faded DC icon with a "+" in the
  list; click it to convert (applies to all selected parts if that row is
  selected). Also right-click › KCut › Use Parent CabNum + Name. Convert sets
  the definition's CabNum formula to `parent!CabNum`, copies the parent's value
  onto the instance, and adds Name = definition name if missing. One undo step.
  Containers between the part and the nearest ancestor with its own CabNum
  (drawer boxes, bumper/leveler assemblies) get `parent!CabNum` too (groups on
  the group, components on the definition); left alone if no ancestor has one.
- Files: `utils/designation_utils.rb` (new), `worker/cutlist/cutlist_kcut_designation_setup_worker.rb`
  (new), `instance_info.rb`, `part_def.rb`, `part.rb`, generate worker,
  `cutlist_controller.rb`, `plugin.rb`, `_list-row-col-name.twig`, tab-cutlist JS, `en.yml`.
- Test `test/TC_Ladb_Utils_DesignationUtils.rb` (12 tests) pass on the Old
  Gulph Testbed (minitest, TestUp not loaded). Converting all 896 unset parts
  in its cabinets (aborted op): all set up, every one gets the nearest
  cabinet's number (e.g. "19 - Drawer Back#27"). Names copied from definitions
  keep SketchUp's "#27" suffix. UI button not clicked live yet (installed
  plugin is the old build). Read-only check on 2424 E. Norris: 121
  parts already set up (e.g. "1 - L End", "1 - Back"), 127 with Name only
  (e.g. Biscuit Slot), 3533 with neither.

## Done (committed)

### `b6b1d3b04` Report components as single items (2026-11-03)
- Right-click › **KCut › Report as Single Item…** on selected drawer boxes;
  pick/create a Hardware item material ("Drawers" by default; never painted on
  the box). **KCut › List Parts** switches back. One undo step each.
- Generate worker stops opening a switched-on box: sides/back/bottom/front leave
  the list, hardware inside it (e.g. Blum slides) stays. Box listed as one part
  with LenX/LenY/LenZ plus every user-visible DC attribute (dropdowns show the
  label, e.g. "Maple"). Different values → separate rows.
- Parts list: one sortable column per value in that group (click header,
  click again to reverse; resets on regenerate).
- Estimate: own section with count and cost, price from the item material
  unless the box has its own part price.
- Export: "SVW drawer order" preset added on first start of the new build —
  number, name, count, Width/Depth/Height (LenX/LenY/LenZ), Species, Scoop,
  Pulls, Contents, one column with all other values. `@item['Species']` works
  in custom export columns.
- Files: `utils/item_utils.rb` (new), `plugin.rb`, generate/export workers,
  `model/cutlist/*`, `formula_wrapper.rb`, `tab-cutlist.js`, `_list.twig`, `en.yml`.
  Test `test/TC_Ladb_Utils_ItemUtils.rb` (7 checks pass in SketchUp).

### `ce8471a42` Hardware materials: unit price (2026-11-03)
- Hardware materials get a Price (per instance) row on the material editor's
  Attributes tab; Formats, Cut options and Estimate options tabs (and weight /
  cut-price rows) hidden for hardware.
- Estimate: hardware part with no own price uses material price × quantity;
  part price still wins. Checked: 3 hinges × $2.50 + 2 pulls at $10 = $27.50.
- Test `TC_Ladb_Model_MaterialAttributes_HardwarePrice`.

### `d32b946be` Smart Draw default DC attributes (2026-11-03)
- New parts get `CabNum` = `=parent!cabNum` (value copied if the parent has
  one; formula error when drawn outside anything with cabNum), LenX/LenY/LenZ
  and X/Y/Z visible in Component Attributes, `Name` = definition name (follows
  renames from the tool's prompt unless typed by hand).
- `utils/dynamic_attributes_utils.rb` + a few lines in `smart_draw_tool.rb`;
  test `TC_Ladb_Utils_DynamicAttributesUtils`.

### `8112ad1db` Donate button removed; DC attribute case fix (2026-11-02)
- Sponsor/donate removed from bottom bar, More menu and upgrade modal.
- `get_dc_attribute` lowercases names on instances/groups (only definitions did).
- Test `TC_Ladb_Model_FormulaWrapper.rb`.

## Pending / waiting on Alex
- Install `dist/KCut-drawer-items-2026-11-03.rbz` and try it: the right-click
  menu, new columns and sorting haven't been seen running yet.
- Add Species, Scoop, Pulls, Contents (user-visible) to the Tray Box DC — the
  SVW preset expects those exact names.
- T51.1901 locking devices inside boxes drop out with the box unless put on a
  Hardware material.
- If "Drawers" is purged as unused, the list warns; Report as Single Item again recreates it.

## Open investigation
LenZ thickness override — see `thickness-investigation.md` (snapshot; live doc
https://claude.ai/artifact/SAckTYxn6ZZiK1eRHCkNbm). Last session stopped
before redrawing ~400 DCs because the production model was open, not the testbed.
