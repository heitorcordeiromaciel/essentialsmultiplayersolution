module VMS
  class Cluster
    attr_reader   :id
    attr_reader   :players
    attr_accessor :online_variables, :variables_dirty

    def initialize(id=-1, server=nil)
      @id = id
      @players = {}
      @online_variables = {}
      @variables_dirty = true
      @server = server
    end

    def add_player(player)
      @players[player.id] = player
      # Mark all players as dirty so the new player gets a full sync
      @players.each_value { |p| p.dirty = true }
      @variables_dirty = true
    end

    def remove_player(player)
      id = player.is_a?(Player) ? player.id : player
      @players.delete(id)

      # Let all players know that the player has disconnected
      @players.each_value do |p|
        @server.send([:disconnect_player, id], p.address, p.port, p.socket)
      end

      # If the cluster is empty, remove it
      if @players.length == 0
        @server.remove_cluster(@id)
      end
    end

    def player_count
      return @players.length
    end

    def has_player(address, port)
      @players.each_value do |player|
        if player.address == address && player.port == port
          return true
        end
      end
      return false
    end

    def remove_player_by_address(address, port)
      @players.each_value do |player|
        if player.address == address && player.port == port
          remove_player(player.id)
          return true
        end
      end
      return false
    end

    def update_players
      # Remove players that have not sent a heartbeat in a while
      @players.each_value do |player|
        if Time.now - player.heartbeat > Config.heartbeat_timeout
          @server.log("Player #{player.name} (#{player.id}) timed out.")
          remove_player(player)
        end
      end
 
      return if @players.empty?
 
      # Construct data array once
      data = []
      data.push([:online_variables, @online_variables]) if @variables_dirty
      
      @players.each_value do |player|
        data.push(player.to_hash(player.dirty))
      end
 
      # Compress once
      binary = Zlib::Deflate.deflate(Marshal.dump(data), Zlib::BEST_COMPRESSION)
 
      # Broadcast binary to all players
      @players.each_value do |player|
        @server.send_binary(binary, player.address, player.port, player.socket)
      end
 
      # Clear dirty flags
      @players.each_value { |p| p.dirty = false }
      @variables_dirty = false
    end
  end
end
