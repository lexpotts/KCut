module Ladb::OpenCutList

  # KCut: default Dynamic Component attributes for parts created by the
  # Smart Draw tool, so a new part is ready to use inside a cabinet DC:
  #
  #   - CabNum   formula =parent!cabNum
  #   - LenX, LenY, LenZ, X, Y, Z shown in the Component Attributes editor
  #   - Name     filled with the part's definition name
  #
  # SketchUp's DC extension stores attribute names in lower case in the
  # "dynamic_attributes" dictionary. An attribute shows in the editor when its
  # "_<name>_label" key is set; formulas are stored without the leading "=".
  # Lengths are stored in inches whatever the model units.
  module DynamicAttributesUtils

    DICT = 'dynamic_attributes'.freeze

    CAB_NUM_KEY = 'cabnum'.freeze
    CAB_NUM_LABEL = 'CabNum'.freeze
    CAB_NUM_FORMULA = 'parent!cabNum'.freeze

    SIZE_LABELS = { 'lenx' => 'LenX', 'leny' => 'LenY', 'lenz' => 'LenZ' }.freeze
    POSITION_LABELS = { 'x' => 'X', 'y' => 'Y', 'z' => 'Z' }.freeze

    METRIC_LENGTH_UNITS = [ 2, 3, 4 ].freeze # Length::Millimeter, Centimeter, Meter

    # Adds the default attributes to a freshly drawn part.
    # - instance: the new Sketchup::ComponentInstance
    # - parent: the group/component the part was drawn in (nil at model root)
    def self.add_part_defaults(instance, parent = nil)
      return if instance.nil? || !instance.valid?
      definition = instance.definition

      definition.set_attribute(DICT, '_formatversion', 1.0) if definition.get_attribute(DICT, '_formatversion').nil?
      definition.set_attribute(DICT, '_lengthunits', length_units(definition.model)) if definition.get_attribute(DICT, '_lengthunits').nil?

      # Name
      set_name(instance, definition.name)

      # CabNum = parent!cabNum
      definition.set_attribute(DICT, "_#{CAB_NUM_KEY}_label", CAB_NUM_LABEL)
      definition.set_attribute(DICT, "_#{CAB_NUM_KEY}_formula", CAB_NUM_FORMULA)
      cab_num = parent_cab_num(parent)
      definition.set_attribute(DICT, CAB_NUM_KEY, cab_num) unless cab_num.nil?

      # LenX, LenY, LenZ
      size(instance).each do |key, value|
        definition.set_attribute(DICT, "_#{key}_label", SIZE_LABELS[key])
        definition.set_attribute(DICT, key, value)
        instance.set_attribute(DICT, key, value)
      end

      # X, Y, Z
      position(instance).each do |key, value|
        definition.set_attribute(DICT, "_#{key}_label", POSITION_LABELS[key])
        instance.set_attribute(DICT, key, value)
      end

    end

    # Updates the Name attribute after the part's definition was renamed,
    # unless the user already gave the Name attribute a value of their own.
    def self.update_name(instance, old_name)
      return if instance.nil? || !instance.valid?
      definition = instance.definition
      current = definition.get_attribute(DICT, 'name')
      return unless current.nil? || current == old_name
      set_name(instance, definition.name)
    end

    def self.set_name(instance, name)
      definition = instance.definition
      definition.set_attribute(DICT, '_name', name)
      definition.set_attribute(DICT, '_name_label', 'Name')
      definition.set_attribute(DICT, 'name', name)
    end

    # Value of the parent's cabNum attribute (instance first, then definition).
    def self.parent_cab_num(parent)
      return nil unless parent.is_a?(Sketchup::ComponentInstance) || parent.is_a?(Sketchup::Group)
      return nil unless parent.valid?
      value = parent.get_attribute(DICT, CAB_NUM_KEY)
      value = parent.definition.get_attribute(DICT, CAB_NUM_KEY) if value.nil?
      value
    end

    # Part size in inches, including the instance's scaling.
    def self.size(instance)
      bounds = instance.definition.bounds
      t = instance.transformation
      {
        'lenx' => bounds.width.to_f * X_AXIS.transform(t).length.to_f,
        'leny' => bounds.height.to_f * Y_AXIS.transform(t).length.to_f,
        'lenz' => bounds.depth.to_f * Z_AXIS.transform(t).length.to_f,
      }
    end

    # Part origin in inches, in its parent's coordinates. While a group or
    # component is open for editing SketchUp reports the transformations of
    # its entities in world coordinates, so the edit transform is removed.
    def self.position(instance)
      origin = instance.transformation.origin
      model = instance.model
      if instance.parent.is_a?(Sketchup::ComponentDefinition) && !model.active_path.nil? &&
         model.active_path.last.definition == instance.parent
        origin = origin.transform(model.edit_transform.inverse)
      end
      { 'x' => origin.x.to_f, 'y' => origin.y.to_f, 'z' => origin.z.to_f }
    end

    def self.length_units(model)
      unit = model.nil? ? nil : model.options['UnitsOptions']['LengthUnit']
      METRIC_LENGTH_UNITS.include?(unit) ? 'CENTIMETERS' : 'INCHES'
    end

  end

end
