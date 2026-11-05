# CLAUDE.md — KCut, start here

Handoff notes for Claude Code, exported 2026-11-05 from the claude.ai Project
"Kole Sketchup plugin". Owner: Alex (git identity `Alex <lex.potsus@gmail.com>`).

KCut is Alex's fork of **OpenCutList** (he calls it "OCL"), the SketchUp
cutlist/estimate plugin by L'Air du Bois. Upstream remote merges come from
`upstream/master`; Alex's own work starts at `8112ad1db`.

More notes: `notes/work-log.md` (what's done, what's pending),
`notes/thickness-investigation.md` (open LenZ investigation — no decision yet).
Sibling repos: `..\kole-sketchup-plugin` (its `CLAUDE.md` covers the shared
SketchUp workflow) and `..\sketchup-mcp` (bridge for running Ruby in SketchUp).

## Layout
- Ruby: `src/ladb_opencutlist/ruby/` (`plugin.rb`, `worker/cutlist/*`,
  `model/*`, `utils/*`, `tool/smart_draw_tool.rb`).
- UI: Twig templates `src/ladb_opencutlist/twig/`, JS `src/ladb_opencutlist/js/`,
  strings `src/ladb_opencutlist/yaml/i18n-src/en.yml`.
- **Template/JS/i18n changes need a rebuild:** `gulp compile` / `gulp build` in `build/`.
- Packages: `dist/` (e.g. `KCut-drawer-items-2026-11-03.rbz`, untracked).
- Tests: TestUp files in `test/` (`TC_Ladb_*.rb`).

## Context from Alex
- Rarely uses "detect axes" (auto-orient). Thickness overrides must only apply
  when detect axes is off.
- Shop orders drawer boxes from SVW Woodcrafters by dimensions, species and
  features (scoops, pulls, contents).
- Wants drawers (later other tracked items) reported as single items with their
  DC values in the parts list/estimate, toggleable per component back to OCL's
  normal breakdown. Chose: per-instance toggle on the Tray Box level, order
  values as DC attributes he adds himself.
- Works evidence-first: investigate on real models and record findings before
  deciding; don't implement the thickness override until he decides.

## Rules
- **Never change Alex's open model when testing.** Wrap probes/tests in
  `model.start_operation('…', true)` … `ensure model.abort_operation`, and check
  `model.modified?` afterwards. Check `Sketchup.active_model.title` first — the
  production file ("1115 Old Gulph Rd_PRODUCTION_10-27-26") has been open
  instead of the test model before. Test model: `..\kole-sketchup-plugin\Old Gulph Testbed.skp` (mm units).
- **CRLF line endings.** Preserve them when editing. Five files show as
  modified only because of line endings — not real edits, leave them alone.
  Commit with `git -c core.autocrlf=true …`.
- **No git identity configured:** `git -c user.name="Alex" -c user.email="lex.potsus@gmail.com" commit …`
  (don't change his config). Commit trailer: `Co-Authored-By: Claude …`.
- Add a TestUp test for each change (they run in an aborted operation).

## Code knowledge
- Thickness: `_fetch_useful_instance_infos` in `cutlist_generate_worker.rb`
  measures visible faces (incl. nested groups and cut-opening children; nested
  components become their own parts); `Size3d.create_from_bounds` orients;
  ~line 387 subtracts veneer / layer count / matches standard thicknesses. Raw
  `instance_info.size` also feeds `PartDef.generate_part_id` and edge-banding width.
- `Ladb::OpenCutList::BoundingBoxHelper#_compute_faces_bounds` can be extended
  onto a probe object in the Ruby console to reproduce OCL's measurements exactly.
- DC attributes on instances use lowercase keys (`lenx`); `get_dc_attribute` in
  `model/formula/formula_wrapper.rb` now lowercases for instances/groups too.
- DC redraw: `$dc_observers.get_latest_class.redraw(inst, false)`; it recomputes
  values but only resizes geometry when the part stores `_len?_nominal`, and
  resizing comes from the parent's redraw. 76 redraws in the test model raise
  `undefined method 'name' for nil`.
- DC formula units vary per component (`_lengthunits`), stored Len values are inches.
- DC formulas use `LARGEST()`/`SMALLEST()`, not `MAX()`/`MIN()`.
