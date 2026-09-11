module VMS

  class TournamentPreviewTrainer
    attr_accessor :name, :party
    def initialize(name, party)
      @name = name
      @party = party
    end
  end

  VMS_PREVIEW_PREFIX = "VMS_PLAYER:"

  def self.ensure_tournament_selection_installed
    return if @tournament_selection_installed
    return unless Object.private_method_defined?(:pbLoadTrainer) || Object.method_defined?(:pbLoadTrainer)
    Object.class_eval do
      alias_method :vms_ts_pbLoadTrainer, :pbLoadTrainer
      def pbLoadTrainer(trainer_type, trainer_name, version = 0)
        if trainer_name.is_a?(String) && trainer_name.start_with?(VMS::VMS_PREVIEW_PREFIX)
          remote_id = trainer_name[VMS::VMS_PREVIEW_PREFIX.length..-1].to_i
          player = VMS.get_player(remote_id)
          return VMS::TournamentPreviewTrainer.new(player&.name || "???", player&.party&.dup || [])
        end
        vms_ts_pbLoadTrainer(trainer_type, trainer_name, version)
      end
    end
    @tournament_selection_installed = true
  end
end
