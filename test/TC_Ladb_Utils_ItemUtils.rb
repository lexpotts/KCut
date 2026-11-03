require 'testup/testcase'

require_relative '../src/ladb_opencutlist/ruby/utils/item_utils'
require_relative '../src/ladb_opencutlist/ruby/worker/cutlist/cutlist_generate_worker'
require_relative '../src/ladb_opencutlist/ruby/worker/cutlist/cutlist_estimate_worker'

# KCut: components reported as single items (drawer boxes ordered from a
# supplier). Builds a small "drawer box" made of two wood parts and one
# hardware part, inside an aborted operation so the open model is untouched.
class TC_Ladb_Utils_ItemUtils < TestUp::TestCase

  O = Ladb::OpenCutList
  DC = 'dynamic_attributes'

  def setup
    @model = Sketchup.active_model
    @model.start_operation('KCut test: ItemUtils', true)

    @wood = @model.materials.add('KCut test wood')
    attrs = O::MaterialAttributes.new(@wood)
    attrs.type = O::MaterialAttributes::TYPE_SOLID_WOOD
    attrs.write_to_attributes

    @slide_material = @model.materials.add('KCut test slide')
    attrs = O::MaterialAttributes.new(@slide_material)
    attrs.type = O::MaterialAttributes::TYPE_HARDWARE
    attrs.write_to_attributes

    @box_definition = @model.definitions.add('KCut test drawer box')
    add_part(@box_definition, 'KCut test side', [ 0, 0, 0 ], [ 20, 0.5, 5 ], @wood)
    add_part(@box_definition, 'KCut test bottom', [ 0, 1, 0 ], [ 20, 15, 0.5 ], @wood)
    add_part(@box_definition, 'KCut test slide part', [ 0, 16, 0 ], [ 20, 0.5, 1 ], @slide_material)

    # Visible DC attributes, as the user would add them in the DC editor
    @box_definition.set_attribute(DC, 'lenx', 20.0)
    @box_definition.set_attribute(DC, 'leny', 16.5)
    @box_definition.set_attribute(DC, 'lenz', 5.0)
    set_dc(@box_definition, 'species', 'Species', 'LIST', 'maple', '&Baltic%20Birch=bb&Maple=maple&')
    set_dc(@box_definition, 'contents', 'Contents', 'TEXTBOX', 'Cutlery tray')
    set_dc(@box_definition, 'secret', 'Secret', 'NONE', 'hidden')

    @wrapper_definition = @model.definitions.add('KCut test drawer')
    @box = @wrapper_definition.entities.add_instance(@box_definition, IDENTITY)
    @wrapper = @model.active_entities.add_instance(@wrapper_definition, Geom::Transformation.new([ 500, 500, 0 ]))
  end

  def teardown
    @model.abort_operation
  end

  def add_part(parent_definition, name, origin, size, material)
    definition = @model.definitions.add(name)
    face = definition.entities.add_face([ 0, 0, 0 ], [ size[0], 0, 0 ], [ size[0], size[1], 0 ], [ 0, size[1], 0 ])
    face.reverse! if face.normal.z < 0
    face.pushpull(size[2])
    instance = parent_definition.entities.add_instance(definition, Geom::Transformation.new(origin))
    instance.material = material
    instance
  end

  def set_dc(definition, key, label, access, value, options = nil)
    definition.set_attribute(DC, "_#{key}_label", label)
    definition.set_attribute(DC, "_#{key}_formlabel", label)
    definition.set_attribute(DC, "_#{key}_access", access)
    definition.set_attribute(DC, "_#{key}_options", options) if options
    definition.set_attribute(DC, key, value)
  end

  def generate
    O::CutlistGenerateWorker.new(active_entity: @wrapper, active_path: []).run
  end

  def part_names(cutlist)
    cutlist.groups.flat_map { |group| group.parts.map(&:name) }.sort
  end

  # -----

  def test_default_lists_the_parts
    refute(O::ItemUtils.item?(@box))
    assert_equal([ 'KCut test bottom', 'KCut test side', 'KCut test slide part' ], part_names(generate))
  end

  def test_item_replaces_wood_parts_and_keeps_hardware
    material = O::ItemUtils.set_item([ @box ], 'KCut test drawers')
    assert_equal(O::MaterialAttributes::TYPE_HARDWARE, O::MaterialAttributes.new(material).type)
    assert_nil(@box.material, 'the item material must not be painted on the instance')

    cutlist = generate
    assert_equal([ 'KCut test drawer box', 'KCut test slide part' ], part_names(cutlist))
    group = cutlist.groups.find { |g| g.material_name == 'KCut test drawers' }
    refute_nil(group)
    assert_equal(1, group.parts.first.count)
  end

  def test_item_reports_visible_dc_values
    O::ItemUtils.set_item([ @box ], 'KCut test drawers')
    group = generate.groups.find { |g| g.material_name == 'KCut test drawers' }
    assert_equal([ 'LenX', 'LenY', 'LenZ', 'Contents', 'Species' ], group.item_columns)
    values = group.parts.first.item_values_by_label
    assert_equal('Maple', values['Species'][:value], 'list values show their label')
    assert_equal('Cutlery tray', values['Contents'][:value])
    assert_equal(Sketchup.format_length(20.0), values['LenX'][:value])
    assert_in_delta(16.5, values['LenY'][:sort], 1e-9)
    refute(values.key?('Secret'), 'attributes hidden from users are not reported')
  end

  def test_instance_values_override_definition
    O::ItemUtils.set_item([ @box ], 'KCut test drawers')
    @box.set_attribute(DC, 'contents', 'Spice insert')
    values = O::ItemUtils.read_values(@box)
    assert_equal('Spice insert', values.find { |v| v[:label] == 'Contents' }[:value])
  end

  def test_switch_back_to_default
    O::ItemUtils.set_item([ @box ], 'KCut test drawers')
    O::ItemUtils.clear_item([ @box ])
    refute(O::ItemUtils.item?(@box))
    assert_equal([ 'KCut test bottom', 'KCut test side', 'KCut test slide part' ], part_names(generate))
  end

  def test_missing_item_material_warns
    O::ItemUtils.set_item([ @box ], 'KCut test drawers')
    @box.set_attribute(O::Plugin::ATTRIBUTE_DICTIONARY, O::ItemUtils::ITEM_MATERIAL_KEY, 'KCut test does not exist')
    cutlist = generate
    assert(cutlist.warnings.any? { |w| w.is_a?(Array) && w[0] == 'tab.cutlist.warning.kcut_item_material_missing' })
    refute_includes(part_names(cutlist), 'KCut test side', 'parts of the item stay hidden')
  end

  def test_item_material_price_reaches_the_estimate
    material = O::ItemUtils.set_item([ @box ], 'KCut test drawers')
    attrs = O::MaterialAttributes.new(material)
    attrs.std_prices = [ { 'val' => '85 $_i', 'dim' => nil } ]
    attrs.write_to_attributes
    cutlist = generate
    group = cutlist.groups.find { |g| g.material_name == 'KCut test drawers' }
    worker = O::CutlistEstimateWorker.new(cutlist, part_ids: group.parts.map(&:id))
    worker.run(:start)
    20.times { r = worker.run(:advance); break unless r.is_a?(Hash) && r[:running] }
    entry = worker.estimate_def.group_defs[O::MaterialAttributes::TYPE_HARDWARE].entry_defs.find { |e| e.respond_to?(:part_defs) && e.part_defs.any? { |p| p.cutlist_part.name == 'KCut test drawer box' } }
    refute_nil(entry)
    assert_in_delta(85.0, entry.part_defs.find { |p| p.cutlist_part.name == 'KCut test drawer box' }.total_cost, 1e-9)
  end

end
