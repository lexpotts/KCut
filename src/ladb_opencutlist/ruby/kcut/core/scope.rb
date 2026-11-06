module Ladb; module OpenCutList; module KCut; module Core

  # KCut: scoped variables (feature list #3).
  #
  # Pure Ruby, no SketchUp. A Scope holds named values and points to its
  # parent; lookup walks up to the nearest scope that defines the name, so a
  # value set on the project (root) is visible inside every cabinet, and a
  # cabinet can override it for everything beneath it.
  #
  # Values are numbers, strings, booleans, or expressions: a String starting
  # with "=". Expressions support + - * / ( ), unary minus, comparison-free
  # functions (LARGEST, SMALLEST, ROUND, ABS, FLOOR, CEILING), names
  # resolved through the scope chain, and cross-structure references
  # "@name.var" to any named scope registered on the root.
  #
  # An expression is evaluated in the scope that asked for the value (like
  # DC's "parent!" but any depth), so a project-level "=width - 2 * reveal"
  # uses the cabinet's own width when read from inside a cabinet.
  class Scope

    class Error < StandardError; end
    class UnknownName < Error; end
    class CycleError < Error; end

    attr_reader :name, :parent

    def initialize(values = {}, parent: nil, name: nil)
      @values = {}
      values.each { |k, v| @values[k.to_s.downcase] = v }
      @parent = parent
      @name = name&.to_s&.downcase
      @named = {} # only used on the root
      root.register(self) if @name
    end

    def root
      @parent ? @parent.root : self
    end

    def register(scope)
      @named[scope.name] = scope
    end

    def child(values = {}, name: nil)
      Scope.new(values, parent: self, name: name)
    end

    def set(key, value)
      @values[key.to_s.downcase] = value
    end

    def defines?(key)
      @values.key?(key.to_s.downcase)
    end

    # The scope that defines key, nearest first, or nil.
    def owner_of(key)
      key = key.to_s.downcase
      s = self
      s = s.parent until s.nil? || s.defines?(key)
      s
    end

    # Resolved value of key, evaluated in this scope.
    def [](key)
      resolve(key.to_s.downcase, [])
    end

    def resolve(key, stack)
      owner = owner_of(key)
      raise UnknownName, "unknown name '#{key}'" if owner.nil?
      raw = owner.raw(key)
      return raw unless raw.is_a?(String) && raw.start_with?('=')
      marker = [ object_id, key ]
      raise CycleError, "cycle: #{(stack.map(&:last) + [ key ]).join(' -> ')}" if stack.include?(marker)
      Expression.new(raw[1..], self, stack + [ marker ]).value
    end

    def raw(key)
      @values[key.to_s.downcase]
    end

    def lookup_named(name)
      root.instance_variable_get(:@named)[name.to_s.downcase] or
        raise UnknownName, "unknown scope '@#{name}'"
    end

    # Tiny safe expression evaluator (no eval).
    class Expression

      FUNCTIONS = {
        'largest' => ->(*a) { a.max },
        'smallest' => ->(*a) { a.min },
        'round' => ->(x, d = 0) { x.round(d.to_i) },
        'abs' => ->(x) { x.abs },
        'floor' => ->(x) { x.floor },
        'ceiling' => ->(x) { x.ceil },
      }.freeze

      TOKEN = /\s*(?:(\d+(?:\.\d+)?(?:e[-+]?\d+)?)|(@[a-z_]\w*\.[a-z_]\w*)|([a-z_]\w*)|(.))/i

      def initialize(source, scope, stack)
        @tokens = source.scan(TOKEN).reject { |t| t.compact.first.strip.empty? }
        @scope = scope
        @stack = stack
        @i = 0
      end

      def value
        v = _sum
        raise Error, "unexpected '#{_peek_text}'" if @i < @tokens.length
        v
      end

      private

      def _peek
        @tokens[@i]
      end

      def _peek_text
        _peek&.compact&.first
      end

      def _take(sym = nil)
        t = @tokens[@i]
        raise Error, "expected '#{sym}'" if sym && t&.at(3) != sym
        @i += 1
        t
      end

      def _sum
        v = _product
        while %w[+ -].include?(_peek&.at(3))
          op = _take[3]
          r = _product
          v = op == '+' ? v + r : v - r
        end
        v
      end

      def _product
        v = _unary
        while %w[* /].include?(_peek&.at(3))
          op = _take[3]
          r = _unary
          v = op == '*' ? v * r : v.to_f / r
        end
        v
      end

      def _unary
        if _peek&.at(3) == '-'
          _take
          return -_unary
        end
        _atom
      end

      def _atom
        t = _take
        raise Error, 'unexpected end of expression' if t.nil?
        num, ref, ident, sym = t
        return (num.include?('.') || num =~ /e/i ? num.to_f : num.to_i) if num
        if ref
          scope_name, var = ref[1..].split('.', 2)
          return @scope.lookup_named(scope_name).resolve(var.downcase, @stack)
        end
        if ident
          if _peek&.at(3) == '('
            fn = FUNCTIONS[ident.downcase] or raise Error, "unknown function '#{ident}'"
            return fn.call(*_args)
          end
          return @scope.resolve(ident.downcase, @stack)
        end
        if sym == '('
          v = _sum
          _take(')')
          return v
        end
        raise Error, "unexpected '#{sym}'"
      end

      def _args
        _take('(')
        args = []
        unless _peek&.at(3) == ')'
          args << _sum
          while _peek&.at(3) == ','
            _take
            args << _sum
          end
        end
        _take(')')
        args
      end

    end

  end

end; end; end; end
