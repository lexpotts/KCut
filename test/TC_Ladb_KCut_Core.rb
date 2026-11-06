# KCut framework core: ArraySpacing, Scope, Feature (pure Ruby, no model).
#
# Runs under TestUp inside SketchUp, or anywhere with plain Ruby:
#   ruby test/TC_Ladb_KCut_Core.rb
begin
  require 'testup/testcase'
  KCUT_TEST_BASE = TestUp::TestCase
rescue LoadError
  require 'minitest/autorun'
  KCUT_TEST_BASE = Minitest::Test
end

require_relative '../src/ladb_opencutlist/ruby/kcut/geom/array_spacing'
require_relative '../src/ladb_opencutlist/ruby/kcut/core/scope'
require_relative '../src/ladb_opencutlist/ruby/kcut/core/feature'
require_relative '../src/ladb_opencutlist/ruby/kcut/features/bore_row'

class TC_Ladb_KCut_Core < KCUT_TEST_BASE

  AS = Ladb::OpenCutList::KCut::Geom::ArraySpacing
  Scope = Ladb::OpenCutList::KCut::Core::Scope
  Feature = Ladb::OpenCutList::KCut::Core::Feature

  def assert_positions(expected, layout)
    assert_equal expected.length, layout.positions.length, "got #{layout.positions.inspect}"
    expected.zip(layout.positions).each { |e, a| assert_in_delta e, a, 1e-6 }
  end

  # -- ArraySpacing ------------------------------------------------------

  def test_count_includes_ends
    assert_positions [ 0, 50, 100 ], AS.layout(length: 100, mode: :count, count: 3)
  end

  def test_count_with_padding_and_size
    # 10 padding, items 20 wide: centers from 20 to 80
    assert_positions [ 20, 50, 80 ], AS.layout(length: 100, mode: :count, count: 3, padding: 10, size: 20)
  end

  def test_single_item_centered
    assert_positions [ 50 ], AS.layout(length: 100, mode: :count, count: 1)
  end

  def test_min_spacing_fits_as_many_as_possible
    l = AS.layout(length: 100, mode: :min_spacing, spacing: 30)
    assert_positions [ 0, 33.333333, 66.666667, 100 ], l
    assert_operator l.pitch, :>=, 30
  end

  def test_max_spacing_uses_as_few_as_needed
    l = AS.layout(length: 100, mode: :max_spacing, spacing: 30)
    assert_equal 5, l.count
    assert_operator l.pitch, :<=, 30
  end

  def test_exact_multiple_does_not_add_items
    assert_equal 5, AS.layout(length: 100, mode: :max_spacing, spacing: 25).count
    assert_equal 5, AS.layout(length: 100, mode: :min_spacing, spacing: 25).count
  end

  def test_fixed_spacing_centers_leftover
    assert_positions [ 5, 35, 65, 95 ], AS.layout(length: 100, mode: :fixed_spacing, spacing: 30)
  end

  def test_distributed_gaps_equal_end_padding
    assert_positions [ 25, 50, 75 ], AS.layout(length: 100, mode: :distributed, count: 3)
    # items 10 wide: 4 equal gaps of 17.5
    assert_positions [ 22.5, 50, 77.5 ], AS.layout(length: 100, mode: :distributed, count: 3, size: 10)
  end

  def test_grid_snaps_to_32mm
    l = AS.layout(length: 700, mode: :fixed_spacing, spacing: 96, padding: 37, grid: 32, grid_origin: 37)
    l.positions.each { |p| assert_in_delta 0, ((p - 37) / 32.0) - ((p - 37) / 32.0).round, 1e-9 }
    assert l.positions.all? { |p| p >= 37 && p <= 663 }
  end

  def test_too_short_gives_nothing
    assert_equal 0, AS.layout(length: 10, mode: :count, count: 2, padding: 6).count
  end

  def test_bad_arguments
    assert_raises(ArgumentError) { AS.layout(length: 100, mode: :nope) }
    assert_raises(ArgumentError) { AS.layout(length: 100, mode: :min_spacing, spacing: 0) }
    assert_raises(ArgumentError) { AS.layout(length: 100, mode: :count) }
  end

  # -- Scope -------------------------------------------------------------

  def project
    Scope.new({ 'reveal' => 3, 'thickness' => 18, 'toe_kick' => 100 })
  end

  def test_value_visible_deep_below
    part = project.child({ 'width' => 600 }).child.child
    assert_equal 18, part['thickness']
    assert_equal 600, part['width']
  end

  def test_nearer_scope_overrides
    cab = project.child({ 'reveal' => 2 })
    assert_equal 2, cab.child['reveal']
  end

  def test_expression_evaluated_where_asked
    root = Scope.new({ 'door_width' => '=width - 2 * reveal', 'reveal' => 3 })
    assert_equal 594, root.child({ 'width' => 600 })['door_width']
    assert_equal 394, root.child({ 'width' => 400 })['door_width']
  end

  def test_functions_and_precedence
    s = Scope.new({ 'a' => 4, 'v' => '=LARGEST(a, 10) / 4 + -1 * (2 + 1)' })
    assert_in_delta(-0.5, s['v'], 1e-9)
  end

  def test_cross_structure_reference
    root = project
    root.child({ 'height' => 720 }, name: 'cab12')
    other = root.child({ 'h' => '=@cab12.height + toe_kick' }, name: 'cab13')
    assert_equal 820, other['h']
  end

  def test_unknown_name_and_cycle
    s = Scope.new({ 'a' => '=b', 'b' => '=a' })
    assert_raises(Scope::CycleError) { s['a'] }
    assert_raises(Scope::UnknownName) { s['missing'] }
  end

  def test_names_are_case_insensitive
    assert_equal 3, Scope.new({ 'Reveal' => 3 })['REVEAL']
  end

  # -- Feature -----------------------------------------------------------

  def test_feature_round_trip
    f = Feature.new(type: 'bore_row', id: 'pins-l', params: { 'dia' => 5 }, scope: :instance)
    g = Feature.from_h(f.to_h)
    assert_equal [ 'bore_row', 'pins-l', :instance, 5 ], [ g.type, g.id, g.scope, g.params['dia'] ]
  end

  def test_newer_schema_rejected
    assert_raises(ArgumentError) { Feature.from_h('v' => 99, 'type' => 'x', 'id' => 'y') }
  end

  def test_bore_row_uses_scope_and_32mm_grid
    cabinet = Scope.new({ 'pin_dia' => 5, 'pin_depth' => 10 }).child({ 'side_height' => 700 })
    f = Feature.new(type: 'bore_row', id: 'pins', params: {
      'length' => '=side_height', 'mode' => 'fixed_spacing', 'spacing' => 32,
      'padding' => 37, 'grid' => 32, 'grid_origin' => 37, 'y' => 37,
      'dia' => '=pin_dia', 'depth' => '=pin_depth',
    })
    ops = f.evaluate(cabinet)
    assert_equal 20, ops.length
    assert ops.all? { |o| o[:op] == :bore && o[:dia] == 5 && o[:depth] == 10 && o[:center][1] == 37 }
    assert_in_delta 37, ops.first[:center][0], 1e-9
  end

  def test_unknown_feature_type
    assert_raises(ArgumentError) { Feature.new(type: 'nope', id: 'x').evaluate(Scope.new) }
  end

end
