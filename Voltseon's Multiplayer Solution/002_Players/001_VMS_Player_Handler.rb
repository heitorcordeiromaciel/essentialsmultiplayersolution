module VMS
  def self.interact_with_player(id)
    return unless VMS.is_connected?
    player = VMS.get_player(id)
    return if player.nil?
    player_name = player.name
    case player.state[0]
    when :idle
      VMS.send_interaction(player)
    when :interact_receive
      if player.state[1] == $player.id
        VMS.send_interaction(player)
      else
        VMS.message(_INTL(VMS::ALREADY_INTERACTING_MESSAGE, player_name))
      end
    when :interact_send
      if player.state[1] == $player.id
        VMS.check_interaction(player)
      else
        VMS.message(_INTL(VMS::ALREADY_INTERACTING_MESSAGE, player_name))
      end
    when :battle
      VMS.message(_INTL(VMS::IN_A_BATTLE_MESSAGE, player_name))
    when :trade
      VMS.message(_INTL(VMS::IN_A_TRADE_MESSAGE, player_name))
    when :gift
      VMS.message(_INTL(VMS::IN_A_GIFT_MESSAGE, player_name))
    else
      if player.state[0].to_s.start_with?("mm_")
        VMS.message(_INTL(VMS::INTERACTION_BUSY_MESSAGE, player_name))
      end
    end
  end

  def self.check_interaction(player)
    return unless player.state.is_a?(Array)
    return if player.state[1] != $player.id
    return if $game_temp.vms[:state][0] == :interact_receive
    player_name = player.name
    if player.state[0] == :interact_send
      $game_temp.vms[:state] = [:interact_receive, player.id]
      VMS.message(_INTL(VMS::INTERACT_MESSAGE, player_name))
      if !VMS.await_player_state(player, :interact_send, _INTL(VMS::INTERACTION_WAIT_MESSAGE, player_name), true, false, true)
        if player.state[1] != $player.id
          VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
          $game_temp.vms[:state] = [:idle, nil]
          return
        end
      end
      while player.state[0] == :interact_send
        VMS.scene_update
        player = VMS.get_player(player.id)
        if player.nil?
          VMS.message(_INTL(VMS::PLAYER_DISCONNECT_MESSAGE, player_name))
          $game_temp.vms[:state] = [:idle, nil]
          return
        end
        break if VMS::INTERACTION_WAIT <= 0 && Input.trigger?(Input::BACK)
      end
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
        battle_seed = player.state[4]
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
      when :gift
        kind = player.state[2]
        item = player.state[3]
        amount = player.state[4]
        desc = (kind == :item) ? _INTL("{1}x {2}", amount, GameData::Item.get(item).name) : _INTL("${1}", amount)
        if pbConfirmMessage(_INTL(VMS::GIFT_OFFER_MESSAGE, player_name, desc))
          $game_temp.vms[:state] = [:gift, player.id, kind, item, amount]
          if !VMS.await_player_state(player, :gift, _INTL(VMS::INTERACTION_WAIT_RESPONSE_MESSAGE, player_name))
            if player.state[1] != $player.id
              VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
              return
            end
          end
          VMS.start_gift(player, false, kind, item, amount)
        else
          $game_temp.vms[:state] = [:idle, nil]
        end
      end
      $game_temp.vms[:state] = [:idle, nil]
    end
  end

  def self.send_interaction(player, no_busy_check=false)
    player_name = player.name
    id = player.id
    if player.busy && !no_busy_check
      VMS.message(_INTL(VMS::INTERACTION_BUSY_MESSAGE, player_name))
      return
    end
    log("Interacting with player #{player_name} (#{id})")
    $game_temp.vms[:state] = [:interact_send, id]
    msgwindow = pbCreateMessageWindow
    msgwindow.letterbyletter = true
    msgwindow.text = _INTL(VMS::INTERACTION_WAIT_RESPONSE_MESSAGE, player_name)
    VMS.get_interaction_time.times do
      VMS.scene_update
      msgwindow.update
      player = VMS.get_player(id)
      if player.nil?
        pbDisposeMessageWindow(msgwindow)
        VMS.message(_INTL(VMS::PLAYER_DISCONNECT_MESSAGE, player_name))
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      break if VMS::INTERACTION_WAIT <= 0 && Input.trigger?(Input::BACK)
      break if player.state[1] == $player.id
    end
    pbDisposeMessageWindow(msgwindow)
    if player.state[1] != $player.id
      $game_temp.vms[:state] = [:idle, nil]
      VMS.message(_INTL(VMS::PLAYER_NO_RESPONSE_MESSAGE, player_name))
      return
    end
    loop do
      choice = VMS.message(VMS::INTERACTION_CHOICE, ["Swap", "Trade", "Battle", "Gift", "Cancel"])
      case choice
      when 0
        $game_temp.vms[:state] = [:interact_switch, id]
        VMS.message(_INTL(VMS::SWAP_INITIATION_MESSAGE, player_name))
        if !VMS.await_player_state(player, :interact_send, _INTL(VMS::INTERACTION_WAIT_SWITCH_MESSAGE, player_name))
          if player.state[1] != $player.id
            VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
            $game_temp.vms[:state] = [:idle, nil]
            return
          end
        end
        VMS.check_interaction(player)
        break
      when 1
        $game_temp.vms[:state] = [:trade, id]
        if !VMS.await_player_state(player, :trade, _INTL(VMS::INTERACTION_WAIT_RESPONSE_MESSAGE, player_name))
          if player.state[1] != $player.id
            VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
            return
          end
        end
        VMS.start_trade(player)
        break
      when 2
        battle_possible = false
        $player.party.each do |pkmn|
          battle_possible = true if pkmn && pkmn.able?
        end
        if battle_possible
          battle_possible = false
          opponent_party = VMS.update_party(player)
          if opponent_party && opponent_party.is_a?(Array)
            opponent_party.each do |pkmn|
              battle_possible = true if pkmn && pkmn.able?
            end
          end
        end
        if !battle_possible
          VMS.message(_INTL(VMS::INTERACTION_NO_BATTLE_MESSAGE, player_name))
          next
        end
        battle_type_choice = VMS.message(VMS::SELECT_BATTLE_TYPE_MESSAGE, [VMS::BATTLE_TYPE_SINGLE, VMS::BATTLE_TYPE_DOUBLE, _INTL("Cancel")])
        case battle_type_choice
        when 0 then type = :single
        when 1 then type = :double
        else next
        end
        size_choices = (type == :single) ? [VMS::PARTY_SIZE_3, VMS::PARTY_SIZE_6, _INTL("No Limit")] : [VMS::PARTY_SIZE_4, VMS::PARTY_SIZE_6, _INTL("No Limit")]
        size_choice = VMS.message(VMS::SELECT_PARTY_SIZE_MESSAGE, size_choices + [_INTL("Cancel")])
        if size_choice == size_choices.length
          next
        end
        if size_choice == 2
          size = nil
        else
          size = (type == :single) ? (size_choice == 0 ? 3 : 6) : (size_choice == 0 ? 4 : 6)
        end
        if size
          if $player.able_pokemon_count < size || VMS.update_party(player).count { |pkmn| pkmn.able? } < size
            VMS.message(VMS::NOT_ENOUGH_POKEMON_MESSAGE)
            next
          end
        else
          if $player.able_pokemon_count < 1 || VMS.update_party(player).count { |pkmn| pkmn.able? } < 1
            VMS.message(VMS::NOT_ENOUGH_POKEMON_MESSAGE)
            next
          end
        end
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
      when 3
        gift_choice = VMS.message(VMS::GIFT_TYPE_CHOICE, [_INTL("Item"), _INTL("Money"), _INTL("Cancel")])
        case gift_choice
        when 0
          item = VMS.choose_giftable_item
          next if item.nil? || item == :NONE
          next if $bag.quantity(item) <= 0
          params = ChooseNumberParams.new
          params.setRange(1, $bag.quantity(item))
          params.setDefaultValue(1)
          params.setCancelValue(0)
          amount = pbMessageChooseNumber(_INTL(VMS::GIFT_ITEM_QUANTITY_MESSAGE, GameData::Item.get(item).name), params)
          next if amount <= 0
          kind = :item
        when 1
          if $player.money <= 0
            VMS.message(VMS::NO_GIFTABLE_MONEY_MESSAGE)
            next
          end
          params = ChooseNumberParams.new
          params.setRange(1, $player.money)
          params.setDefaultValue(1)
          params.setCancelValue(0)
          amount = pbMessageChooseNumber(VMS::GIFT_MONEY_AMOUNT_MESSAGE, params)
          next if amount <= 0
          kind = :money
          item = nil
        else
          next
        end
        $game_temp.vms[:state] = [:gift, id, kind, item, amount]
        if !VMS.await_player_state(player, :gift, _INTL(VMS::INTERACTION_WAIT_RESPONSE_MESSAGE, player_name))
          if player.state[1] != $player.id
            VMS.message(_INTL(VMS::INTERACTION_CANCEL_MESSAGE, player_name))
            return
          end
        end
        VMS.start_gift(player, true, kind, item, amount)
        break
      when 4
        $game_temp.vms[:state] = [:idle, nil]
        break
      end
    end
    $game_temp.vms[:state] = [:idle, nil]
  end

  def self.create_event(map_id, id)
    rf_event = Rf.create_event(map_id) do |event|
      event.x = 0
      event.y = 0
      event.name = "vms_player_#{id}"
      page = RPG::Event::Page.new
      page.list.clear
      page.trigger = 0
      list = page.list
      Compiler.push_script(list, "VMS::INTERACTION_PROC.call(#{id}, VMS.get_player(#{id}), get_self)")
      Compiler.push_end(list)
      event.pages = [page]
    end
    rf_event[:event].name = "vms_player_#{id}"
    return rf_event
  end

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
        VMS.force_delete_event(player.rf_event)
        VMS.delete_follower_event(player) if VMS::ENABLE_FOLLOWER_SYNC
        VMS.clear_encounter_proxies(player) if VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC
        $game_temp.vms[:players].delete(player.id)
      end
      $game_temp.vms[same_timer] += Graphics.delta
    else
      $game_temp.vms[same_timer] = 0
    end
    $game_temp.vms[stored] = player.heartbeat
  end

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

  def self.await_player_state(player, state=:idle, message="", vms_updates=true, indefinite=false, not_in_state = false)
    if !message.nil? && message != ""
      msgwindow = pbCreateMessageWindow
      msgwindow.letterbyletter = true
      msgwindow.text = message
    end
    VMS.get_interaction_time.times do
      VMS.scene_update(vms_updates)
      msgwindow.update unless msgwindow.nil?
      player = VMS.player_still_connected(player.id, msgwindow, false)
      if player.nil? || player.state[1] != $player.id || ((VMS::INTERACTION_WAIT <= 0 || indefinite) && Input.trigger?(Input::BACK))
        pbDisposeMessageWindow(msgwindow) unless msgwindow.nil?
        $game_temp.vms[:state] = [:idle, nil]
        return false
      end
      if not_in_state
        break if player.state[0] != state
      else
        break if player.state[0] == state
      end
    end
    pbDisposeMessageWindow(msgwindow) unless msgwindow.nil?
    if not_in_state
      return true if player.state[0] != state
    else
      return true if player.state[0] == state
    end
    $game_temp.vms[:state] = [:idle, nil]
    return false
  end

  def self.update_party(player)
    return player.party || []
  end

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
      next if $scene.spriteset.vms_animation_exists?(anim[0], anim[2], anim[3], anim[4], anim[5])
      $scene.spriteset.vms_add_user_animation(anim[0], anim[2], anim[3], anim[4], anim[5], false)
    end
  end

  def self.handle_player(player)
    VMS.update_party(player)
    VMS.sync_animations(player) if player.is_new
    return if player.rf_event.nil?
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
    real_distance = Math.sqrt((player.rf_event[:event].real_x - player.real_x) ** 2 + (player.rf_event[:event].real_y - player.real_y) ** 2)
    if VMS::SMOOTH_MOVEMENT && real_distance < VMS::SNAP_DISTANCE
      player.rf_event[:event].real_x = Math.lerp(player.rf_event[:event].real_x, player.real_x, VMS::SMOOTH_MOVEMENT_ACCURACY)
      player.rf_event[:event].real_y = Math.lerp(player.rf_event[:event].real_y, player.real_y, VMS::SMOOTH_MOVEMENT_ACCURACY)
    else
      player.rf_event[:event].real_x = player.real_x
      player.rf_event[:event].real_y = player.real_y
    end
    distance = $map_factory.getRelativePos($game_map.map_id, $game_player.x, $game_player.y, player.map_id, player.x, player.y)
    distanceNorm = Math.sqrt(distance[0] ** 2 + distance[1] ** 2)
    player.rf_event[:event].opacity = 0 if distance[0].abs > VMS::CULL_DISTANCE || distance[1].abs > VMS::CULL_DISTANCE || distanceNorm > VMS::CULL_DISTANCE
    player.rf_event[:event].calculate_bush_depth
    player.rf_event[:event].refresh
  end
end