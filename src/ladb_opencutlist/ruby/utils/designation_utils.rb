module Ladb::OpenCutList

  require_relative 'dynamic_attributes_utils'

  # KCut: part designation from Dynamic Component attributes.
  #
  # A part whose DC "Name" attribute is set is listed under that name. When it
  # also has a "CabNum" value, the cabinet number comes first:
  #
  #   CabNum 12, Name "Left Side"   ->  "12 - Left Side"
  #   no CabNum, Name "Left Side"   ->  "Left Side"
  #   no Name                       ->  definition name (OCL default)
  #
  # A part is "set up" when it has both a Name and a CabNum attribute. Parts
  # that aren't can be converted with set_up: CabNum becomes =parent!CabNum and
  # Name is added (filled with the definition name) when it is missing.
  # Containers in between that have no CabNum (a drawer box in a cabinet) are
  # chained with parent!CabNum too.
  #
  # CabNum given by the formula parent!CabNum is read straight from the parent
  # in the part's path, so the list is right even before the DC extension has
  # redrawn the part (and when one definition is used in several cabinets).
  module DesignationUtils

    DICT = DynamicAttributesUtils::DICT
    NAME_KEY = 'name'.freeze
    CAB_NUM_KEY = DynamicAttributesUtils::CAB_NUM_KEY
    CAB_NUM_LABEL = DynamicAttributesUtils::CAB_NUM_LABEL
    PARENT_CAB_NUM_FORMULA = 'parent!CabNum'.freeze
    SEPARATOR = ' - '.freeze

    MAX_DEPTH = 32

    # Designation of the part at the end of path (Array of groups/instances
    # from the model root or active path down to the part).
    # Returns { :name, :cab_num, :designation, :set_up }; :designation is nil
    # when the part has no DC Name.
    def self.read(path)
      entity = path.is_a?(Array) ? path.last : path
      return { :name => nil, :cab_num => nil, :designation => nil, :set_up => false } unless dc_entity?(entity)
      path = [ entity ] unless path.is_a?(Array)

      name = dc_value(entity, NAME_KEY)
      name = name.nil? ? nil : name.to_s.strip
      name = nil if name && name.empty?

      cab_num = format_cab_num(cab_num(path))

      designation = nil
      unless name.nil?
        designation = cab_num.nil? ? name : "#{cab_num}#{SEPARATOR}#{name}"
      end

      { :name => name, :cab_num => cab_num, :designation => designation, :set_up => !name.nil? && cab_num_attribute?(entity) }
    end

    def self.set_up?(path)
      read(path)[:set_up]
    end

    # Converts a part: CabNum = parent!CabNum, Name added if missing (definition
    # name). parent is the group/component the part sits in (nil at model root),
    # or the whole path down to it; its CabNum is copied to the part right away
    # so the value shows before the DC extension redraws.
    # Returns true if the part was changed.
    def self.set_up(instance, parent = nil)
      return false unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
      definition = instance.definition

      definition.set_attribute(DICT, '_formatversion', 1.0) if definition.get_attribute(DICT, '_formatversion').nil?
      definition.set_attribute(DICT, '_lengthunits', DynamicAttributesUtils.length_units(definition.model)) if definition.get_attribute(DICT, '_lengthunits').nil?

      # Name
      DynamicAttributesUtils.set_name(instance, base_name(definition.name)) if dc_value(instance, NAME_KEY).to_s.strip.empty?

      # CabNum = parent!CabNum (an instance-level formula would win over it)
      definition.set_attribute(DICT, "_#{CAB_NUM_KEY}_label", CAB_NUM_LABEL)
      definition.set_attribute(DICT, "_#{CAB_NUM_KEY}_formula", PARENT_CAB_NUM_FORMULA)
      instance.delete_attribute(DICT, "_#{CAB_NUM_KEY}_formula") unless instance.get_attribute(DICT, "_#{CAB_NUM_KEY}_formula").nil?
      parent = parent_path(parent) unless parent.is_a?(Array)
      chain_containers(parent)
      value = parent.empty? ? nil : cab_num(parent)
      if value.nil?
        instance.delete_attribute(DICT, CAB_NUM_KEY) unless instance.get_attribute(DICT, CAB_NUM_KEY).nil?
      else
        instance.set_attribute(DICT, CAB_NUM_KEY, value)
      end

      true
    end

    # Containers between a part and the nearest ancestor that has its own
    # CabNum (e.g. a drawer box inside a cabinet) get CabNum = parent!CabNum
    # too, so the number reaches the part through the DC formulas. Containers
    # that already chain (parent!CabNum) are left as they are. Nothing changes
    # when no ancestor in path has a CabNum. Returns the containers changed.
    def self.chain_containers(path)
      return [] unless path.is_a?(Array) && !path.empty?
      source_index = path.rindex { |entity| dc_entity?(entity) && !dc_value(entity, CAB_NUM_KEY).nil? && !parent_reference?(dc_value(entity, "_#{CAB_NUM_KEY}_formula")) }
      return [] if source_index.nil?
      changed = []
      ((source_index + 1)...path.length).each do |index|
        container = path[index]
        next unless dc_entity?(container)
        unless parent_reference?(dc_value(container, "_#{CAB_NUM_KEY}_formula"))
          # Groups keep their DC attributes on themselves, components on their definition
          holder = container.is_a?(Sketchup::Group) ? container : container.definition
          holder.set_attribute(DICT, "_#{CAB_NUM_KEY}_label", CAB_NUM_LABEL)
          holder.set_attribute(DICT, "_#{CAB_NUM_KEY}_formula", PARENT_CAB_NUM_FORMULA)
          container.delete_attribute(DICT, "_#{CAB_NUM_KEY}_formula") if container.is_a?(Sketchup::ComponentInstance) && !container.get_attribute(DICT, "_#{CAB_NUM_KEY}_formula").nil?
          changed << container
        end
        # Value now, so it shows before the DC extension redraws
        value = cab_num(path[0..index])
        container.set_attribute(DICT, CAB_NUM_KEY, value) unless value.nil?
      end
      changed
    end

    # -- Internals --

    def self.dc_entity?(entity)
      (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) && entity.valid?
    end

    # DC value: instance first, then definition (like the DC extension).
    # Blank strings count as no value.
    def self.dc_value(entity, key)
      value = entity.get_attribute(DICT, key)
      value = entity.definition.get_attribute(DICT, key) if value.nil? && entity.respond_to?(:definition)
      value = nil if value.is_a?(String) && value.strip.empty?
      value
    end

    def self.cab_num_attribute?(entity)
      !dc_value(entity, CAB_NUM_KEY).nil? || !dc_value(entity, "_#{CAB_NUM_KEY}_formula").nil? || !dc_value(entity, "_#{CAB_NUM_KEY}_label").nil?
    end

    def self.parent_reference?(formula)
      !!(formula.to_s.strip.sub(/\A=/, '').strip =~ /\Aparent!cabnum\z/i)
    end

    # Raw CabNum of the last entity of path, following parent!CabNum formulas
    # up the path.
    def self.cab_num(path, depth = 0)
      entity = path.last
      return nil unless dc_entity?(entity) && depth < MAX_DEPTH
      if path.length >= 2 && parent_reference?(dc_value(entity, "_#{CAB_NUM_KEY}_formula"))
        value = cab_num(path[0...-1], depth + 1)
        return value unless value.nil?
      end
      dc_value(entity, CAB_NUM_KEY)
    end

    # Path from the root down to entity (entity's own parents, for a part
    # selected in SketchUp). Uses the active path when entity is in it.
    def self.parent_path(entity)
      return [] unless dc_entity?(entity)
      model = entity.model
      active_path = model ? (model.active_path || []) : []
      index = active_path.index(entity)
      return active_path[0..index] unless index.nil?
      [ entity ]
    end

    # Definition name without the "#27" SketchUp adds to copies:
    # "Drawer Back#27" -> "Drawer Back". Kept as is if nothing would remain.
    def self.base_name(name)
      stripped = name.to_s.sub(/\s*#\d+\z/, '').strip
      stripped.empty? ? name.to_s : stripped
    end

    # 12.0 -> "12", "A3" -> "A3"
    def self.format_cab_num(value)
      return nil if value.nil?
      if value.is_a?(Float) && value == value.round
        value.round.to_s
      elsif value.is_a?(String) && value.strip =~ /\A[-+]?\d+\.0+\z/
        value.strip.to_f.round.to_s
      else
        s = value.to_s.strip
        s.empty? ? nil : s
      end
    end

  end

end
