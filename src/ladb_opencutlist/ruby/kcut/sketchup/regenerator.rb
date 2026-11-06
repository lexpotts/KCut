require 'json'
require_relative '../core/scope'
require_relative '../assemblies/base_cabinet'

module Ladb; module OpenCutList; module KCut; module SketchUpAdapter

  # KCut: builds SketchUp geometry from recipes (notes/architecture.md).
  #
  # The only KCut layer that touches SketchUp. A recipe group stores its
  # recipe as JSON in the 'kcut' dictionary; everything inside the group is
  # generated and is thrown away and rebuilt on every change. Booleans
  # (Solid Tools, SketchUp Pro) only ever run on that generated copy, so
  # resizing re-applies cuts to the new size and nothing is ever lost.
  #
  # Callers wrap calls in model.start_operation / commit_operation.
  module Regenerator

    DICT = 'kcut'.freeze
    SHOP_FILE = File.join(__dir__, '..', 'shop', 'default_standards.json')
    CHORD_TOLERANCE_MM = 0.1
    CUTTER_OVERSHOOT_MM = 0.1

    # -- Project scope (model root) -------------------------------------

    # Copy the shop standards onto the model unless it already has a project.
    def self.seed_project(model, shop_file = SHOP_FILE)
      return false if model.get_attribute(DICT, 'project')
      model.set_attribute(DICT, 'project', File.read(shop_file))
      true
    end

    def self.project_values(model)
      json = model.get_attribute(DICT, 'project') or raise 'model has no KCut project; call seed_project first'
      JSON.parse(json).reject { |k, _| k.start_with?('_') }
    end

    def self.set_project_value(model, key, value)
      values = JSON.parse(model.get_attribute(DICT, 'project'))
      values[key.to_s] = value
      model.set_attribute(DICT, 'project', JSON.generate(values))
    end

    # -- Recipe groups ---------------------------------------------------

    def self.recipe(group)
      json = group.get_attribute(DICT, 'recipe')
      json && JSON.parse(json)
    end

    def self.recipe_group?(entity)
      entity.is_a?(Sketchup::Group) && !entity.get_attribute(DICT, 'recipe').nil?
    end

    def self.create(entities, recipe, transformation = IDENTITY)
      group = entities.add_group
      group.transformation = transformation
      group.set_attribute(DICT, 'recipe', JSON.generate(recipe))
      rebuild(group)
      group
    end

    # Merge new params into the recipe and rebuild.
    def self.update(group, params)
      r = recipe(group)
      r['params'] = (r['params'] || {}).merge(params)
      group.set_attribute(DICT, 'recipe', JSON.generate(r))
      rebuild(group)
    end

    def self.rebuild(group)
      model = group.model
      r = recipe(group)
      project = Core::Scope.new(project_values(model))
      out = Assemblies.build(r, project)
      mm = ->(a) { ::Geom::Point3d.new(*a.map(&:mm)) }

      group.entities.clear!
      group.name = "#{r.dig('params', 'name') || r['type']} (KCut recipe)"
      out[:parts].each { |p| _build_part(group, p, mm) }
      out[:annotations].each { |a| _build_annotation(group, a, mm) }
      group
    end

    # -- Geometry ---------------------------------------------------------

    def self._build_part(parent, p, mm)
      part = _box(parent.entities, p[:min], p[:max], mm)
      unless p[:ops].empty?
        # One cutter group holding every tool body (disjoint solids), so a
        # part costs a single Boolean no matter how many holes it has.
        cutter = parent.entities.add_group
        p[:ops].each { |op| _cutter(cutter.entities, op, mm) }
        cutter.entities.grep(Sketchup::Group).each(&:explode)
        part = cutter.subtract(part) || raise("subtract failed in #{p[:name]}")
      end
      part.name = p[:name]
      part.layer = _tag(parent.model, p[:tag])
      part.set_attribute(DICT, 'part', p[:name])
      part
    end

    def self._cutter(entities, op, mm)
      case op[:op]
      when :cut_box
        _box(entities, op[:min], op[:max], mm)
      when :bore
        r = op[:dia].to_f / 2
        dir = ::Geom::Vector3d.new(*op[:dir])
        start = op[:center].each_with_index.map { |c, i| c - op[:dir][i] * CUTTER_OVERSHOOT_MM }
        g = entities.add_group
        edges = g.entities.add_circle(mm.call(start), dir, r.mm, _segments(r))
        face = g.entities.add_face(edges)
        face.reverse! if face.normal.dot(dir) < 0 # pushpull goes along the normal
        face.pushpull((op[:depth].to_f + CUTTER_OVERSHOOT_MM).mm)
        g
      end
    end

    def self._box(entities, min, max, mm)
      g = entities.add_group
      x0, y0, z0 = min
      x1, y1, = max
      face = g.entities.add_face(mm.call([ x0, y0, z0 ]), mm.call([ x1, y0, z0 ]),
                                 mm.call([ x1, y1, z0 ]), mm.call([ x0, y1, z0 ]))
      face.reverse! if face.normal.z < 0
      face.pushpull((max[2] - min[2]).mm)
      g
    end

    # Fewest segments that keep the chord within tolerance (performance goal).
    def self._segments(radius_mm)
      return 8 if radius_mm <= CHORD_TOLERANCE_MM
      n = (Math::PI / Math.acos(1 - CHORD_TOLERANCE_MM / radius_mm)).ceil
      n.clamp(8, 48)
    end

    def self._build_annotation(parent, a, mm)
      g = parent.entities.add_group
      a[:lines].each { |p1, p2| g.entities.add_line(mm.call(p1), mm.call(p2)) }
      g.name = a[:name]
      g.layer = _tag(parent.model, a[:tag], dashed: true)
      g
    end

    def self._tag(model, name, dashed: false)
      return nil if name.nil?
      tag = model.layers[name] || model.layers.add(name)
      if dashed && tag.respond_to?(:line_style=) && (style = model.line_styles['Dash'])
        tag.line_style = style
      end
      tag
    end

    private_class_method :_build_part, :_cutter, :_box, :_segments, :_build_annotation, :_tag

  end

end; end; end; end
