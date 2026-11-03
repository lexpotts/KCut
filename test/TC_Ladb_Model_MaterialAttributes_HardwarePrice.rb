require 'testup/testcase'

require_relative '../src/ladb_opencutlist/ruby/model/attributes/material_attributes'

# KCut: unit price on hardware materials, used by the estimate for hardware
# parts that have no price of their own.
# Runs inside an aborted operation so the open model is left untouched.
class TC_Ladb_Model_MaterialAttributes_HardwarePrice < TestUp::TestCase

  def setup
    @model = Sketchup.active_model
    @model.start_operation('KCut test: hardware price', true)
    @material = @model.materials.add('KCut test hardware')
  end

  def teardown
    @model.abort_operation
  end

  def attributes_for(type, std_prices)
    attrs = Ladb::OpenCutList::MaterialAttributes.new(@material)
    attrs.type = type
    attrs.std_prices = std_prices
    attrs.write_to_attributes
    Ladb::OpenCutList::MaterialAttributes.new(@material)
  end

  def price(val)
    "#{val}#{Ladb::OpenCutList::UnitUtils::UV_SEPARATOR}$_i"
  end

  def test_hardware_unit_price_is_saved_and_read_back
    attrs = attributes_for(Ladb::OpenCutList::MaterialAttributes::TYPE_HARDWARE, [ { 'val' => price('2.35'), 'dim' => nil } ])
    assert_in_delta(2.35, attrs.hardware_unit_price, 1e-9)
    refute_empty(attrs.std_prices, 'hardware materials keep their own std_prices')
  end

  def test_hardware_without_price_is_zero
    attrs = attributes_for(Ladb::OpenCutList::MaterialAttributes::TYPE_HARDWARE, [])
    assert_equal(0.0, attrs.hardware_unit_price)
  end

  def test_other_types_have_no_hardware_unit_price
    attrs = attributes_for(Ladb::OpenCutList::MaterialAttributes::TYPE_SOLID_WOOD, [ { 'val' => price('9'), 'dim' => nil } ])
    assert_equal(0.0, attrs.hardware_unit_price)
  end

end
