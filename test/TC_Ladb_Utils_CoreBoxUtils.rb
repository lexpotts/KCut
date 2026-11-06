require 'testup/testcase'

require_relative '../src/ladb_opencutlist/ruby/utils/core_box_utils'

# KCut: cabinet size read from / written through the "Cab Bounding Box" core box.
# Runs inside an aborted operation so the open model is left untouched.
class TC_Ladb_Utils_CoreBoxUtils < TestUp::TestCase

  DICT = 'dynamic_attributes'
  DELTA = 1e-6
  U = Ladb::OpenCutList::CoreBoxUtils

  def setup
    @model = Sketchup.active_model
    @model.start_operation('KCut test: CoreBoxUtils', true)

    # 10" cube, like the real core box definition.
    @box_definition = @model.definitions.add('Cab Bounding Box')
    @box_definition.entities.add_face([ 0, 0, 0 ], [ 10, 0, 0 ], [ 10, 10, 0 ], [ 0, 10, 0 ]).pushpull(-10)

    # Cabinet whose core box is scaled to 18 x 24.5 x 34.82 and whose Len
    # attributes are stale (31 x 25.25 x 34.25), plus a drawer sticking out.
    @cabinet_definition = @model.definitions.add('KCut test cabinet')
    @box = @cabinet_definition.entities.add_instance(@box_definition, Geom::Transformation.scaling(1.8, 2.45, 3.482))
    drawer = @model.definitions.add('KCut test drawer')
    drawer.entities.add_face([ 0, 0, 0 ], [ 16, 0, 0 ], [ 16, 30, 0 ], [ 0, 30, 0 ]).pushpull(-6)
    @cabinet_definition.entities.add_instance(drawer, Geom::Transformation.translation([ 1, -20, 20 ]))
    @cabinet = @model.active_entities.add_instance(@cabinet_definition, Geom::Transformation.translation([ 100, 0, 0 ]))
    @cabinet.set_attribute(DICT, 'lenx', '31')
    @cabinet.set_attribute(DICT, 'leny', 25.25)
    @cabinet.set_attribute(DICT, 'lenz', 34.25)
  end

  def teardown
    @model.abort_operation
  end

  def assert_size(expected, actual)
    expected.each_with_index { |v, i| assert_in_delta(v, actual[i], DELTA, "axis #{i}") }
  end

  def test_core_box_found
    assert_equal(@box, U.core_box(@cabinet))
    assert(U.cabinet?(@cabinet))
    refute(U.cabinet?(@box))
  end

  def test_core_size_ignores_geometry_outside_box
    assert_size([ 18, 24.5, 34.82 ], U.core_size(@cabinet))
    assert(@cabinet.bounds.height > 40, 'drawer extends the cabinet bounds')
  end

  def test_drift
    d = U.drift(@cabinet)
    assert_equal(%w[x y z], d[:axes])
    assert_size([ 31, 25.25, 34.25 ], d[:cabinet])
    assert(U.drifted?(@cabinet))
  end

  def test_missing_len_counts_as_drift
    @cabinet.delete_attribute(DICT, 'leny')
    assert_includes(U.drift(@cabinet)[:axes], 'y')
  end

  def test_sync_from_core_box_core_wins
    assert_equal(%w[x y z], U.sync_from_core_box(@cabinet))
    assert_size([ 18, 24.5, 34.82 ], U.cabinet_size(@cabinet))
    refute(U.drifted?(@cabinet))
    assert_equal([], U.sync_from_core_box(@cabinet))
  end

  def test_resize_sets_box_cabinet_and_definition
    assert(U.resize(@cabinet, [ 24, nil, 30 ], redraw: false))
    assert_size([ 24, 24.5, 30 ], U.core_size(@cabinet))
    assert_size([ 24, 24.5, 30 ], U.cabinet_size(@cabinet))
    assert_in_delta(24, @cabinet_definition.get_attribute(DICT, '_lenx_nominal'), DELTA)
    assert_in_delta(30, @box.get_attribute(DICT, 'lenz'), DELTA)
    refute(U.drifted?(@cabinet))
  end

  def test_resize_never_scales_cabinet_instance
    U.resize(@cabinet, [ 40, 30, 50 ], redraw: false)
    assert_size([ 1, 1, 1 ], U.scales(@cabinet.transformation))
  end

  def test_resize_keeps_min_faces_by_default
    U.resize(@cabinet, [ 24, nil, nil ], redraw: false)
    assert_in_delta(100, @cabinet.transformation.origin.x, DELTA)
  end

  def test_resize_anchor_keeps_max_face
    U.resize(@cabinet, [ 24, nil, nil ], anchor: [ 1, 0, 0 ], redraw: false)
    assert_in_delta(94, @cabinet.transformation.origin.x, DELTA)
  end

  def test_resize_makes_shared_definition_unique
    other = @model.active_entities.add_instance(@cabinet_definition, IDENTITY)
    U.resize(@cabinet, [ 24, nil, nil ], redraw: false)
    refute_equal(other.definition, @cabinet.definition)
    assert_size([ 18, 24.5, 34.82 ], U.core_size(other))
  end

  def test_scales_reads_matrix_not_normalized_axes
    assert_size([ 1.8, 2.45, 3.482 ], U.scales(@box.transformation))
  end

end
