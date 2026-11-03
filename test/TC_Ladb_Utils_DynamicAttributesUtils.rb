require 'testup/testcase'

require_relative '../src/ladb_opencutlist/ruby/utils/dynamic_attributes_utils'

# KCut: default DC attributes added to parts drawn with the Smart Draw tool.
# Runs inside an aborted operation so the open model is left untouched.
class TC_Ladb_Utils_DynamicAttributesUtils < TestUp::TestCase

  DICT = 'dynamic_attributes'

  def setup
    @model = Sketchup.active_model
    @model.start_operation('KCut test: DynamicAttributesUtils', true)

    @definition = @model.definitions.add('KCut test part')
    @definition.entities.add_face([ 0, 0, 0 ], [ 10, 0, 0 ], [ 10, 4, 0 ], [ 0, 4, 0 ]).pushpull(-0.75)
    @instance = @model.active_entities.add_instance(@definition, Geom::Transformation.new([ 1, 2, 3 ]))
  end

  def teardown
    @model.abort_operation
  end

  def utils
    Ladb::OpenCutList::DynamicAttributesUtils
  end

  def test_cab_num_formula
    utils.add_part_defaults(@instance)
    assert_equal('CabNum', @definition.get_attribute(DICT, '_cabnum_label'))
    assert_equal('parent!cabNum', @definition.get_attribute(DICT, '_cabnum_formula'))
    assert_nil(@definition.get_attribute(DICT, 'cabnum'))
  end

  def test_cab_num_value_from_parent
    parent = @model.active_entities.add_group
    parent.entities.add_cpoint(ORIGIN)
    parent.set_attribute(DICT, 'cabnum', 7)
    utils.add_part_defaults(@instance, parent)
    assert_equal(7, @definition.get_attribute(DICT, 'cabnum'))
  end

  def test_size_and_position_shown
    utils.add_part_defaults(@instance)
    { 'lenx' => 'LenX', 'leny' => 'LenY', 'lenz' => 'LenZ', 'x' => 'X', 'y' => 'Y', 'z' => 'Z' }.each do |key, label|
      assert_equal(label, @definition.get_attribute(DICT, "_#{key}_label"), key)
    end
    assert_in_delta(10.0, @instance.get_attribute(DICT, 'lenx'), 1e-6)
    assert_in_delta(4.0, @instance.get_attribute(DICT, 'leny'), 1e-6)
    assert_in_delta(0.75, @instance.get_attribute(DICT, 'lenz'), 1e-6)
    assert_in_delta(1.0, @instance.get_attribute(DICT, 'x'), 1e-6)
    assert_in_delta(2.0, @instance.get_attribute(DICT, 'y'), 1e-6)
    assert_in_delta(3.0, @instance.get_attribute(DICT, 'z'), 1e-6)
  end

  def test_size_includes_scaling
    @instance.transformation = Geom::Transformation.scaling(2, 1, 1)
    utils.add_part_defaults(@instance)
    assert_in_delta(20.0, @instance.get_attribute(DICT, 'lenx'), 1e-6)
  end

  def test_name_is_definition_name
    utils.add_part_defaults(@instance)
    assert_equal('Name', @definition.get_attribute(DICT, '_name_label'))
    assert_equal(@definition.name, @definition.get_attribute(DICT, 'name'))
    assert_equal(@definition.name, @definition.get_attribute(DICT, '_name'))
  end

  def test_rename_updates_name
    utils.add_part_defaults(@instance)
    old_name = @definition.name
    @definition.name = 'KCut test side panel'
    utils.update_name(@instance, old_name)
    assert_equal('KCut test side panel', @definition.get_attribute(DICT, 'name'))
  end

  def test_rename_keeps_custom_name
    utils.add_part_defaults(@instance)
    old_name = @definition.name
    @definition.set_attribute(DICT, 'name', 'Custom')
    @definition.name = 'KCut test other'
    utils.update_name(@instance, old_name)
    assert_equal('Custom', @definition.get_attribute(DICT, 'name'))
  end

end
