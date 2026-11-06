require 'testup/testcase'

require_relative '../src/ladb_opencutlist/ruby/utils/designation_utils'

# KCut: part designation "CabNum - Name" from DC attributes, and the
# conversion to CabNum = parent!CabNum.
# Runs inside an aborted operation so the open model is left untouched.
class TC_Ladb_Utils_DesignationUtils < TestUp::TestCase

  DICT = 'dynamic_attributes'

  def setup
    @model = Sketchup.active_model
    @model.start_operation('KCut test: DesignationUtils', true)

    # Cabinet (component, CabNum 12) > Box (group, no attributes) > Side (part)
    @cabinet_definition = @model.definitions.add('KCut test cabinet')
    @cabinet = @model.active_entities.add_instance(@cabinet_definition, IDENTITY)
    @cabinet.set_attribute(DICT, 'cabnum', 12.0)

    @definition = @model.definitions.add('KCut test side')
    @definition.entities.add_face([ 0, 0, 0 ], [ 10, 0, 0 ], [ 10, 4, 0 ], [ 0, 4, 0 ]).pushpull(-0.75)
    @part = @cabinet_definition.entities.add_instance(@definition, IDENTITY)
    @path = [ @cabinet, @part ]
  end

  def teardown
    @model.abort_operation
  end

  def utils
    Ladb::OpenCutList::DesignationUtils
  end

  def test_no_name_keeps_default
    info = utils.read(@path)
    assert_nil(info[:designation])
    refute(info[:set_up])
  end

  def test_name_only
    @definition.set_attribute(DICT, 'name', 'Left Side')
    info = utils.read(@path)
    assert_equal('Left Side', info[:designation])
    refute(info[:set_up])
  end

  def test_name_and_cab_num_value
    @definition.set_attribute(DICT, 'name', 'Left Side')
    @part.set_attribute(DICT, 'cabnum', 'A3')
    info = utils.read(@path)
    assert_equal('A3 - Left Side', info[:designation])
    assert(info[:set_up])
  end

  def test_instance_name_wins
    @definition.set_attribute(DICT, 'name', 'Side')
    @part.set_attribute(DICT, 'name', 'Left Side')
    assert_equal('Left Side', utils.read(@path)[:name])
  end

  def test_parent_formula_reads_parent_not_stale_value
    @definition.set_attribute(DICT, 'name', 'Left Side')
    @definition.set_attribute(DICT, '_cabnum_formula', 'parent!cabNum')
    @definition.set_attribute(DICT, 'cabnum', 3)   # stale value from another cabinet
    assert_equal('12 - Left Side', utils.read(@path)[:designation])
  end

  def test_parent_formula_through_nested_formula
    group = @cabinet_definition.entities.add_group
    group.set_attribute(DICT, '_cabnum_formula', '=parent!CabNum')
    part = group.entities.add_instance(@definition, IDENTITY)
    @definition.set_attribute(DICT, 'name', 'Back')
    @definition.set_attribute(DICT, '_cabnum_formula', 'parent!CabNum')
    assert_equal('12 - Back', utils.read([ @cabinet, group, part ])[:designation])
  end

  def test_set_up_converts_part
    assert(utils.set_up(@part, [ @cabinet ]))
    assert_equal('KCut test side', @definition.get_attribute(DICT, 'name'))
    assert_equal('CabNum', @definition.get_attribute(DICT, '_cabnum_label'))
    assert_equal('parent!CabNum', @definition.get_attribute(DICT, '_cabnum_formula'))
    assert_equal(12.0, @part.get_attribute(DICT, 'cabnum'))
    info = utils.read(@path)
    assert(info[:set_up])
    assert_equal('12 - KCut test side', info[:designation])
  end

  def test_set_up_keeps_existing_name
    @part.set_attribute(DICT, 'name', 'Left Side')
    utils.set_up(@part, [ @cabinet ])
    assert_nil(@definition.get_attribute(DICT, 'name'))
    assert_equal('12 - Left Side', utils.read(@path)[:designation])
  end

  def test_set_up_chains_containers
    # Cabinet [12] > Drawer box (component, no CabNum) > Drawer back
    box_definition = @model.definitions.add('KCut test drawer box')
    box = @cabinet_definition.entities.add_instance(box_definition, IDENTITY)
    back = box_definition.entities.add_instance(@definition, IDENTITY)
    utils.set_up(back, [ @cabinet, box ])
    assert_equal('parent!CabNum', box_definition.get_attribute(DICT, '_cabnum_formula'))
    assert_equal('CabNum', box_definition.get_attribute(DICT, '_cabnum_label'))
    assert_equal(12.0, box.get_attribute(DICT, 'cabnum'))
    assert_equal(12.0, back.get_attribute(DICT, 'cabnum'))
    assert_equal('12 - KCut test side', utils.read([ @cabinet, box, back ])[:designation])
    assert_nil(@cabinet_definition.get_attribute(DICT, '_cabnum_formula'))   # source left alone
  end

  def test_set_up_chains_groups_on_the_group
    group = @cabinet_definition.entities.add_group
    part = group.entities.add_instance(@definition, IDENTITY)
    utils.set_up(part, [ @cabinet, group ])
    assert_equal('parent!CabNum', group.get_attribute(DICT, '_cabnum_formula'))
    assert_equal('12 - KCut test side', utils.read([ @cabinet, group, part ])[:designation])
  end

  def test_set_up_without_cab_num_ancestor_leaves_containers
    box_definition = @model.definitions.add('KCut test loose box')
    box = @model.active_entities.add_instance(box_definition, IDENTITY)
    part = box_definition.entities.add_instance(@definition, IDENTITY)
    utils.set_up(part, [ box ])
    assert_nil(box_definition.get_attribute(DICT, '_cabnum_formula'))
  end

  def test_set_up_strips_copy_suffix_from_name
    definition = @model.definitions.add('KCut test back#27')
    definition.entities.add_cpoint(ORIGIN)
    part = @cabinet_definition.entities.add_instance(definition, IDENTITY)
    utils.set_up(part, [ @cabinet ])
    assert_equal('KCut test back', definition.get_attribute(DICT, 'name'))
    assert_equal('12 - KCut test back', utils.read([ @cabinet, part ])[:designation])
    assert_equal('#5', utils.base_name('#5'))
  end

  def test_set_up_at_root_has_no_cab_num
    part = @model.active_entities.add_instance(@definition, IDENTITY)
    utils.set_up(part, nil)
    info = utils.read([ part ])
    assert_equal('KCut test side', info[:designation])
    assert(info[:set_up])
  end

end
