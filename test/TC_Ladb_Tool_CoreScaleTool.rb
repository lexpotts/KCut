require 'testup/testcase'

require_relative '../src/ladb_opencutlist/ruby/tool/core_scale_tool'

# KCut: core-box resize tool geometry (grips, preview box, anchoring).
# Runs inside an aborted operation so the open model is left untouched.
class TC_Ladb_Tool_CoreScaleTool < TestUp::TestCase

  DELTA = 1e-6
  T = Ladb::OpenCutList::CoreScaleTool
  G = Ladb::OpenCutList::CoreScaleTool::Grip

  def setup
    @model = Sketchup.active_model
    @model.start_operation('KCut test: CoreScaleTool', true)
    box = @model.definitions.add('Cab Bounding Box')
    box.entities.add_face([ 0, 0, 0 ], [ 10, 0, 0 ], [ 10, 10, 0 ], [ 0, 10, 0 ]).pushpull(-10)
    cabinet = @model.definitions.add('KCut test cabinet')
    cabinet.entities.add_instance(box, Geom::Transformation.scaling(1.8, 2.4, 3.0))
    drawer = @model.definitions.add('KCut test drawer')
    drawer.entities.add_face([ 0, 0, 0 ], [ 16, 0, 0 ], [ 16, 30, 0 ], [ 0, 30, 0 ]).pushpull(-6)
    cabinet.entities.add_instance(drawer, Geom::Transformation.translation([ 1, -20, 20 ]))
    # Rotated 90 degrees and moved, like a cabinet on a side wall.
    @tr = Geom::Transformation.translation([ 100, 50, 0 ]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees)
    @cabinet = @model.active_entities.add_instance(cabinet, @tr)
    @tool = T.new(@cabinet)
  end

  def teardown
    @model.abort_operation
  end

  def assert_point(expected, actual)
    3.times { |i| assert_in_delta(expected[i], actual[i].to_f, DELTA, "coord #{i}") }
  end

  def test_frame_is_core_box_not_bounds
    assert_equal([ 18.0, 24.0, 30.0 ], @tool.size.map { |v| v.round(6) })
    assert_point([ 100, 50, 0 ], @tool.origin)
    assert_point([ 0, 1, 0 ], @tool.axes[0])
  end

  def test_rejects_non_cabinet
    assert_nil(T.new(@cabinet.definition.entities.grep(Sketchup::ComponentInstance).last).cabinet)
  end

  def test_face_centers
    assert_point([ 100 - 12, 50 + 18, 15 ], @tool.face_center(@tool.origin, @tool.size, G.new(0, 1)))
    assert_point([ 100 - 12, 50, 15 ], @tool.face_center(@tool.origin, @tool.size, G.new(0, -1)))
    assert_point([ 100 - 12, 50 + 9, 30 ], @tool.face_center(@tool.origin, @tool.size, G.new(2, 1)))
  end

  def test_corners_count_and_extent
    c = @tool.corners(@tool.origin, @tool.size)
    assert_equal(8, c.length)
    assert_in_delta(30, c.map { |p| p.z.to_f }.max, DELTA)
  end

  def test_move_max_face_keeps_origin
    r = @tool.moved(G.new(0, 1), 6)
    assert_in_delta(24, r[:size][0], DELTA)
    assert_point(@tool.origin.to_a, r[:origin])
  end

  def test_move_min_face_moves_origin_outward
    r = @tool.moved(G.new(0, -1), 6)
    assert_in_delta(24, r[:size][0], DELTA)
    assert_point([ 100, 44, 0 ], r[:origin])
  end

  def test_move_snaps_to_sixteenth
    assert_in_delta(18.0625, @tool.moved(G.new(0, 1), 0.07)[:size][0], DELTA)
  end

  def test_move_clamps_to_min_size
    assert_in_delta(T::MIN_SIZE, @tool.moved(G.new(2, 1), -100)[:size][2], DELTA)
  end

end
