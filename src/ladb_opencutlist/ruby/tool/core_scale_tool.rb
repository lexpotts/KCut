module Ladb::OpenCutList

  require_relative '../utils/core_box_utils'

  # KCut: resize a cabinet by its core box ("Cab Bounding Box").
  #
  # Grips sit on the 6 faces of the core box only: open drawers, hinges and
  # anything else outside the box are ignored. Dragging a grip shows a preview
  # box; releasing sets the new size through CoreBoxUtils.resize (one undo
  # step, one DC redraw). The opposite face stays put. The cabinet instance is
  # never scaled.
  #
  # Keyboard (Measurements box): after hovering or dragging a grip, type a
  # length to set that axis ("24", "610mm"), or "W,D,H" to set all three
  # (leave one empty to keep it, e.g. ",,30"). Esc cancels a drag.
  class CoreScaleTool

    GRIP_PX = 7
    PICK_PX = 12
    MIN_SIZE = 1.0     # inches
    ROUND_TO = 1 / 16.0 # inches

    COLOR_BOX = Sketchup::Color.new(0, 120, 255)
    COLOR_PREVIEW = Sketchup::Color.new(255, 120, 0)
    COLOR_GRIP = Sketchup::Color.new(255, 255, 255)
    COLOR_GRIP_HOT = Sketchup::Color.new(255, 120, 0)

    # A grip: axis index 0..2, side -1 (min face) or +1 (max face).
    Grip = Struct.new(:axis, :side)

    GRIPS = [ 0, 1, 2 ].flat_map { |a| [ Grip.new(a, 1), Grip.new(a, -1) ] }.freeze

    def initialize(cabinet = nil, transformation = nil)
      set_cabinet(cabinet, transformation || (cabinet ? cabinet.transformation : nil))
    end

    # -- Tool lifecycle --

    def activate
      if @cabinet.nil?
        sel = Sketchup.active_model.selection.to_a
        cab = sel.length == 1 && CoreBoxUtils.cabinet?(sel.first) ? sel.first : nil
        set_cabinet(cab, cab ? Sketchup.active_model.edit_transform * cab.transformation : nil)
      end
      update_status
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def onCancel(_reason, view)
      @drag = nil
      @preview = nil
      update_status
      view.invalidate
    end

    def enableVCB?
      true
    end

    def getExtents
      bb = Geom::BoundingBox.new
      corners(@origin, @size).each { |p| bb.add(p) } if @cabinet
      corners(@preview[:origin], @preview[:size]).each { |p| bb.add(p) } if @preview
      bb
    end

    # -- Mouse --

    def onMouseMove(_flags, x, y, view)
      if @drag
        @preview = drag_preview(view, x, y)
        Sketchup.vcb_value = format_length(@preview[:size][@drag.axis]) if @preview
      else
        @hot = grip_at(view, x, y)
        Sketchup.vcb_value = format_length(@size[@hot.axis]) if @hot
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      if @drag
        # Second click of click-move-click.
        finish_drag
      elsif @cabinet && (grip = grip_at(view, x, y))
        @drag = grip
        @last_grip = grip
        @preview = nil
        Sketchup.vcb_label = AXIS_LABELS[grip.axis]
      else
        pick_cabinet(view, x, y)
      end
      update_status
      view.invalidate
    end

    def onLButtonUp(_flags, _x, _y, view)
      # Press-drag-release finishes here; a click without moving keeps the
      # grip so the next click finishes (click-move-click).
      return unless @drag && @preview && (@preview[:size][@drag.axis] - @size[@drag.axis]).abs > 1e-6
      finish_drag
      view.invalidate
    end

    def finish_drag
      preview = @preview
      grip = @drag
      @drag = nil
      @preview = nil
      apply(preview[:size], grip) if preview && (preview[:size][grip.axis] - @size[grip.axis]).abs > 1e-6
      update_status
    end

    def onUserText(text, view)
      return if @cabinet.nil?
      size = @size.dup
      if text.include?(',') || text.include?(';')
        parts = text.split(/[,;]/, -1)
        parts.first(3).each_with_index { |t, i| size[i] = parse_length(t) || size[i] }
        grip = Grip.new(0, 1)
      else
        grip = @drag || @hot || @last_grip
        if grip.nil?
          UI.beep
          Sketchup.status_text = 'KCut: hover a grip first, or type W,D,H.'
          return
        end
        v = parse_length(text)
        return UI.beep if v.nil?
        size[grip.axis] = v
      end
      @drag = nil
      @preview = nil
      apply(size, grip)
      view.invalidate
    end

    # -- Drawing --

    def draw(view)
      return if @cabinet.nil?

      view.line_width = 2
      view.line_stipple = ''
      view.drawing_color = COLOR_BOX
      draw_box(view, @origin, @size)

      if @preview
        view.line_stipple = '-'
        view.drawing_color = COLOR_PREVIEW
        draw_box(view, @preview[:origin], @preview[:size])
        view.line_stipple = ''
        p = face_center(@preview[:origin], @preview[:size], @drag)
        view.draw_text(view.screen_coords(p), "#{AXIS_LABELS[@drag.axis]} #{format_length(@preview[:size][@drag.axis])}", color: COLOR_PREVIEW, size: 14)
      end

      return if @drag
      GRIPS.each do |g|
        pt = view.screen_coords(face_center(@origin, @size, g))
        view.draw_points([ pt ], GRIP_PX * 2, 2, hot?(g) ? COLOR_GRIP_HOT : COLOR_GRIP)  # 2 = filled square
        view.draw_points([ pt ], GRIP_PX * 2, 1, COLOR_BOX)                                # 1 = open square
      end
    end

    # -- Geometry (public for tests) --

    attr_reader :cabinet, :origin, :size, :axes

    # World corners of a box from origin, size and @axes.
    def corners(origin, size)
      [ 0, 1 ].product([ 0, 1 ], [ 0, 1 ]).map do |i, j, k|
        origin.offset(@axes[0], size[0] * i).offset(@axes[1], size[1] * j).offset(@axes[2], size[2] * k)
      end
    end

    def face_center(origin, size, grip)
      f = [ 0.5, 0.5, 0.5 ]
      f[grip.axis] = grip.side > 0 ? 1.0 : 0.0
      origin.offset(@axes[0], size[0] * f[0]).offset(@axes[1], size[1] * f[1]).offset(@axes[2], size[2] * f[2])
    end

    # New origin and size when the given grip's face moves by delta inches
    # outward (negative = inward). The opposite face stays put.
    def moved(grip, delta)
      size = @size.dup
      new_len = snap(size[grip.axis] + delta)
      new_len = MIN_SIZE if new_len < MIN_SIZE
      change = new_len - size[grip.axis]
      size[grip.axis] = new_len
      origin = grip.side < 0 ? @origin.offset(@axes[grip.axis], -change) : @origin.clone
      { :origin => origin, :size => size }
    end

    private

    AXIS_LABELS = %w[Width Depth Height].freeze

    def set_cabinet(cabinet, transformation)
      @cabinet = nil
      @hot = @drag = @preview = @last_grip = nil
      return if cabinet.nil? || !CoreBoxUtils.cabinet?(cabinet)
      @cabinet = cabinet
      @transformation = transformation
      refresh_frame
    end

    # World origin, axes (unit vectors) and size (inches) of the core box.
    def refresh_frame
      box = CoreBoxUtils.core_box(@cabinet)
      t = @transformation * box.transformation
      @origin = box.definition.bounds.min.transform(t)
      @axes = [ t.xaxis, t.yaxis, t.zaxis ].map(&:normalize)
      @size = CoreBoxUtils.core_size(@cabinet)
      @cabinet_scales = CoreBoxUtils.scales(@transformation)
    end

    def grip_at(view, x, y)
      return nil if @cabinet.nil?
      best = nil
      best_d = PICK_PX
      GRIPS.each do |g|
        sp = view.screen_coords(face_center(@origin, @size, g))
        d = Math.hypot(sp.x - x, sp.y - y)
        if d <= best_d
          best = g
          best_d = d
        end
      end
      best
    end

    def hot?(grip)
      @hot && @hot.axis == grip.axis && @hot.side == grip.side
    end

    # Projects the mouse ray onto the grip's axis line.
    def drag_preview(view, x, y)
      grip = @drag
      start = face_center(@origin, @size, grip)
      dir = @axes[grip.axis]
      ray = view.pickray(x, y)
      pts = Geom.closest_points([ start, dir ], ray)
      return @preview if pts.nil? || pts.first.nil?
      along = (pts.first - start) % dir # signed distance along +axis
      moved(grip, along * grip.side / @cabinet_scales[grip.axis])
    end

    def apply(size, grip)
      model = Sketchup.active_model
      anchor = [ 0, 0, 0 ]
      anchor[grip.axis] = grip.side < 0 ? 1 : 0
      model.start_operation('KCut - Resize Cabinet', true)
      begin
        CoreBoxUtils.resize(@cabinet, size.map { |v| v < MIN_SIZE ? MIN_SIZE : v }, anchor: anchor)
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("KCut: could not resize the cabinet.\n#{e.message}")
      end
      # resize may have moved the instance (anchored face) or made it unique.
      @transformation = model.edit_transform * @cabinet.transformation if @cabinet.valid?
      refresh_frame if @cabinet.valid?
      update_status
    end

    def pick_cabinet(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      path = ph.path_at(0)
      cab = nil
      tr = Sketchup.active_model.edit_transform
      (path || []).each do |e|
        next unless e.respond_to?(:transformation)
        tr *= e.transformation
        if CoreBoxUtils.cabinet?(e)
          cab = e
          break
        end
      end
      set_cabinet(cab, tr)
      Sketchup.active_model.selection.clear
      Sketchup.active_model.selection.add(cab) if cab && cab.parent == Sketchup.active_model.active_entities.parent
    end

    def update_status
      Sketchup.status_text = if @cabinet.nil?
        'KCut Resize: click a cabinet.'
      elsif @drag
        'KCut Resize: move to size, click to finish. Type a length. Esc cancels.'
      else
        cab_num = @cabinet.get_attribute(CoreBoxUtils::DICT, 'cabnum')
        "KCut Resize#{cab_num ? " cab #{cab_num.to_s.sub(/\.0\z/, '')}" : ''}: #{@size.map { |v| format_length(v) }.join(' x ')}. Drag a grip, or type W,D,H."
      end
      Sketchup.vcb_label = @drag ? AXIS_LABELS[@drag.axis] : 'Size'
    end

    def draw_box(view, origin, size)
      c = corners(origin, size)
      edges = [ [ 0, 1 ], [ 2, 3 ], [ 4, 5 ], [ 6, 7 ], [ 0, 2 ], [ 1, 3 ], [ 4, 6 ], [ 5, 7 ], [ 0, 4 ], [ 1, 5 ], [ 2, 6 ], [ 3, 7 ] ]
      view.draw(GL_LINES, edges.flat_map { |a, b| [ c[a], c[b] ] })
    end

    def snap(v)
      (v / ROUND_TO).round * ROUND_TO
    end

    def parse_length(text)
      t = text.to_s.strip
      return nil if t.empty?
      t.to_l.to_f
    rescue ArgumentError
      nil
    end

    def format_length(v)
      v.to_l.to_s
    end

  end

end
