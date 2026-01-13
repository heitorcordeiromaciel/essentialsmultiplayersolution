module VMS
  require 'socket'
  require "zlib"

  # Usage: VMS.join(id #<Integer>) (connects to the server with the specified ID)
  def self.join(id=-1)
    if id == -1 # Invalid ID
      VMS.log("No ID specified", true)
      return
    end
    if !$game_temp.vms[:socket].nil? # Already connected
      VMS.log("Already connected to a server")
      return
    end
    # Create socket
    begin
      if VMS::USE_TCP
        socket = TCPSocket.new(VMS::HOST, VMS::PORT)
      else
        socket = UDPSocket.new
        socket.connect(VMS::HOST, VMS::PORT)
      end
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      VMS.log("Server is not active", true)
    rescue => e
      VMS.log("Failed to connect to server: #{e}", true)
    ensure
      return if socket.nil?
    end
    # Initialize variables
    $game_temp.vms[:cluster] = id
    player_data = VMS.generate_player_data
    $game_temp.vms[:socket] = socket
    # Send connect message
    VMS.send_message(["connect", player_data])
    VMS.log("Connected to server")
  end

  # Usage: VMS.leave (disconnects from the server)
  def self.leave(show_message = true)
    if $game_temp.vms[:socket].nil? # Not connected
      VMS.log("Not connected to a server") if show_message
      return
    end
    VMS.clear_events
    # Send disconnect message
    VMS.send_message(["disconnect", VMS.generate_player_data])
    # Close socket
    $game_temp.vms[:socket].close
    # Reset variables
    System.set_window_title(System.game_title) if VMS::SHOW_PING
    $game_temp.vms[:socket] = nil
    $game_temp.vms[:cluster] = -1
    $game_temp.vms[:ping_log] = []
    $game_temp.vms[:time_since_last_message] = 0
    $game_temp.vms[:ping_stamp] = 0
    $game_temp.vms[:players] = {}
    $game_temp.vms[:online_variables] = {}
    VMS.log("Disconnected from server") if show_message
    VMS.message(VMS::DISCONNECTED_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "" || !show_message)
  end

  # Usage: VMS.update (sends and receives data from the server)
  def self.update
    return if $game_temp.vms[:socket].nil? # Not connected
    # Show ping
    if VMS::SHOW_PING
      $game_temp.vms[:ping_log].push((VMS.ping * 500).round)
      $game_temp.vms[:ping_log].shift if $game_temp.vms[:ping_log].size > 50
      ping = [$game_temp.vms[:ping_log].sum / $game_temp.vms[:ping_log].size, 0].max
      System.set_window_title(System.game_title + (ping != -1 ? " (#{ping}ms)" : ""))
    end
    # Actually communicate with the server
    begin
      # Send update message
      if VMS::TICK_RATE == 0 || Graphics.frame_count % (60 / VMS::TICK_RATE) == 0
        send_data = VMS.generate_player_data
        own_player = VMS.get_self
        update_data = own_player.nil? ? send_data : send_data.reject do |key, value|
          key != :state && key != :cluster_id && key != :id && key != :heartbeat &&
          ((!value.is_a?(Array) && own_player.instance_variable_get("@" + key.to_s) == value) ||
          (value.is_a?(Array) && VMS.array_compare(own_player.instance_variable_get("@" + key.to_s), value)))
        end
        VMS.send_message(["update", update_data])
      end
      # Receive data
      data = $game_temp.vms[:socket].read_nonblock(65536, exception: false)
      # No data received
      if data == :wait_readable || data == :wait_writable || data.nil?
        $game_temp.vms[:time_since_last_message] += Graphics.delta
        VMS.leave if $game_temp.vms[:time_since_last_message] > VMS::TIMEOUT_SECONDS
        return
      end
      # Process data
      $game_temp.vms[:time_since_last_message] = 0
      data = Marshal.load(Zlib::Inflate.inflate(data))
      # Disconnect data
      if data.is_a?(Symbol)
        if [:disconnect, :disconnect_full].include?(data)
          suffix = data == :disconnect_full ? " (server full)" : ""
          VMS.log("Disconnected from server#{suffix}")
          VMS.leave(false)
          VMS.message(data == :disconnect_full ? VMS::CLUSTER_FULL_MESSAGE : VMS::SERVER_DISCONNECT_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "")
          return
        elsif data == :disconnect_wrong_game
          VMS.log("Disconnected from server (wrong game)", true)
          VMS.leave(false)
          VMS.message(VMS::DIFFERENT_GAME_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "")
          return
        elsif data == :disconnect_wrong_version
          VMS.log("Disconnected from server (wrong version)", true)
          VMS.leave(false)
          VMS.message(VMS::DIFFERENT_VERSION_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "")
          return
        end
      end
      # Check if a player has disconnected
      if data[0] == :disconnect_player
        id = data[1]
        player = VMS.get_player(id)
        return if player.nil?
        VMS.log("Player #{player.name} (#{id}) has disconnected from the server")
        Rf.delete_event(player.rf_event) if VMS.event_deletion_possible?(player)
        $game_temp.vms[:players].delete(id)
        return
      end
      # Actually use the data
      VMS.process(data)
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      # Server is not active
      VMS.log("Server is not active", true)
      VMS.leave(false)
      VMS.message(VMS::SERVER_INACTIVE_MESSAGE) if !(VMS::DISCONNECTED_MESSAGE.nil? || VMS::DISCONNECTED_MESSAGE == "")
      return
    rescue => e
      # Something went wrong so disconnect
      VMS.log("Failed to communicate with server: #{e}", true)
      VMS.leave
      return
    end
    # Check all players for timeouts (and disconnect them if necessary)
    VMS.get_players.each do |player|
      next if player.id == $player.id
      VMS.check_timeout(player)
      VMS.check_interaction(player) if $game_temp.vms[:state][0] == :idle && VMS.interaction_possible?
    end
  end

  # Usage: VMS.process(data #<Hash>) (processes data received from the server)
  def self.process(data)
    # Sync seed
    VMS.sync_seed if VMS::SEED_SYNC && $game_temp.vms[:battle_player].nil?
    # Iterate through players
    data.each do |pl|
      # Check for online variables
      if pl[0] == :online_variables
        $game_temp.vms[:online_variables] = pl[1]
        next
      end
      # Get player
      id = pl["id"]
      player = $game_temp.vms[:players][id]
      is_self = id == $player.id
      if player.nil? # Player doesn't exist yet
        # Create player
        $game_temp.vms[:players][id] = VMS::Player.new(id, "", 0)
        player = $game_temp.vms[:players][id]
      end
      # Update ping if this is the player
      $game_temp.vms[:ping_stamp] = pl["heartbeat"] if is_self
      # Check if packet is new
      new_packet = pl["heartbeat"] <= player.heartbeat - VMS::ADDED_DELAY
      next if !VMS::HANDLE_MORE_PACKETS && new_packet
      # Update player
      player.update(pl)
      player.is_new = new_packet
      # Don't create event if player is self and SHOW_SELF is false
      next unless VMS::SHOW_SELF if is_self
      # Create event if necessary
      if player.rf_event.nil? || player.rf_event[:event].erased?
        if $map_factory.areConnected?(player.map_id, $game_map.map_id) # Map connection check
          player.rf_event = VMS.create_event(player.map_id, id)
        end
      elsif $map_factory.areConnected?(player.map_id, $game_map.map_id)
        if player.rf_event[:event].map_id != player.map_id # Map change check
          Rf.delete_event(player.rf_event) if VMS.event_deletion_possible?(player)
          player.rf_event = VMS.create_event(player.map_id, id)
        end
      else # Event is on a different map, so delete it
        Rf.delete_event(player.rf_event) if VMS.event_deletion_possible?(player)
        player.rf_event = nil
      end
      # Handle player
      VMS.handle_player(player)
    end
  end

  # Usage: VMS.clear_events (deletes all player events)
  def self.clear_events
    VMS.get_players.each do |player|
      next unless VMS.event_deletion_possible?(player)
      Rf.delete_event(player.rf_event)
      player.rf_event = nil
    end
  end

  # Usage: VMS.clean_up_events (deletes all player events that are no longer necessary)
  def self.clean_up_events
    return unless $game_map
    $game_map.events.each_value do |event|
      next if event.nil?
      next if event.erased?
      next unless event.name && event.name&.include?("vms_player")
      id = (event.name.gsub("vms_player_","")).to_i
      player = VMS.get_player(id)
      if player.nil? || !$map_factory.areConnected?(player.map_id, $game_map.map_id)
        event.character_name = ""
        event.through = true
        event.erase
      end
    end
  end

  # Usage: VMS.send_message(message #<String>) (sends a message to the server)
  def self.send_message(message)
    if $game_temp.vms[:socket].nil? # Not connected
      VMS.log("Not connected to a server")
      return
    end
    # Send message
    message = Zlib::Deflate.deflate(Marshal.dump(message), Zlib::BEST_SPEED)
    $game_temp.vms[:socket].send(message, 0)
  end

  # Usage: VMS.generate_player_data (generates a hash of the player's data)
  def self.generate_player_data
    # Generate party data
    party = []
    $player.party.each do |pkmn|
      party.push(VMS.hash_pokemon(pkmn))
    end
    # Generate player data
    data = {}
    data[:cluster_id]         = $game_temp.vms[:cluster] || -1        # What cluster to connect to
    data[:id]                 = $player.id                            # Player ID
    data[:heartbeat]          = Time.now                              # Used to calculate ping
    data[:game_name]          = System.game_title                     # The name of the game
    data[:game_version]       = Settings::GAME_VERSION                # The version of the game
    data[:online_variables]   = $game_temp.vms[:online_variables]     # Online variables
    data[:party]              = party
    data[:name]               = $player.name
    data[:trainer_type]       = $player.trainer_type
    data[:map_id]             = $game_map.map_id
    data[:x]                  = $game_player.x
    data[:y]                  = $game_player.y
    data[:real_x]             = $game_player.real_x
    data[:real_y]             = $game_player.real_y
    data[:direction]          = $game_player.direction
    data[:pattern]            = $game_player.pattern
    data[:graphic]            = $game_player.character_name
    data[:offset_x]           = $game_player.x_offset
    data[:offset_y]           = $game_player.y_offset
    data[:opacity]            = $game_player.opacity
    data[:stop_animation]     = $game_player.step_anime
    data[:animation]          = $scene.spriteset.getAnimationSprites if $scene.is_a?(Scene_Map) && $scene.spriteset
    data[:jump_offset]        = $game_player.screen_y_ground - $game_player.screen_y - $game_player.y_offset
    data[:jumping_on_spot]    = $game_player.jumping_on_spot
    data[:surfing]            = $PokemonGlobal.surfing
    data[:diving]             = $PokemonGlobal.diving
    data[:surf_base_coords]   = $game_temp.surf_base_coords || [nil, nil]
    data[:state]              = $game_temp.vms[:state]
    data[:busy]               = !VMS.interaction_possible?
    return data
  end
end