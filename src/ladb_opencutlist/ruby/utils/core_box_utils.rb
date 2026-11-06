module Ladb::OpenCutList

  # KCut: cabinet "core box" sizing.
  #
  # A cabinet DC builds its parts from an invisible child box ("Cab Bounding
  # Box"), not from its own bounds. KCut treats that box as the cabinet's true
  # size: it is what gets measured, synced and resized. Geometry outside it
  # (open drawers, hinges, cutters, nested parts larger than it) never affects
  # the size.
  #
  # The core box wins: when the cabinet's own LenX/LenY/LenZ disagree with the
  # drawn core box, sync_from_core_box writes the core box size back to the
  # cabinet.
  module CoreBoxUtils

    DICT = 'dynamic_attributes'.freeze
    CORE_BOX_NAME = /\ACab Bounding Box(#\d+)?\z/
    AXES = %w[x y z].freeze
    TOLERANCE = 0.01 # inches

    # The core box child instance of cabinet, or nil.
    def self.core_box(cabinet)
      return nil unless cabinet.is_a?(Sketchup::ComponentInstance) || cabinet.is_a?(Sketchup::Group)
      definition = cabinet.respond_to?(:definition) ? cabinet.definition : cabinet.entities.parent
      definition.entities.find do |e|
        (e.is_a?(Sketchup::ComponentInstance) && e.definition.name =~ CORE_BOX_NAME) ||
          (e.respond_to?(:name) && e.name =~ CORE_BOX_NAME)
      end
    end

    def self.cabinet?(entity)
      !core_box(entity).nil?
    end

    # Drawn size of the core box in the cabinet's axes: [x, y, z] in inches.
    def self.core_size(cabinet)
      box = core_box(cabinet)
      return nil if box.nil?
      b = box.definition.bounds
      s = scales(box.transformation)
      [ b.width * s[0], b.height * s[1], b.depth * s[2] ].map(&:to_f)
    end

    # Scale factors of a transformation along its own x, y, z axes
    # (Transformation#xaxis is normalized, so read the matrix columns).
    def self.scales(t)
      a = t.to_a
      [ 0, 4, 8 ].map { |o| Math.sqrt(a[o]**2 + a[o + 1]**2 + a[o + 2]**2) }
    end

    # The cabinet's own LenX/LenY/LenZ attributes: [x, y, z] in inches (nil entries when missing).
    def self.cabinet_size(cabinet)
      AXES.map do |a|
        v = cabinet.get_attribute(DICT, "len#{a}")
        v = cabinet.definition.get_attribute(DICT, "len#{a}") if v.nil? && cabinet.respond_to?(:definition)
        v.nil? ? nil : v.to_f
      end
    end

    # { :cabinet => [x,y,z], :core => [x,y,z], :axes => ['x', ...] } for the axes that disagree.
    def self.drift(cabinet)
      core = core_size(cabinet)
      return nil if core.nil?
      cab = cabinet_size(cabinet)
      axes = AXES.each_index.select { |i| cab[i].nil? || (cab[i] - core[i]).abs > TOLERANCE }.map { |i| AXES[i] }
      { :cabinet => cab, :core => core, :axes => axes }
    end

    def self.drifted?(cabinet)
      d = drift(cabinet)
      !d.nil? && !d[:axes].empty?
    end

    # Writes the core box size to the cabinet's LenX/LenY/LenZ (instance level,
    # as the DC extension does). Returns the axes changed. No redraw.
    def self.sync_from_core_box(cabinet)
      d = drift(cabinet)
      return [] if d.nil?
      d[:axes].each do |a|
        set_len(cabinet, a, d[:core][AXES.index(a)])
      end
      d[:axes]
    end

    # Sets the cabinet's size to [x, y, z] inches (nil keeps an axis) through
    # the core box: the cabinet's Len attributes and the core box's own Len
    # attributes are set together, then the cabinet is redrawn. No SketchUp
    # scaling is applied to the cabinet instance.
    # The +x/+y/+z faces move; pass anchor: [ax, ay, az] with each 0 (min side
    # fixed, default) or 1 (max side fixed) to grow toward the other side.
    def self.resize(cabinet, size, anchor: [ 0, 0, 0 ], redraw: true)
      old = core_size(cabinet)
      return false if old.nil?
      new = AXES.each_index.map { |i| size[i].nil? ? old[i] : size[i].to_f }
      # The DC extension evaluates parent!LenX as the definition's
      # _lenx_nominal times the instance scale, so the size is stored on the
      # definition. Make it unique first so other cabinets keep their size.
      cabinet.make_unique if cabinet.respond_to?(:make_unique) && cabinet.definition.count_instances > 1
      box = core_box(cabinet)
      AXES.each_with_index do |a, i|
        set_len(cabinet, a, new[i])
        cabinet.definition.set_attribute(DICT, "_len#{a}_nominal", new[i] / scales(cabinet.transformation)[i])
        set_len(box, a, new[i])
      end
      # The DC redraw doesn't resize the core box geometry (it has no Len
      # formulas on every axis), so size it directly: same origin and axes,
      # new scale. Only this hidden box is scaled, never the cabinet.
      set_box_size(box, new)
      # Keep the anchored faces in place.
      shift = Geom::Vector3d.new(*AXES.each_index.map { |i| anchor[i].to_i == 1 ? old[i] - new[i] : 0 })
      if shift.length > 0
        t = cabinet.transformation
        world = Geom::Vector3d.new(t.xaxis.normalize.to_a.map { |c| c * shift.x }) +
          Geom::Vector3d.new(t.yaxis.normalize.to_a.map { |c| c * shift.y }) +
          Geom::Vector3d.new(t.zaxis.normalize.to_a.map { |c| c * shift.z })
        cabinet.transform!(Geom::Transformation.translation(world))
      end
      redraw(cabinet) if redraw
      true
    end

    def self.redraw(cabinet)
      return false unless defined?($dc_observers) && $dc_observers
      $dc_observers.get_latest_class.redraw(cabinet, false)
      true
    rescue StandardError
      false
    end

    def self.set_box_size(box, size)
      b = box.definition.bounds
      t = box.transformation
      factors = [ b.width, b.height, b.depth ].each_with_index.map { |d, i| d.to_f > 0 ? size[i].to_f / d.to_f : 1.0 }
      box.transformation = Geom::Transformation.axes(t.origin, t.xaxis, t.yaxis, t.zaxis) *
        Geom::Transformation.scaling(b.min, *factors)
    end

    def self.set_len(entity, axis, inches)
      entity.set_attribute(DICT, "len#{axis}", inches.to_f)
      entity.set_attribute(DICT, "_len#{axis}_nominal", inches.to_f)
    end

  end

end
