module VMS
  # Usage: VMS.interact_with_player(id #<Integer>) (interacts with the specified player)
  def self.interact_with_player(id)
    return unless VMS.is_connected? # Not connected
    # Get player
    player = VMS.get_player(id)
    return if player.nil? # Player doesn't exist
    player_name = player.name
    # Check state
    case player.state[0]
    when :idle
      VMS.send_interaction(player)
    when :interact_receive
      if player.state[1] == $player.id # Other player is interacting with us
        VMS.send_interaction(player)
      else # The other player is interacting with someone else
        VMS.message(_INTL(VMS::ALREADY_INTERACTING_MESSAGE, player_name))
      end
    when :interact_send
      if player.state[1] == $player.id # Other player is interacting with us
        VMS.check_interaction(player)
      else # The other player is interacting with someone else
        VMS.message(_INTL(VMS::ALREADY_INTERACTING_MESSAGE, player_name))
      end
    when :battle
      VMS.message(_INTL(VMS::IN_A_BATTLE_MESSAGE, player_name))
    when :trade
      VMS.message(_INTL(VMS::IN_A_TRADE_MESSAGE, player_name))
    end
  end

  # Usage: VMS.check_interaction(player #<VMS::Player>) (checks if the specified player is interacting with the player)
  def self.check_interaction(player)
    return unless player.state.is_a?(Array)
    return if player.state[1] != $player.id
    return if $game_temp.vms[:state][0] == :interact_receive
    player_name = player.name
    # Check state
    if player.state[0] == :interact_send
      # Set state to interact with player
      $game_temp.vms[:state] = [:interact_receive, player.id]
      # Tell player to interact with us
      VMS.message(_INTL(VMS::INTERACT_MESSAGE, player_name))
      # Wait for other player to say something
      if !VMS.await_player_state(player, :interact_send, _INTL(VMS::INTERACTION_WAIT_MESSAGE, player_name), true, false, true)
        if player.state[1] != $player.id
          VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
          $game_temp.vms[:state] = [:idle, nil]
          return
        end
      end
      # Wait until the other player is done interacting with us
      while player.state[0] == :interact_send
        # Update the scene
        VMS.scene_update
        # Check if player still exists
        player = VMS.get_player(player.id)
        if player.nil?
          VMS.message(_INTL(VMS::PLAYER_DISCONNECT_MESSAGE, player_name))
          $game_temp.vms[:state] = [:idle, nil]
          return
        end
        # Check for cancellation
        break if VMS::INTERACTION_WAIT <= 0 && Input.trigger?(Input::BACK)
      end
      # Check what the player said
      case player.state[0]
      when :idle
        $game_temp.vms[:state] = [:idle, nil]
        VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
      when :interact_send
        VMS.message(_INTL(VMS::INTERACTION_WAITING_FOR_YOU_MESSAGE, player_name))
        VMS.check_interaction(player)
      when :interact_receive

      when :interact_switch
        VMS.message(_INTL(VMS::INTERACTION_SWAP_MESSAGE, player_name))
        VMS.send_interaction(player, true)
      when :trade
        if pbConfirmMessage(_INTL(VMS::INTERACTION_TRADE_MESSAGE, player_name))
          $game_temp.vms[:state] = [:trade, player.id]
          if !VMS.await_player_state(player, :trade, _INTL(VMS::INTERACTION_WAIT_RESPONSE_MESSAGE, player_name))
            if player.state[1] != $player.id
              VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
              return
            end
          end
          VMS.start_trade(player)
        else
          $game_temp.vms[:state] = [:idle, nil]
        end
      when :battle
        battle_type = player.state[2] == :double ? VMS::BATTLE_TYPE_DOUBLE : VMS::BATTLE_TYPE_SINGLE
        battle_size = player.state[3]
        battle_seed = player.state[4] # Get seed from initiator
        if pbConfirmMessage(_INTL(VMS::INTERACTION_BATTLE_MESSAGE, player_name, "#{battle_type} (#{battle_size}v#{battle_size})"))
          $game_temp.vms[:state] = [:battle, player.id, player.state[2], player.state[3], battle_seed]
          if !VMS.await_player_state(player, :battle, _INTL(VMS::INTERACTION_WAIT_RESPONSE_MESSAGE, player_name))
            if player.state[1] != $player.id
              VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
              return
            end
          end
          VMS.start_battle(player, player.state[2], player.state[3], battle_seed)
        else
          $game_temp.vms[:state] = [:idle, nil]
        end
      end
      $game_temp.vms[:state] = [:idle, nil]
    end
  end

  # Usage: VMS.send_interaction(player #<VMS::Player>) (sends an interaction request to the specified player)
  def self.send_interaction(player, no_busy_check=false)
    # Get player name
    player_name = player.name
    # Get player ID
    id = player.id
    # Check if player is busy
    if player.busy && !no_busy_check
      VMS.message(_INTL(VMS::INTERACTION_BUSY_MESSAGE, player_name))
      return
    end
    # Log it
    log("Interacting with player #{player_name} (#{id})")
    # Set state to interact with player
    $game_temp.vms[:state] = [:interact_send, id]
    # Create wait message
    msgwindow = pbCreateMessageWindow
    msgwindow.letterbyletter = true
    msgwindow.text = _INTL(VMS::INTERACTION_WAIT_RESPONSE_MESSAGE, player_name)
    # Wait for other player to respond
    VMS.get_interaction_time.times do
      # Update the scene (so the message window doesn't freeze)
      VMS.scene_update
      msgwindow.update
      # Check if player still exists
      player = VMS.get_player(id)
      if player.nil?
        # Stop waiting
        pbDisposeMessageWindow(msgwindow)
        VMS.message(_INTL(VMS::PLAYER_DISCONNECT_MESSAGE, player_name))
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      # Check for cancellation
      break if VMS::INTERACTION_WAIT <= 0 && Input.trigger?(Input::BACK)
      # Check if player has responded
      break if player.state[1] == $player.id
    end
    pbDisposeMessageWindow(msgwindow) # Dispose message window
    # Check if player has responded
    if player.state[1] != $player.id
      # Set state to idle
      $game_temp.vms[:state] = [:idle, nil]
      VMS.message(_INTL(VMS::PLAYER_NO_RESPONSE_MESSAGE, player_name))
      return
    end
    # What do we do now?
    loop do
      choice = VMS.message(VMS::INTERACTION_CHOICE, ["Swap", "Trade", "Battle", "Cancel"])
      case choice
      when 0 # Swap
        # Set state to interact with player
        $game_temp.vms[:state] = [:interact_switch, id]
        # Tell player to interact with us
        VMS.message(_INTL(VMS::SWAP_INITIATION_MESSAGE, player_name))
        # Wait for other player to say something
        if !VMS.await_player_state(player, :interact_send, _INTL(VMS::INTERACTION_WAIT_SWITCH_MESSAGE, player_name))
          if player.state[1] != $player.id
            VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
            $game_temp.vms[:state] = [:idle, nil]
            return
          end
        end
        # Start interacting with the player
        VMS.check_interaction(player)
        break
      when 1 # Trade
        # Set state to trade with player
        $game_temp.vms[:state] = [:trade, id]
        if !VMS.await_player_state(player, :trade, _INTL(VMS::INTERACTION_WAIT_RESPONSE_MESSAGE, player_name))
          if player.state[1] != $player.id
            VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
            return
          end
        end
        VMS.start_trade(player)
        break
      when 2 # Battle
        # Check if a battle would be possible
        battle_possible = false
        $player.party.each do |pkmn|
          battle_possible = true if pkmn.able?
        end
        if battle_possible
          battle_possible = false
          VMS.update_party(player).each do |pkmn|
            battle_possible = true if pkmn.able?
          end
        end
        if !battle_possible
          VMS.message(_INTL(VMS::INTERACTION_NO_BATTLE_MESSAGE, player_name))
          next
        end
        # Select battle type
        battle_type_choice = VMS.message(VMS::SELECT_BATTLE_TYPE_MESSAGE, [VMS::BATTLE_TYPE_SINGLE, VMS::BATTLE_TYPE_DOUBLE, _INTL("Cancel")])
        case battle_type_choice
        when 0 then type = :single
        when 1 then type = :double
        else next
        end
        # Select party size
        size_choices = (type == :single) ? [VMS::PARTY_SIZE_3, VMS::PARTY_SIZE_6] : [VMS::PARTY_SIZE_4, VMS::PARTY_SIZE_6]
        size_choice = VMS.message(VMS::SELECT_PARTY_SIZE_MESSAGE, size_choices + [_INTL("Cancel")])
        if size_choice == size_choices.length
          next
        end
        size = (type == :single) ? (size_choice == 0 ? 3 : 6) : (size_choice == 0 ? 4 : 6)
        # Validate party size
        if $player.able_pokemon_count < size || VMS.update_party(player).count { |pkmn| pkmn.able? } < size
          VMS.message(VMS::NOT_ENOUGH_POKEMON_MESSAGE)
          next
        end
        # Set state to battle with player
        battle_seed = rand(1000000...9999999)
        $game_temp.vms[:state] = [:battle, id, type, size, battle_seed]
        if !VMS.await_player_state(player, :battle, _INTL(VMS::INTERACTION_WAIT_RESPONSE_MESSAGE, player_name))
          if player.state[1] != $player.id
            VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
            return
          end
        end
        VMS.start_battle(player, type, size, battle_seed)
        break
      when 3 # Cancel
        # Set state to idle
        $game_temp.vms[:state] = [:idle, nil]
        break
      end
    end
    $game_temp.vms[:state] = [:idle, nil]
  end

  # Usage: VMS.create_event(map_id #<Integer>, id #<Integer>) (creates an event for the specified player)
  def self.create_event(map_id, id)
    rf_event = Rf.create_event(map_id) do |event|
      # Default
      event.x = 0
      event.y = 0
      event.name = "vms_player_#{id}"
      # Create page
      page = RPG::Event::Page.new
      page.list.clear
      page.trigger = 0
      list = page.list
      # Add behavior
      Compiler.push_script(list, "VMS::INTERACTION_PROC.call(#{id}, VMS.get_player(#{id}), get_self)")
      Compiler.push_end(list)
      # Save
      event.pages = [page]
    end
    rf_event[:event].name = "vms_player_#{id}"
    return rf_event
  end

  # Usage: VMS.check_timeout(player #<VMS::Player>) (checks if the specified player has timed out)
  def self.check_timeout(player)
    stored = ("stored_heartbeat_" + player.id.to_s).to_sym
    same_timer = ("same_timer_" + player.id.to_s).to_sym
    if $game_temp.vms[stored].nil?
      $game_temp.vms[stored] = player.heartbeat
      $game_temp.vms[same_timer] = 0
      return
    end
    if $game_temp.vms[stored] == player.heartbeat
      if $game_temp.vms[same_timer] > (VMS::TIMEOUT_SECONDS / 5)
        VMS.log("Player #{player.name} (#{player.id}) timed out.")
        Rf.delete_event(player.rf_event) if VMS.event_deletion_possible?(player)
        $game_temp.vms[:players].delete(player.id)
      end
      $game_temp.vms[same_timer] += Graphics.delta
    else
      $game_temp.vms[same_timer] = 0
    end
    $game_temp.vms[stored] = player.heartbeat
  end

  # Usage: VMS.player_still_connected(id #<Integer>, msgwindow #<MessageWindow>, show_message #<Boolean>) (checks if the specified player is still connected)
  def self.player_still_connected(id, msgwindow=nil, show_message=true)
    player = VMS.get_player(id)
    if player.nil?
      pbDisposeMessageWindow(msgwindow) unless msgwindow.nil?
      $game_temp.vms[:state] = [:idle, nil]
      VMS.message(VMS::CONNECTION_ISSUE_MESSAGE) if show_message
      return nil
    end
    return player
  end

  # Usage: VMS.await_player_state(player #<VMS::Player>, state #<Symbol>, message #<String>, vms_updates #<Boolean>, indefinite #<Boolean>) (waits for the specified player to be in the specified state)
  def self.await_player_state(player, state=:idle, message="", vms_updates=true, indefinite=false, not_in_state = false)
    # Create wait message
    if !message.nil? && message != ""
      msgwindow = pbCreateMessageWindow
      msgwindow.letterbyletter = true
      msgwindow.text = message
    end
    # Wait for other player to respond
    VMS.get_interaction_time.times do
      # Update the scene (so the message window doesn't freeze)
      VMS.scene_update(vms_updates)
      msgwindow.update unless msgwindow.nil?
      # Check if player still exists
      player = VMS.player_still_connected(player.id, msgwindow, false)
      # Compare states
      if player.nil? || player.state[1] != $player.id || ((VMS::INTERACTION_WAIT <= 0 || indefinite) && Input.trigger?(Input::BACK))
        # Dispose message window
        pbDisposeMessageWindow(msgwindow) unless msgwindow.nil?
        # Set state to idle
        $game_temp.vms[:state] = [:idle, nil]
        return false
      end
      # Check if player is still in the specified state
      if not_in_state
        break if player.state[0] != state
      else
        break if player.state[0] == state
      end
    end
    # Dispose message window
    pbDisposeMessageWindow(msgwindow) unless msgwindow.nil?
    if not_in_state
      return true if player.state[0] != state
    else
      return true if player.state[0] == state # Return true if player is in the specified state
    end
    # Player is not in the specified state
    $game_temp.vms[:state] = [:idle, nil]
    return false
  end

  # Usage: VMS.update_party(player #<VMS::Player>) (updates the player's party)
  def self.update_party(player)
    new_party = []
    player.party.each do |pkmn|
      new_party.push(pkmn.is_a?(::Pokemon) ? pkmn : VMS.dehash_pokemon(pkmn))
    end
    player.party = new_party
    return player.party
  end

  # Usage: VMS.sync_animations(player #<VMS::Player>) (syncs the player's animations)
  def self.sync_animations(player)
    return unless VMS.is_connected?
    return if VMS::SYNC_ANIMATIONS == [0]
    return if player.nil?
    return if player.id == $player.id && !VMS::SHOW_SELF
    return unless $scene.is_a?(Scene_Map)
    return unless $scene.spriteset
    return if player.animation.nil? || player.animation.empty?
    player.animation.each do |anim|
      next if anim.nil?
      next if anim == 0
      next unless anim[1] == $game_map.map_id
      next unless VMS::SYNC_ANIMATIONS.include?(anim[0])
      next if $scene.spriteset.animationExists?(anim[0], anim[2], anim[3], anim[4], anim[5])
      $scene.spriteset.addUserAnimation(anim[0], anim[2], anim[3], anim[4], anim[5], false)
    end
  end

  # Usage: VMS.handle_player(player #<VMS::Player>) (handles the specified player)
  def self.handle_player(player)
    # Update party
    VMS.update_party(player)
    # Sync animations
    VMS.sync_animations(player) if player.is_new
    # No event
    return if player.rf_event.nil?
    # Update event
    player.rf_event[:event].x = player.x
    player.rf_event[:event].y = player.y
    player.rf_event[:event].direction = player.direction
    player.rf_event[:event].pattern = player.pattern
    player.rf_event[:event].character_name = player.graphic
    player.rf_event[:event].opacity = player.opacity
    player.rf_event[:event].step_anime = player.stop_animation
    player.rf_event[:event].through = VMS::THROUGH
    player.rf_event[:event].jumping_on_spot = player.jumping_on_spot
    player.rf_event[:event].x_offset = player.offset_x
    player.rf_event[:event].y_offset = player.offset_y - player.jump_offset
    # Smooth the event's movement
    real_distance = Math.sqrt((player.rf_event[:event].real_x - player.real_x) ** 2 + (player.rf_event[:event].real_y - player.real_y) ** 2)
    if VMS::SMOOTH_MOVEMENT && real_distance < VMS::SNAP_DISTANCE
      player.rf_event[:event].real_x = Math.lerp(player.rf_event[:event].real_x, player.real_x, VMS::SMOOTH_MOVEMENT_ACCURACY)
      player.rf_event[:event].real_y = Math.lerp(player.rf_event[:event].real_y, player.real_y, VMS::SMOOTH_MOVEMENT_ACCURACY)
    else
      player.rf_event[:event].real_x = player.real_x
      player.rf_event[:event].real_y = player.real_y
    end
    # Make event invisible if it is too far away
    distance = $map_factory.getRelativePos($game_map.map_id, $game_player.x, $game_player.y, player.map_id, player.x, player.y)
    distanceNorm = Math.sqrt(distance[0] ** 2 + distance[1] ** 2)
    player.rf_event[:event].opacity = 0 if distance[0].abs > VMS::CULL_DISTANCE || distance[1].abs > VMS::CULL_DISTANCE || distanceNorm > VMS::CULL_DISTANCE
    # Refresh event
    player.rf_event[:event].calculate_bush_depth
    player.rf_event[:event].refresh
  end
end