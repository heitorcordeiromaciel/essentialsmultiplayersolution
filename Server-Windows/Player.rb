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
      if data.key?(:heartbeat)
        incoming_hb = data[:heartbeat]
        return if incoming_hb < @heartbeat
        @heartbeat = incoming_hb
      end

      data.each do |key, value|
        next if key == :heartbeat
        next if value.nil? && !@can_be_nil.include?(key.to_sym)
        
        # Check if value actually changed
        current_val = instance_variable_get("@#{key}")
        if current_val != value
          instance_variable_set("@#{key}", value)
          @dirty = true
        end
      end
    end

    def to_hash(full = true)
      hash = { "id" => @id, "heartbeat" => @heartbeat }
      return hash unless full

      instance_variables.each do |var|
        name = var.to_s.delete("@")
        next if ["address", "port", "can_be_nil", "dirty", "id", "heartbeat", "socket"].include?(name)
        value = instance_variable_get(var)
        value = (value * 1000).round / 1000 if value.is_a?(Float)
        hash[name] = value
      end
      return hash
    end
  end
end