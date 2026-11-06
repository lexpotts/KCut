# KCut recipes: base_cabinet assembly (pure) and the SketchUp regenerator.
#
# The assembly tests run anywhere (plain Ruby or TestUp). The regenerator
# tests need SketchUp Pro and run inside an aborted operation, so the open
# model is left untouched.
begin
  require 'testup/testcase'
  KCUT_RECIPE_TEST_BASE = TestUp::TestCase
rescue LoadError
  require 'minitest/autorun'
  KCUT_RECIPE_TEST_BASE = Minitest::Test
end

require 'json'
require_relative '../src/ladb_opencutlist/ruby/kcut/assemblies/base_cabinet'
require_relative '../src/ladb_opencutlist/ruby/kcut/sketchup/recipe_editor' if defined?(Sketchup)

class TC_Ladb_KCut_Recipes < KCUT_RECIPE_TEST_BASE

  KC = Ladb::OpenCutList::KCut
  SHOP = File.join(__dir__, '..', 'src', 'ladb_opencutlist', 'ruby', 'kcut', 'shop', 'default_standards.json')

  def project
    KC::Core::Scope.new(JSON.parse(File.read(SHOP)).reject { |k, _| k.start_with?('_') })
  end

  def build(params = {}, features = [])
    KC::Assemblies.build({ 'v' => 1, 'type' => 'base_cabinet', 'params' => params, 'features' => features }, project)
  end

  def part(out, name)
    out[:parts].find { |p| p[:name] == name } or flunk("no part #{name}")
  end

  # -- Assembly (pure) ----------------------------------------------------

  def test_parts_and_sizes
    out = build
    names = out[:parts].map { |p| p[:name] }
    assert_equal [ 'Left End', 'Right End', 'Bottom', 'Back', 'Rear Stretcher', 'Front Cleat', 'Toe Kick', 'Shelf 1', 'Door 1', 'Door 2' ], names
    le = part(out, 'Left End')
    assert_in_delta 18.44, le[:max][0] - le[:min][0], 1e-9
    assert_in_delta 694.3, le[:max][2], 1e-9
  end

  def test_shelf_pins_on_32mm_from_first_hole
    ops = part(build, 'Left End')[:ops].select { |o| o[:op] == :bore }
    zs = ops.map { |o| o[:center][2] }.uniq.sort
    first = 101.6 + 18.44 + 64
    zs.each { |z| assert_in_delta 0, ((z - first) / 32.0) - ((z - first) / 32.0).round, 1e-9 }
    assert ops.all? { |o| o[:dir] == [ -1.0, 0.0, 0.0 ] && o[:center][0] == 18.44 }, 'left end bores go into the inner face'
  end

  def test_resize_recomputes_doors_and_hinges
    out = build('width' => 600, 'doors' => 1, 'height' => 900)
    door = part(out, 'Door 1')
    assert_in_delta 600 - 2 * 18.44 - 2 * 3.175, door[:max][0] - door[:min][0], 1e-9
    cups = door[:ops].select { |o| o[:dia] == 35.0 }
    assert_equal 3, cups.length, 'taller door gets a third hinge (max 500 between)'
    assert cups.all? { |o| o[:dir] == [ 0.0, -1.0, 0.0 ] }
  end

  def test_project_value_flows_down
    s = project
    s.set('panel_th', 19.05)
    out = KC::Assemblies.build({ 'type' => 'base_cabinet', 'params' => {} }, s)
    le = part(out, 'Left End')
    assert_in_delta 19.05, le[:max][0] - le[:min][0], 1e-9
  end

  def test_extra_feature_on_recipe
    frame = { 'origin' => [ 0, 19.05, 0 ], 'u' => [ 0, 0, 1 ], 'v' => [ 0, 1, 0 ], 'n' => [ 1, 0, 0 ] }
    f = { 'type' => 'bore_row', 'id' => 'outlet', 'part' => 'Left End', 'frame' => frame,
          'params' => { 'length' => 200, 'mode' => 'count', 'count' => 1, 'y' => 100, 'dia' => 8, 'depth' => 18.44 } }
    ops = part(build({}, [ f ]), 'Left End')[:ops]
    assert(ops.any? { |o| o[:dia] == 8 && o[:center] == [ 0.0, 119.05, 100.0 ] })
  end

  def test_newer_recipe_rejected
    assert_raises(ArgumentError) { KC::Assemblies.build({ 'v' => 99, 'type' => 'base_cabinet' }, project) }
  end

  # -- Regenerator (SketchUp Pro) -------------------------------------------

  def with_model
    skip 'needs SketchUp' unless defined?(Sketchup)
    model = Sketchup.active_model
    model.start_operation('KCut test: recipes', true)
    yield model
  ensure
    model&.abort_operation
  end

  def test_build_and_resize_keep_every_part_solid
    with_model do |m|
      KC::SketchUpAdapter::Regenerator.seed_project(m)
      g = KC::SketchUpAdapter::Regenerator.create(m.entities, { 'v' => 1, 'type' => 'base_cabinet', 'params' => {} })
      parts = g.entities.grep(Sketchup::Group).reject { |p| p.layer.name.start_with?('KCut/') }
      assert_equal 10, parts.length
      assert parts.all?(&:manifold?)

      le = parts.find { |p| p.name == 'Left End' }
      solid = 18.44 * 495.3 * 694.3 - 18.44 * 101.0 * 101.6
      pins = 22 * 18.75 * 10 # 2 rows x 11 holes; 5 mm hole drawn as a 12-gon (area 18.75), 10 deep
      assert_in_delta solid - pins, le.volume / 1.mm**3, 5

      KC::SketchUpAdapter::Regenerator.update(g, { 'width' => 600, 'doors' => 1 })
      parts = g.entities.grep(Sketchup::Group).reject { |p| p.layer.name.start_with?('KCut/') }
      assert parts.all?(&:manifold?), 'cuts re-applied cleanly after resize'
      door = parts.find { |p| p.name == 'Door 1' }
      assert_in_delta 600 - 2 * 18.44 - 2 * 3.175, door.bounds.width.to_mm, 0.01
      assert_nil parts.find { |p| p.name == 'Door 2' }
      assert_equal 600, JSON.parse(g.get_attribute('kcut', 'recipe'))['params']['width']
    end
  end

  def test_editor_round_trips_and_stores_only_changes
    with_model do |m|
      ed = KC::SketchUpAdapter::RecipeEditor
      KC::SketchUpAdapter::Regenerator.seed_project(m)
      g = KC::SketchUpAdapter::Regenerator.create(m.entities, { 'v' => 1, 'type' => 'base_cabinet', 'params' => { 'cabnum' => 7 } })
      fs = ed.fields(g)
      assert_equal :length, fs.find { |f| f.key == 'width' }.kind
      assert_equal :integer, fs.find { |f| f.key == 'doors' }.kind
      assert_equal 'Cab Number', fs.find { |f| f.key == 'cabnum' }.label

      # What the input box hands back: Lengths and strings, edited width/doors.
      results = ed.prompt_values(fs).each_with_index.map do |v, i|
        case fs[i].key
        when 'width' then 700.mm
        when 'doors' then '1'
        else v
        end
      end
      ed.apply(g, ed.parse(fs, results))
      params = JSON.parse(g.get_attribute('kcut', 'recipe'))['params']
      assert_equal({ 'cabnum' => 7, 'width' => 700.0, 'doors' => 1 }, params)
      assert_in_delta 700, g.bounds.width.to_mm, 0.01
      assert_raises(ArgumentError) { ed.parse(fs, results.each_with_index.map { |v, i| fs[i].key == 'shelves' ? 'two' : v }) }
    end
  end

end
