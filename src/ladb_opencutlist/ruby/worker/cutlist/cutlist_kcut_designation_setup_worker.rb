module Ladb::OpenCutList

  require_relative '../../utils/designation_utils'
  require_relative '../../utils/path_utils'

  # KCut: converts the instances of the given parts so their designation
  # comes from DC attributes: CabNum = parent!CabNum, Name added if missing
  # (see DesignationUtils). One undo step.
  class CutlistKcutDesignationSetupWorker

    def initialize(cutlist,

                   part_ids: nil

    )

      @cutlist = cutlist

      @part_ids = part_ids

    end

    # -----

    def run
      return { :errors => [ 'default.error' ] } unless @cutlist
      return { :errors => [ 'tab.cutlist.error.obsolete_cutlist' ] } if @cutlist.obsolete?

      model = Sketchup.active_model
      return { :errors => [ 'tab.cutlist.error.no_model' ] } unless model

      paths = @cutlist.get_parts(@part_ids)
                      .flat_map { |part| part.respond_to?(:entity_serialized_paths) ? part.entity_serialized_paths : [] }
                      .uniq
                      .map { |serialized_path| PathUtils.unserialize_path(serialized_path) }
                      .compact
                      .select { |path| path.last.is_a?(Sketchup::ComponentInstance) }
      return { :errors => [ 'default.error' ] } if paths.empty?

      count = 0
      model.start_operation('KCut - Use Parent CabNum', true)
      begin
        paths.each { |path| count += 1 if DesignationUtils.set_up(path.last, path[0...-1]) }
        model.commit_operation
      rescue => e
        model.abort_operation
        return { :errors => [ [ 'core.error.exception', { :error => e.message } ] ] }
      end

      { :success => true, :count => count }
    end

  end

end
