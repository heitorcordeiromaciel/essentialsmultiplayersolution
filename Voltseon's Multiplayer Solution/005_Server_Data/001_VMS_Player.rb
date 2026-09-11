##############################################################################
# VMS Player
# ----------------------------------------------------------------------------
# This class is used to store information about a player.
# Make sure to update the same script in the server/plugin when making changes.
# ----------------------------------------------------------------------------
##############################################################################

module VMS
  class Player
    # Necessary for connections
    attr_reader :id, :address, :port, :heartbeat
    # Necessary for game
    attr_accessor :name, :map_id, :x, :y, :real_x, :real_y, :trainer_type, :direction, :pattern, :graphic
    # Additional information
    attr_accessor :party, :animation, :offset_x, :offset_y, :opacity, :stop_animation, :rf_event
    # Jumping information
    attr_accessor :jump_offset, :jumping_on_spot
    # Other data
    attr_accessor :surfing, :diving, :surf_base_coords
    # Custom information
    attr_accessor :state, :busy
    # Following Pokemon sync (see 004_Other/003_VMS_FollowerSync.rb)
    # follower holds [x, y, real_x, real_y, direction, pattern, character_name, opacity]
    # or nil when the sender's follower isn't currently active/visible.
    # rf_follower_event is client-local only (no PACKET_KEYS entry, never networked),
    # same treatment as rf_event.
    attr_accessor :follower, :rf_follower_event
    # Overworld Encounters sync (see 004_Other/004_VMS_EncounterSync.rb)
    # encounters holds, when this player is the authority for their current
    # map: [[uid, x, y, direction, pattern, character_name, opacity, pokemon_hash], ...]
    # (empty array when not authority, or authority for nothing right now).
    # encounter_claim holds [uid, seq] the moment a player battles a synced
    # encounter, so the actual authority can remove its real copy.
    # rf_encounter_events is client-local only (no PACKET_KEYS entry, never
    # networked) -- a Hash of uid => rf_event handle for that proxy.
    attr_accessor :encounters, :encounter_claim, :rf_encounter_events

    def initialize(id, address, port)
      # Used to check what values can be nil
      @can_be_nil = [:surf_base_coords, :rf_event, :follower, :encounter_claim]
      # Required for connections
      @id = id
      @address = address
      @port = port
      @heartbeat = Time.now
      # Necessary for game
      @name = ""
      @map_id = 0
      @x = 0
      @y = 0
      @real_x = 0
      @real_y = 0
      @trainer_type = nil
      @direction = 0
      @pattern = 0
      @graphic = ""
      # Additional information
      @party = []
      @animation = []
      @offset_x = 0
      @offset_y = 0
      @opacity = 255
      @stop_animation = false
      @rf_event = nil
      # Jumping information
      @jump_offset = 0
      @jumping_on_spot = false
      # Other data
      @surfing = false
      @diving = false
      @surf_base_coords = nil
      # Custom information
      @state = [:idle, nil]
      @busy = false
      # Following Pokemon sync
      @follower = nil
      @rf_follower_event = nil
      # Overworld Encounters sync
      @encounters = []
      @encounter_claim = nil
      @rf_encounter_events = {}
    end

    def update(data)
      data.each do |key_idx, value|
        key = VMS::REVERSE_KEYS[key_idx]
        next if key.nil?
        next if value.nil? && !@can_be_nil.include?(key)
        if key == :heartbeat
          @heartbeat = value
          next
        end
        # Special handling for party data - deserialize from strings to Pokemon objects
        if key == :party && value.is_a?(Array) && !value.empty?
          deserialized_party = []
          value.each do |pkmn_data|
            next if pkmn_data.nil?
            # Check if it's a serialized string that needs dehashing
            if pkmn_data.is_a?(String)
              deserialized_party.push(VMS.dehash_pokemon(pkmn_data))
            else
              # Already a Pokemon object
              deserialized_party.push(pkmn_data)
            end
          end
          @party = deserialized_party
        else
          instance_variable_set("@#{key}", value)
        end
      end
    end

    def to_hash
      hash = {}
      instance_variables.each do |var|
        sym = var.to_s.delete("@").to_sym
        next unless VMS::PACKET_KEYS.key?(sym)
        next if [:address, :port, :can_be_nil].include?(sym)
        
        value = instance_variable_get(var)
        value = (value * 1000).round / 1000 if value.is_a?(Float)
        hash[VMS::PACKET_KEYS[sym]] = value
      end
      return hash
    end
  end
end