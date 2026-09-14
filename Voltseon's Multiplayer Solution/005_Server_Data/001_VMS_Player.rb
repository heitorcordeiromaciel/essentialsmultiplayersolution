
module VMS
  class Player
    attr_reader :id, :address, :port, :heartbeat
    attr_accessor :name, :map_id, :x, :y, :real_x, :real_y, :trainer_type, :direction, :pattern, :graphic
    attr_accessor :party, :animation, :offset_x, :offset_y, :opacity, :stop_animation, :rf_event
    attr_accessor :jump_offset, :jumping_on_spot
    attr_accessor :surfing, :diving, :surf_base_coords
    attr_accessor :state, :busy
    attr_accessor :follower, :rf_follower_event
    attr_accessor :encounters, :encounter_claim, :rf_encounter_events

    def initialize(id, address, port)
      @can_be_nil = [:surf_base_coords, :rf_event, :follower, :encounter_claim]
      @id = id
      @address = address
      @port = port
      @heartbeat = Time.now
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
      @party = []
      @animation = []
      @offset_x = 0
      @offset_y = 0
      @opacity = 255
      @stop_animation = false
      @rf_event = nil
      @jump_offset = 0
      @jumping_on_spot = false
      @surfing = false
      @diving = false
      @surf_base_coords = nil
      @state = [:idle, nil]
      @busy = false
      @follower = nil
      @rf_follower_event = nil
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
        if key == :party && value.is_a?(Array) && !value.empty?
          deserialized_party = []
          value.each do |pkmn_data|
            next if pkmn_data.nil?
            if pkmn_data.is_a?(String)
              deserialized_party.push(VMS.dehash_pokemon(pkmn_data))
            else
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