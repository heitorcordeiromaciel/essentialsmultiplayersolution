module VMS

  class TournamentPreviewTrainer
    attr_accessor :name, :party
    def initialize(name, party)
      @name = name
      @party = party
    end
  end

  VMS_PREVIEW_PREFIX = "VMS_PLAYER:"

  TOURNAMENT_PARAMETERS_PATH = "PBS/Plugins/Tournament Selection/tournament_parameters.txt"

  def self.write_tournament_parameters(poke_max, double)
    poke_max = poke_max.to_i.clamp(1, 6)
    existing = File.exist?(TOURNAMENT_PARAMETERS_PATH) ? File.readlines(TOURNAMENT_PARAMETERS_PATH) : []
    vms_start = existing.index { |line| line.strip == "[VMS]" }
    existing.slice!(vms_start, 10) if vms_start
    File.open(TOURNAMENT_PARAMETERS_PATH, "w") do |f|
      f.puts "[VMS]"
      f.puts "poke_max = #{poke_max}"
      f.puts "battle_mode = #{double ? "2v2" : "1v1"}"
      f.puts "battle_start = false"
      f.puts "show_items = false"
      f.puts "show_trainer_face = false"
      f.puts "oppo_team_access = false"
      f.puts "oppo_custom_choice = nil"
      f.puts "input_tone = default"
      f.puts "animation_speed = normal"
      unless existing.empty?
        f.puts "#-------------------------------"
        existing.each { |line| f.print(line) }
      end
    end
  end

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
