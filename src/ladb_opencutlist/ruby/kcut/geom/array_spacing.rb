module Ladb; module OpenCutList; module KCut; module Geom

  # KCut: positions for an array of items along a length (feature list #13).
  #
  # Pure Ruby, no SketchUp. All values are plain numbers in one unit.
  # Positions are item *centers* measured from the start of the length;
  # spacing ("pitch") is center to center.
  #
  #   padding  distance from each end to the first/last item's edge
  #   size     item width along the array (0 for points, e.g. hole centers)
  #
  # Modes:
  #   :count          exactly `count` items spread across the span (ends included)
  #   :min_spacing    as many items as fit with pitch >= spacing
  #   :max_spacing    as few items as needed so pitch <= spacing
  #   :fixed_spacing  pitch == spacing exactly; leftover split evenly to both ends
  #   :distributed    `count` items; end gaps equal the gaps between items
  #                   (ignores padding)
  #
  # grid: snap every position to the nearest multiple of `grid` from
  # `grid_origin` (e.g. 32 mm system). Snapping can change the spacing; positions
  # that would land outside the span are dropped, as are duplicates.
  module ArraySpacing

    MODES = %i[count min_spacing max_spacing fixed_spacing distributed].freeze
    EPS = 1e-9

    Layout = Struct.new(:positions, :pitch) do
      def count
        positions.length
      end
    end

    def self.layout(length:, mode:, count: nil, spacing: nil, padding: 0, size: 0, grid: nil, grid_origin: 0)
      raise ArgumentError, "unknown mode #{mode.inspect}" unless MODES.include?(mode)
      raise ArgumentError, 'length must be >= 0' if length.negative?

      positions = case mode
                  when :distributed
                    n = _require_count(count)
                    gap = (length - n * size).to_f / (n + 1)
                    return Layout.new([], nil) if gap < -EPS
                    Array.new(n) { |i| gap * (i + 1) + size * i + size / 2.0 }
                  else
                    first = padding + size / 2.0
                    span = length - 2 * padding - size
                    return Layout.new([], nil) if span < -EPS
                    span = 0.0 if span < 0
                    _span_positions(mode, first, span, count, spacing)
                  end

      if grid
        pad = mode == :distributed ? 0 : padding
        positions = _snap(positions, grid, grid_origin, pad + size / 2.0, length - pad - size / 2.0)
      end
      Layout.new(positions, positions.length > 1 ? positions[1] - positions[0] : nil)
    end

    def self._span_positions(mode, first, span, count, spacing)
      case mode
      when :count
        _even(first, span, _require_count(count))
      when :min_spacing
        s = _require_spacing(spacing)
        _even(first, span, (span / s + EPS).floor + 1)
      when :max_spacing
        s = _require_spacing(spacing)
        _even(first, span, (span / s - EPS).ceil + 1)
      when :fixed_spacing
        s = _require_spacing(spacing)
        n = (span / s + EPS).floor + 1
        offset = (span - (n - 1) * s) / 2.0
        Array.new(n) { |i| first + offset + s * i }
      end
    end

    def self._even(first, span, n)
      return [ first + span / 2.0 ] if n == 1
      step = span.to_f / (n - 1)
      Array.new(n) { |i| first + step * i }
    end

    def self._snap(positions, grid, origin, min, max)
      raise ArgumentError, 'grid must be > 0' unless grid.positive?
      positions.map { |p| origin + ((p - origin) / grid).round * grid }
               .select { |p| p >= min - EPS && p <= max + EPS }
               .uniq { |p| (p / EPS).round }
    end

    def self._require_count(count)
      raise ArgumentError, 'count must be >= 1' unless count.is_a?(Integer) && count >= 1
      count
    end

    def self._require_spacing(spacing)
      raise ArgumentError, 'spacing must be > 0' unless spacing.is_a?(Numeric) && spacing.positive?
      spacing.to_f
    end

    private_class_method :_span_positions, :_even, :_snap, :_require_count, :_require_spacing

  end

end; end; end; end
