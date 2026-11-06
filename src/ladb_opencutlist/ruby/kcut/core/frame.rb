module Ladb; module OpenCutList; module KCut; module Core

  # KCut: a feature's anchor, i.e. a plane on a host face (feature list #2).
  #
  # Pure Ruby. origin is a point on the face, u and v lie in the face,
  # n points *into* the material. Features work in (u, v) on the face;
  # the frame maps them to 3D, so a feature moves only within its face.
  class Frame

    attr_reader :origin, :u, :v, :n

    def initialize(origin:, u:, v:, n:)
      @origin = origin.map(&:to_f)
      @u = u.map(&:to_f)
      @v = v.map(&:to_f)
      @n = n.map(&:to_f)
    end

    # 3D point at (a, b) on the face, w deep into the material.
    def point(a, b, w = 0)
      Array.new(3) { |i| @origin[i] + @u[i] * a + @v[i] * b + @n[i] * w }
    end

    # Turn a feature's 2D op into 3D (bores: center + direction into material).
    def place(op)
      case op[:op]
      when :bore
        op.merge(center: point(*op[:center]), dir: @n)
      else
        op
      end
    end

    def to_h
      { 'origin' => @origin, 'u' => @u, 'v' => @v, 'n' => @n }
    end

    def self.from_h(h)
      new(origin: h['origin'], u: h['u'], v: h['v'], n: h['n'])
    end

  end

end; end; end; end
