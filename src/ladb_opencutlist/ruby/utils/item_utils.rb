module Ladb::OpenCutList

  require 'digest'
  require 'cgi'
  require_relative '../model/attributes/material_attributes'

  # KCut: "report as single item" components.
  #
  # A component instance switched to this mode is listed as ONE part (for
  # example a drawer box ordered from a supplier) instead of being opened up
  # into the parts it is made of:
  #
  #   - parts inside it that are not hardware are left out of the parts list;
  #     hardware inside it (slides, ...) is still listed;
  #   - it reports into an "item material" of type Hardware (e.g. "Drawers"),
  #     so it gets its own group, count and price in the parts list and the
  #     estimate. The item material is NOT painted on the instance;
  #   - it reports its size (LenX, LenY, LenZ) and every DC attribute users
  #     can see in Component Options as columns.
  #
  # The switch is stored per instance in the plugin's attribute dictionary.
  module ItemUtils

    ITEM_MATERIAL_KEY = 'kcut_item_material'.freeze
    DEFAULT_ITEM_MATERIAL_NAME = 'Drawers'.freeze

    DC_DICT = 'dynamic_attributes'.freeze
    SIZE_KEYS = [ [ 'lenx', 'LenX' ], [ 'leny', 'LenY' ], [ 'lenz', 'LenZ' ] ].freeze
    VISIBLE_ACCESSES = [ 'VIEW', 'TEXTBOX', 'LIST' ].freeze
    LENGTH_UNITS = [ 'INCHES', 'FEET', 'MILLIMETERS', 'CENTIMETERS', 'METERS' ].freeze

    # -- Switch --

    # Name of the item material the instance reports into, or nil when the
    # instance is listed the default OCL way.
    def self.item_material_name(entity)
      return nil unless entity.is_a?(Sketchup::ComponentInstance) && entity.valid?
      name = entity.get_attribute(Plugin::ATTRIBUTE_DICTIONARY, ITEM_MATERIAL_KEY, nil)
      name.is_a?(String) && !name.empty? ? name : nil
    end

    def self.item?(entity)
      !item_material_name(entity).nil?
    end

    # Switches instances to "single item" mode, reporting into material_name.
    # Creates the hardware item material if needed. Returns the material.
    def self.set_item(instances, material_name)
      instances = instances.grep(Sketchup::ComponentInstance)
      return nil if instances.empty?
      material = ensure_item_material(instances.first.model, material_name)
      instances.each { |instance| instance.set_attribute(Plugin::ATTRIBUTE_DICTIONARY, ITEM_MATERIAL_KEY, material.name) }
      material
    end

    # Back to the default OCL behaviour (the component's parts are listed).
    def self.clear_item(instances)
      instances.grep(Sketchup::ComponentInstance).each do |instance|
        instance.delete_attribute(Plugin::ATTRIBUTE_DICTIONARY, ITEM_MATERIAL_KEY)
      end
    end

    # Existing material of that name (made a Hardware material if it isn't
    # typed yet), or a new Hardware material.
    def self.ensure_item_material(model, material_name)
      name = material_name.to_s.strip
      name = DEFAULT_ITEM_MATERIAL_NAME if name.empty?
      material = model.materials[name]
      if material.nil?
        material = model.materials.add(name)
        material.color = Sketchup::Color.new(120, 120, 120)
      end
      attributes = MaterialAttributes.new(material)
      if attributes.type == MaterialAttributes::TYPE_UNKNOWN
        attributes.type = MaterialAttributes::TYPE_HARDWARE
        attributes.write_to_attributes
      end
      material
    end

    # Names of the model's Hardware materials (choices for the item material).
    def self.hardware_material_names(model)
      model.materials
           .select { |material| MaterialAttributes.new(material).type == MaterialAttributes::TYPE_HARDWARE }
           .map(&:name)
           .sort
    end

    # -- Reported values --

    # Ordered list of { :key, :label, :value } reported for an item instance:
    # LenX, LenY, LenZ first, then every DC attribute users can see in
    # Component Options (sorted by label). Instance values override
    # definition values, like the DC extension does.
    def self.read_values(instance)
      return [] unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
      definition_dict = instance.definition.attribute_dictionary(DC_DICT)
      instance_dict = instance.attribute_dictionary(DC_DICT)
      meta = lambda { |key| definition_dict ? definition_dict[key] : nil }
      value_of = lambda do |key|
        value = instance_dict ? instance_dict[key] : nil
        value = definition_dict[key] if value.nil? && definition_dict
        value
      end

      values = []

      # Size
      bounds = nil
      SIZE_KEYS.each_with_index do |(key, label), index|
        raw = value_of.call(key)
        if raw.nil? || raw.to_s.strip.empty?
          bounds ||= instance.definition.bounds
          raw = [ bounds.width, bounds.height, bounds.depth ][index] * [ instance.transformation.xscale, instance.transformation.yscale, instance.transformation.zscale ][index]
        end
        values << { :key => key, :label => label, :value => format_length(raw), :sort => numeric?(raw) ? raw.to_f : raw.to_s }
      end

      # User-facing DC attributes
      if definition_dict
        keys = definition_dict.keys
                              .select { |k| k.start_with?('_') && k.end_with?('_access') }
                              .map { |k| k[1...-('_access'.length)] }
                              .select { |k| VISIBLE_ACCESSES.include?(meta.call("_#{k}_access").to_s.upcase) }
                              .reject { |k| SIZE_KEYS.any? { |size_key, _| size_key == k } }
        rows = keys.map do |key|
          label = (meta.call("_#{key}_formlabel") || meta.call("_#{key}_label") || key).to_s
          raw = value_of.call(key)
          access = meta.call("_#{key}_access")
          options = meta.call("_#{key}_options")
          value = format_value(raw, access, options, meta.call("_#{key}_units"))
          is_list_label = access.to_s.upcase == 'LIST' && options.is_a?(String) && !list_label(options, raw).nil?
          { :key => key, :label => label, :value => value, :sort => sort_key(raw, value, is_list_label) }
        end
        values.concat(rows.sort_by { |row| row[:label].downcase })
      end

      values
    end

    # Short string that changes whenever a reported value changes. Used to keep
    # instances with different values on separate rows.
    def self.signature(values)
      Digest::MD5.hexdigest(values.map { |v| "#{v[:key]}=#{v[:value]}" }.join('|'))
    end

    def self.format_value(raw, access, options, units)
      return '' if raw.nil?
      if access.to_s.upcase == 'LIST' && options.is_a?(String)
        label = list_label(options, raw)
        return label unless label.nil?
      end
      units = units.to_s.upcase
      return format_length(raw) if LENGTH_UNITS.include?(units) && numeric?(raw)
      if units == 'BOOLEAN'
        return %w[1 1.0 true TRUE].include?(raw.to_s) ? 'Yes' : 'No'
      end
      return raw.to_s.sub(/\.0\z/, '') if numeric?(raw)
      raw.to_s
    end

    # "&Yes=1&No=0&" -> label for the stored value
    def self.list_label(options, raw)
      options.split('&').each do |pair|
        next if pair.empty?
        label, value = pair.split('=', 2).map { |s| CGI.unescape(s.to_s) }
        next if value.nil?
        return label if value == raw.to_s || (numeric?(value) && numeric?(raw) && value.to_f == raw.to_f)
      end
      nil
    end

    # Sort key for the parts list columns: the plain number for numbers and
    # lengths (inches), the displayed text for list labels and strings.
    def self.sort_key(raw, display, is_list_label = false)
      return raw.to_f if numeric?(raw) && !is_list_label
      display.to_s
    end

    def self.numeric?(value)
      return true if value.is_a?(Numeric)
      !!(value.to_s.strip =~ /\A[-+]?\d*\.?\d+(e[-+]?\d+)?\z/i)
    end

    def self.format_length(value)
      return value.to_s unless numeric?(value)
      Sketchup.format_length(value.to_f)
    end

  end

end
