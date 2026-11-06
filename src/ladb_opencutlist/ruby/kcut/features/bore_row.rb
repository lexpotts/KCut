require_relative '../core/feature'
require_relative '../geom/array_spacing'

module Ladb; module OpenCutList; module KCut; module Features

  # KCut example feature: a row of bores along X on the anchor face, e.g.
  # shelf-pin holes on the 32 mm system. Shows the full path
  # params -> scope -> ArraySpacing -> Ops.
  #
  # Params: length, mode, count/spacing, padding, grid, grid_origin, y, dia, depth.
  Core::Feature.register('bore_row') do |p, _feature|
    layout = Geom::ArraySpacing.layout(
      length: p['length'],
      mode: (p['mode'] || 'fixed_spacing').to_sym,
      count: p['count'],
      spacing: p['spacing'],
      padding: p['padding'] || 0,
      grid: p['grid'],
      grid_origin: p['grid_origin'] || 0
    )
    layout.positions.map do |x|
      { op: :bore, center: [ x, p['y'] || 0 ], dia: p['dia'], depth: p['depth'] }
    end
  end

end; end; end; end
