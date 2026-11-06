require_relative '../core/scope'
require_relative '../core/feature'
require_relative '../core/frame'
require_relative '../geom/array_spacing'
require_relative '../features/bore_row'

module Ladb; module OpenCutList; module KCut

  # KCut: assemblies turn a recipe into parts (pure Ruby, no SketchUp).
  #
  # A recipe is data:
  #   { 'v' => 1, 'type' => 'base_cabinet', 'params' => { 'width' => 952.5, ... },
  #     'features' => [ { 'type' => 'bore_row', 'id' => ..., 'part' => 'Left End',
  #                       'frame' => { origin/u/v/n }, 'params' => { ... } } ] }
  #
  # build returns { parts: [...], annotations: [...] } in the assembly's own
  # coordinates (x width, y depth with front at 0, z up; recipe units).
  # Parts: { name:, tag:, min:, max:, ops: [ {op: :cut_box, min:, max:} |
  #          {op: :bore, center:, dir:, dia:, depth:} ] }
  # Annotations: { name:, tag:, lines: [ [p1, p2], ... ] }
  module Assemblies

    RECIPE_VERSION = 1
    @types = {}

    def self.register(type, defaults = {}, &build)
      @types[type.to_s] = { defaults: defaults, build: build }
    end

    def self.types
      @types.keys
    end

    def self.defaults(type)
      (@types[type.to_s] or raise ArgumentError, "unknown assembly '#{type}'")[:defaults]
    end

    def self.build(recipe, project)
      v = recipe['v'] || 1
      raise ArgumentError, "recipe v#{v} is newer than this KCut (v#{RECIPE_VERSION})" if v > RECIPE_VERSION
      type = @types[recipe['type'].to_s] or raise ArgumentError, "unknown assembly '#{recipe['type']}'"
      params = type[:defaults].merge(recipe['params'] || {})
      scope = project.child(params, name: params['cabnum'] ? "cab#{params['cabnum']}" : nil)
      out = type[:build].call(scope)

      # Extra features stored on the recipe, attached to a named part's face.
      (recipe['features'] || []).each do |h|
        part = out[:parts].find { |p| p[:name] == h['part'] } or
          raise ArgumentError, "feature '#{h['id']}': no part '#{h['part']}'"
        frame = Core::Frame.from_h(h['frame'])
        part[:ops].concat(Core::Feature.from_h(h).evaluate(scope).map { |op| frame.place(op) })
      end
      out
    end

    # Evaluate a feature on a frame: [op, ...] in 3D.
    def self.feature_ops(scope, frame, type, id, params)
      Core::Feature.new(type: type, id: id, params: params).evaluate(scope).map { |op| frame.place(op) }
    end

    # -- base_cabinet ---------------------------------------------------
    # Frameless-style base: two ends with toe notch, bottom, back, rear
    # stretcher, front cleat, toe kick, adjustable shelves on 32 mm pin rows,
    # overlay doors with hinge cup bores and door swing markers.
    # Defaults measured from Old Gulph "Base Cabinet#8" (cab 20).
    register('base_cabinet', {
      'name' => 'Base Cabinet', 'width' => 952.5, 'depth' => 527.05, 'height' => 694.3,
      'front_inset' => 19.05, 'doors' => 2, 'shelves' => 1, 'rev_top' => 41.9,
    }) do |s|
      w = s['width'].to_f
      d = s['depth'].to_f
      h = s['height'].to_f
      pt = s['panel_th'].to_f
      bt = s['back_th'].to_f
      yf = s['front_inset'].to_f
      yb = d - bt
      toe_h = s['toe_h'].to_f
      toe_d = s['toe_depth'].to_f
      parts = []
      anns = []
      part = ->(name, tag, min, max, ops = []) { parts << { name: name, tag: tag, min: min, max: max, ops: ops } }

      # Ends: toe notch is a through cut; pin rows bored on the inner face.
      pin_params = {
        'length' => '=height', 'mode' => 'fixed_spacing', 'spacing' => '=pin_grid',
        'padding' => '=toe_h + panel_th + pin_end', 'grid' => '=pin_grid',
        'grid_origin' => '=toe_h + panel_th + pin_end', 'dia' => '=pin_dia', 'depth' => '=pin_depth',
      }
      [ [ 'Left End', 0.0, -1 ], [ 'Right End', w - pt, 1 ] ].each do |name, x0, side|
        inner_x = side < 0 ? pt : x0
        frame = Core::Frame.new(origin: [ inner_x, yf, 0 ], u: [ 0, 0, 1 ], v: [ 0, 1, 0 ], n: [ side, 0, 0 ])
        ops = [ { op: :cut_box, min: [ x0 - 1, yf - 1, -1 ], max: [ x0 + pt + 1, yf + toe_d, toe_h ] } ]
        [ s['pin_inset'], (yb - yf) - s['pin_inset'] ].each_with_index do |y, i|
          ops.concat(feature_ops(s, frame, 'bore_row', "#{name} pins #{i + 1}", pin_params.merge('y' => y)))
        end
        part.call(name, 'Carcass', [ x0, yf, 0 ], [ x0 + pt, yb, h ], ops)
      end

      part.call('Bottom', 'Carcass', [ pt, yf, toe_h ], [ w - pt, yb, toe_h + pt ])
      part.call('Back', 'Carcass', [ 0, yb, toe_h ], [ w, d, h ])
      part.call('Rear Stretcher', 'Carcass', [ pt, yb - pt, h - s['stretcher_w'] ], [ w - pt, yb, h ])
      part.call('Front Cleat', 'Carcass', [ pt, yf, h - s['cleat_w'] ], [ w - pt, yf + pt, h ])
      part.call('Toe Kick', 'Carcass', [ pt, yf + toe_d, 0 ], [ w - pt, yf + toe_d + pt, toe_h ])

      # Shelves spread evenly in the interior.
      z0 = toe_h + pt
      z1 = h - s['cleat_w']
      Geom::ArraySpacing.layout(length: z1 - z0, mode: :distributed, count: s['shelves'].to_i, size: pt).positions.each_with_index do |zc, i|
        z = z0 + zc - pt / 2
        c = s['shelf_clear'].to_f
        part.call("Shelf #{i + 1}", 'Shelves', [ pt + c, yf + 3, z ], [ w - pt - c, yb, z + pt ])
      end if s['shelves'].to_i > 0

      # Doors: overlay in front of the carcass, hinge cups on the back face.
      n = s['doors'].to_i
      if n > 0
        rev = s['reveal'].to_f
        gap = s['door_gap'].to_f
        dz0 = toe_h + pt + rev
        dz1 = h - s['rev_top']
        dw = (w - 2 * pt - 2 * rev - (n - 1) * gap) / n
        dth = s['door_th'].to_f
        n.times do |i|
          x0 = pt + rev + i * (dw + gap)
          x1 = x0 + dw
          hinge_left = n == 1 || i < n / 2.0
          hx = hinge_left ? x0 : x1
          frame = Core::Frame.new(origin: [ hx, yf, dz0 ], u: [ 0, 0, 1 ], v: [ hinge_left ? 1 : -1, 0, 0 ], n: [ 0, -1, 0 ])
          cups = feature_ops(s, frame, 'bore_row', "Door #{i + 1} hinges", {
            'length' => dz1 - dz0, 'mode' => 'max_spacing', 'spacing' => '=hinge_max_spacing',
            'padding' => '=hinge_end', 'y' => '=hinge_cup_edge', 'dia' => '=hinge_cup_dia', 'depth' => '=hinge_cup_depth',
          })
          part.call("Door #{i + 1}", 'Doors / DF', [ x0, yf - dth, dz0 ], [ x1, yf, dz1 ], cups)

          # Swing marker on the door face: lines from the free edge's corners to the hinge side's mid height.
          fx = hinge_left ? x1 : x0
          y = yf - dth - 0.5
          apex = [ hx, y, (dz0 + dz1) / 2 ]
          anns << { name: "Door #{i + 1} swing", tag: 'KCut/Door Swing',
                    lines: [ [ [ fx, y, dz0 ], apex ], [ [ fx, y, dz1 ], apex ] ] }
        end
      end

      { parts: parts, annotations: anns }
    end

  end

end; end; end
