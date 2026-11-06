require 'json'
require_relative 'regenerator'

module Ladb; module OpenCutList; module KCut; module SketchUpAdapter

  # KCut: right-click > KCut > Edit Recipe... on a recipe group.
  #
  # Shows the recipe's parameters (assembly defaults merged with the
  # recipe's own values) in an input box and rebuilds the group with the
  # result, as one undo step. Field kind follows the default value:
  #   Float   -> length in mm, shown and entered in model units
  #   Integer -> whole number (doors, shelves, cab number)
  #   String  -> text
  # Only values that differ from the assembly defaults (or were already on
  # the recipe) are stored, so the recipe stays small and later default
  # changes still reach it.
  module RecipeEditor

    Field = Struct.new(:key, :label, :kind, :value)

    def self.fields(group)
      r = Regenerator.recipe(group)
      defaults = Assemblies.defaults(r['type'])
      params = defaults.merge(r['params'] || {})
      params.map do |k, v|
        kind = case v
               when Integer then :integer
               when Numeric then :length
               else :text
               end
        Field.new(k, k.split('_').map(&:capitalize).join(' ').sub(/\ACabnum\z/, 'Cab Number'), kind, v)
      end
    end

    # Values for UI.inputbox (lengths as Length so SketchUp shows model units).
    def self.prompt_values(fields)
      fields.map { |f| f.kind == :length ? f.value.to_f.mm : f.value }
    end

    # Parse inputbox results back into recipe params (mm, Integer, String).
    def self.parse(fields, results)
      fields.zip(results).to_h do |f, v|
        value = case f.kind
                when :length then (v.is_a?(Length) ? v.to_mm : v.to_s.to_l.to_mm).round(4)
                when :integer then Integer(v.to_s.strip, 10)
                else v.to_s
                end
        [ f.key, value ]
      end
    end

    # New params to store: changed from defaults, or already on the recipe.
    def self.changed_params(group, values)
      r = Regenerator.recipe(group)
      defaults = Assemblies.defaults(r['type'])
      own = r['params'] || {}
      values.select { |k, v| own.key?(k) || defaults[k] != v }
    end

    def self.apply(group, values)
      r = Regenerator.recipe(group)
      r['params'] = changed_params(group, values)
      group.set_attribute(Regenerator::DICT, 'recipe', JSON.generate(r))
      Regenerator.rebuild(group)
    end

    # Interactive entry point (menu).
    def self.edit(group)
      model = group.model
      fs = fields(group)
      results = UI.inputbox(fs.map(&:label), prompt_values(fs), "KCut - Edit Recipe (#{Regenerator.recipe(group)['type']})")
      return false unless results
      values = parse(fs, results)
      model.start_operation('KCut - Edit Recipe', true)
      begin
        apply(group, values)
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("KCut: could not rebuild the recipe.\n#{e.message}")
        return false
      end
      Sketchup.status_text = "KCut: rebuilt #{group.name}."
      true
    end

    def self.rebuild(groups)
      model = groups.first.model
      model.start_operation('KCut - Rebuild Recipe', true)
      begin
        groups.each { |g| Regenerator.rebuild(g) }
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("KCut: could not rebuild.\n#{e.message}")
      end
    end

  end

end; end; end; end
