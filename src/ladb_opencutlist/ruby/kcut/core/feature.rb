module Ladb; module OpenCutList; module KCut; module Core

  # KCut: feature records and the feature-type registry (notes/architecture.md).
  #
  # Pure Ruby, no SketchUp. A Feature is stored data: a type, parameters
  # (values or "=expressions" resolved through a Scope), an optional anchor
  # (host face plane) and where it lives:
  #   :definition  shared by every copy of the component
  #   :instance    this copy only
  # A feature type turns resolved params into Ops (plain hashes); only the
  # SketchUp adapter turns Ops into geometry.
  class Feature

    SCHEMA_VERSION = 1
    SCOPES = %i[definition instance].freeze

    attr_reader :type, :id, :params, :anchor, :scope

    def initialize(type:, id:, params: {}, anchor: nil, scope: :definition)
      raise ArgumentError, "scope must be one of #{SCOPES}" unless SCOPES.include?(scope.to_sym)
      @type = type.to_s
      @id = id.to_s
      @params = params.transform_keys { |k| k.to_s.downcase }
      @anchor = anchor
      @scope = scope.to_sym
    end

    # Params resolved through scope: the feature's own params come first,
    # falling back to the scope chain for anything not set on it.
    def resolved_params(scope)
      local = scope.child(@params)
      @params.keys.to_h { |k| [ k, local[k] ] }.merge('__scope' => local)
    end

    def evaluate(scope)
      Feature.type(@type).evaluate(resolved_params(scope), self)
    end

    def to_h
      { 'v' => SCHEMA_VERSION, 'type' => @type, 'id' => @id, 'params' => @params,
        'anchor' => @anchor, 'scope' => @scope.to_s }
    end

    def self.from_h(h)
      h = migrate(h)
      new(type: h['type'], id: h['id'], params: h['params'] || {}, anchor: h['anchor'],
          scope: (h['scope'] || 'definition').to_sym)
    end

    # Upgrade older stored records. Add a step here when SCHEMA_VERSION bumps.
    def self.migrate(h)
      v = h['v'] || 1
      raise ArgumentError, "feature schema v#{v} is newer than this KCut (v#{SCHEMA_VERSION})" if v > SCHEMA_VERSION
      h
    end

    # -- Registry --------------------------------------------------------

    @types = {}

    # Register a feature type. The block receives (params, feature) and
    # returns an Array of Op hashes, e.g. { op: :bore, center: [x, y], dia:, depth: }.
    def self.register(type, &evaluate)
      raise ArgumentError, 'block required' unless evaluate
      @types[type.to_s] = Struct.new(:name, :evaluator) do
        def evaluate(params, feature)
          evaluator.call(params, feature)
        end
      end.new(type.to_s, evaluate)
    end

    def self.type(name)
      @types[name.to_s] or raise ArgumentError, "unknown feature type '#{name}'"
    end

    def self.types
      @types.keys
    end

  end

end; end; end; end
