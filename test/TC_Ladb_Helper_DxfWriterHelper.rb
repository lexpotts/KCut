require 'testup/testcase'
require 'stringio'

# KCut: DXF part labels must be centered in the part even for readers that
# ignore TEXT alignment (e.g. VCarve, which draws from the start point, group 10).
# Pure output test: writes to a StringIO, touches no model.
class TC_Ladb_Helper_DxfWriterHelper < TestUp::TestCase

  class Writer
    include Ladb::OpenCutList::DxfWriterHelper
    def initialize
      @_dxf_handle = 0
    end
    def _dxf_generate_id
      @_dxf_handle += 1
      @_dxf_handle.to_s(16).upcase
    end
  end

  RATIO = Ladb::OpenCutList::DxfWriterHelper::DXF_TEXT_CHAR_WIDTH_RATIO

  def setup
    @writer = Writer.new
  end

  # Returns { code => [ values ] } for the first TEXT entity in the output.
  def write_label(*args)
    io = StringIO.new
    @writer.send(:_dxf_write_label, io, *args)
    lines = io.string.lines.map(&:strip)
    groups = Hash.new { |h, k| h[k] = [] }
    lines.each_slice(2) { |code, value| groups[code.to_i] << value }
    groups
  end

  def assert_point(groups, xcode, ex, ey)
    assert_in_delta ex, groups[xcode].first.to_f, 1e-6, "group #{xcode}"
    assert_in_delta ey, groups[xcode + 10].first.to_f, 1e-6, "group #{xcode + 10}"
  end

  def test_horizontal_label_start_is_left_of_center
    # 200 x 100 rect at origin, text 'AB': height = min(60, 50, 100) = 50
    g = write_label(0, 0, 200, 100, 'AB', 200, 100, 0, 0, 0, 'TXT')
    h = 50.0
    half_w = 2 * h * RATIO / 2.0
    assert_point(g, 11, 100, 50)                 # alignment point = part center
    assert_point(g, 10, 100 - half_w, 50 - h / 2) # start point = left / baseline
    assert_equal '1', g[72].first                # still centered for AutoCAD-like readers
    assert_equal '2', g[73].first
  end

  def test_rotated_label_start_follows_text_direction
    g = write_label(0, 0, 100, 200, 'AB', 200, 100, 0, 0, 90, 'TXT')
    h = 50.0
    half_w = 2 * h * RATIO / 2.0
    assert_point(g, 11, 50, 100)
    # Text runs up (+Y), its "up" points to -X: start is below and to the right of center
    assert_point(g, 10, 50 + h / 2, 100 - half_w)
  end

  def test_label_offset_moves_both_points
    g = write_label(10, 20, 200, 100, 'X', 200, 100, 5, -5, 0, 'TXT')
    h = 50.0
    assert_point(g, 11, 115, 65)
    assert_point(g, 10, 115 - h * RATIO / 2.0, 65 - h / 2)
  end

  def test_plain_text_start_defaults_to_alignment_point
    io = StringIO.new
    @writer.send(:_dxf_write_text, io, 3.0, 4.0, 10.0, 'X')
    lines = io.string.lines.map(&:strip)
    groups = Hash.new { |h, k| h[k] = [] }
    lines.each_slice(2) { |code, value| groups[code.to_i] << value }
    assert_point(groups, 10, 3, 4)
    assert_point(groups, 11, 3, 4)
  end

end
