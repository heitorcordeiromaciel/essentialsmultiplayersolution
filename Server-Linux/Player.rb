##############################################################################
# VMS Player
# ----------------------------------------------------------------------------
# This class is used to store information about a player.
# Make sure to update the same script in the server/plugin when making changes.
# ----------------------------------------------------------------------------
##############################################################################

module VMS
  # Mapping for integer-keyed serialization to reduce bandwidth
  PACKET_KEYS = {
    id: 1, heartbeat: 2, name: 3, map_id: 4, x: 5, y: 6, real_x: 7, real_y: 8,
    trainer_type: 9, direction: 10, pattern: 11, graphic: 12, party: 13,
    animation: 14, offset_x: 15, offset_y: 16, opacity: 17, stop_animation: 18,
    rf_event: 19, jump_offset: 20, jumping_on_spot: 21, surfing: 22, diving: 23,
    surf_base_coords: 24, state: 25, busy: 26, cluster_id: 27,
    online_variables: 28, game_name: 29, game_version: 30
  }
  REVERSE_KEYS = PACKET_KEYS.invert

  class Player
    # Necessary for connections
    attr_reader :id, :address, :port, :heartbeat, :socket
    # Necessary for game
    attr_accessor :name, :map_id, :x, :y, :real_x, :real_y, :trainer_type, :direction, :pattern, :graphic
    # Additional information
    attr_accessor :party, :animation, :offset_x, :offset_y, :opacity, :stop_animation, :rf_event
    # Jumping information
    attr_accessor :jump_offset, :jumping_on_spot
    # Other data
    attr_accessor :surfing, :diving, :surf_base_coords
    # Custom information
    attr_accessor :state, :busy, :dirty, :socket

    def initialize(id, address, port)
      # Used to check what values can be nil
      @can_be_nil = [:surf_base_coords, :rf_event]
      # Required for connections
      @id = id
      @address = address
      @port = port
      @socket = nil
      @heartbeat = Time.now
      @dirty = true
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
    end

    def update(data)
      # Packet sequencing: ignore older packets
      hb_key = PACKET_KEYS[:heartbeat]
      if data.key?(hb_key)
        incoming_hb = data[hb_key]
        return if incoming_hb < @heartbeat
        @heartbeat = incoming_hb
      end

      data.each do |key_idx, value|
        key = REVERSE_KEYS[key_idx]
        next if key == :heartbeat || key.nil?
        next if value.nil? && !@can_be_nil.include?(key)
        
        # Check if value actually changed
        current_val = instance_variable_get("@#{key}")
        if current_val != value
          instance_variable_set("@#{key}", value)
          @dirty = true
        end
      end
    end

    def to_hash(full = true)
      hash = { PACKET_KEYS[:id] => @id, PACKET_KEYS[:heartbeat] => @heartbeat }
      return hash unless full

      instance_variables.each do |var|
        sym = var.to_s.delete("@").to_sym
        next unless PACKET_KEYS.key?(sym)
        next if [:id, :heartbeat].include?(sym)
        
        value = instance_variable_get(var)
        value = (value * 1000).round / 1000 if value.is_a?(Float)
        hash[PACKET_KEYS[sym]] = value
      end
      return hash
    end
  end
end