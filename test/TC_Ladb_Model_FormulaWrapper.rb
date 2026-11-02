require 'testup/testcase'

require_relative '../src/ladb_opencutlist/ruby/model/formula/formula_wrapper'

# KCut: DC attribute names are stored lower case by SketchUp, so formulas must
# find them whatever case the user types (e.g. @instance.get_dc_attribute("LenX")).
class TC_Ladb_Model_FormulaWrapper < TestUp::TestCase

  def setup
    @model = Sketchup.active_model
    @model.start_operation('KCut test: FormulaWrapper', true)

    @group = @model.active_entities.add_group
    @group.entities.add_cpoint(ORIGIN)
    @group.set_attribute('dynamic_attributes', 'lenx', 'group-value')

    definition = @model.definitions.add('KCut test FormulaWrapper')
    definition.entities.add_cpoint(ORIGIN)
    definition.set_attribute('dynamic_attributes', 'lenx', 'definition-value')
    @instance = @model.active_entities.add_instance(definition, IDENTITY)
    @instance.set_attribute('dynamic_attributes', 'lenx', 'instance-value')
  end

  def teardown
    @model.abort_operation  # Leave the open model untouched
  end

  def test_instance_get_dc_attribute_ignores_case
    wrapper = Ladb::OpenCutList::ComponentInstanceFormulaWrapper.new(@instance)
    %w[lenx LenX LENX].each do |key|
      assert_equal('instance-value', wrapper.get_dc_attribute(key), "key #{key}")
    end
    assert_equal('instance-value', wrapper.get_dc_attribute(:LenX))
  end

  def test_group_get_dc_attribute_ignores_case
    wrapper = Ladb::OpenCutList::GroupFormulaWrapper.new(@group)
    %w[lenx LenX LENX].each do |key|
      assert_equal('group-value', wrapper.get_dc_attribute(key), "key #{key}")
    end
  end

  def test_definition_get_dc_attribute_ignores_case
    wrapper = Ladb::OpenCutList::ComponentDefinitionFormulaWrapper.new(@instance.definition)
    %w[lenx LenX LENX].each do |key|
      assert_equal('definition-value', wrapper.get_dc_attribute(key), "key #{key}")
    end
  end

end
