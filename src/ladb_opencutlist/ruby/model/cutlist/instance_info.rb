module Ladb::OpenCutList

  require_relative '../data_container'
  require_relative '../../model/geom/scale3d'
  require_relative '../../utils/path_utils'
  require_relative '../../utils/designation_utils'

  class InstanceInfo < DataContainer

    attr_accessor :size, :definition_bounds
    attr_accessor :kcut_item_material_name, :kcut_within_item   # KCut: single items (see ItemUtils)
    attr_reader :path

    @size = nil
    @definition_bounds = nil

    def initialize(path = [])
      @path = path
    end

    # -----

    # KCut: the DC Name (with CabNum in front, see DesignationUtils) is always
    # used when the part has one, whatever try_from_dynamic_attributes says.
    def read_name(try_from_dynamic_attributes = false)
      designation = kcut_designation[:designation]
      return [ designation, true ] unless designation.nil?
      [ entity.definition.name, false ]
    end

    def kcut_designation
      @kcut_designation ||= DesignationUtils.read(@path)
    end

    # -----

    def definition
      return @definition if @definition
      @definition = entity.definition if entity.is_a?(Sketchup::ComponentInstance)
    end

    def entity
      @path.last
    end

    def layer
      entity.layer
    end

    def serialized_path
      return @serialized_path if @serialized_path
      @serialized_path = PathUtils.serialize_path(@path)
    end

    def named_path
      return @named_path if @named_path
      @named_path = PathUtils.get_named_path(@path).join('.')
    end

    def transformation
      return @transformation if @transformation
      @transformation = PathUtils.get_transformation(@path)
    end

    def scale
      return @scale if @scale
      @scale = Scale3d.create_from_transformation(transformation)
    end

    def flipped
      return @flipped if @flipped
      @flipped = TransformationUtils::flipped?(transformation)
    end

    # -----

    def size
      return @size if @size
      Size3d.new
    end

  end

end