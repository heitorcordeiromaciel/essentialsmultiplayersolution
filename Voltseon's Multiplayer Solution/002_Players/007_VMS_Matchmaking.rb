
module VMS

  def self.open_matchmaking_menu
    unless VMS.is_connected?
      VMS.message(VMS::MM_NOT_CONNECTED_MESSAGE)
      return
    end
    choices = [VMS::MM_BATTLE_MENU_NAME, VMS::MB_MENU_NAME, VMS::MM_TRADE_MENU_NAME, _INTL("Cancel")]
    choice = VMS.message(VMS::MENU_CHOICES_MESSAGE, choices, -1)
    case choice
    when 0 then VMS.open_battle_matchmaking_menu
    when 1 then VMS.open_multibattle_menu
    when 2 then VMS.open_trade_matchmaking_menu
    end
  end

  def self.mm_compute_pairing(queue_tag, filter_key)
    queued = VMS.get_players.select do |p|
      p.state.is_a?(Array) && p.state[0] == queue_tag && p.state[2] == filter_key
    end.sort_by(&:id)
    idx = queued.index { |p| p.id == $player.id }
    return nil if idx.nil?
    partner_idx = idx.even? ? idx + 1 : idx - 1
    return queued[partner_idx]
  end

  def self.mm_queue_loop(queue_tag, found_tag, filter_key, wait_message)
    $game_temp.vms[:state] = [queue_tag, nil, filter_key]
    start_time = Time.now
    msgwindow  = pbCreateMessageWindow
    msgwindow.letterbyletter = false
    msgwindow.setText(wait_message)
    partner     = nil
    match_start = nil
    loop do
      VMS.scene_update
      msgwindow.update

      if Input.trigger?(Input::BACK)
        pbDisposeMessageWindow(msgwindow)
        $game_temp.vms[:state] = [:idle, nil]
        VMS.message(VMS::MM_QUEUE_CANCELLED_MESSAGE)
        return nil
      end
      if Time.now - start_time > VMS::MM_QUEUE_TIMEOUT
        pbDisposeMessageWindow(msgwindow)
        $game_temp.vms[:state] = [:idle, nil]
        VMS.message(VMS::MM_QUEUE_TIMEOUT_MESSAGE)
        return nil
      end

      if partner.nil?
        candidate = VMS.mm_compute_pairing(queue_tag, filter_key)
        if candidate
          partner     = candidate
          match_start = Time.now
          $game_temp.vms[:state] = [found_tag, partner.id, filter_key]
        end
        next
      end

      live_partner = VMS.get_player(partner.id)
      pst = live_partner&.state
      if pst.is_a?(Array) && pst[0] == found_tag && pst[1] == $player.id
        pbDisposeMessageWindow(msgwindow)
        VMS.message(_INTL(VMS::MM_MATCH_FOUND_MESSAGE, partner.name))
        return live_partner
      end

      if live_partner.nil? || (Time.now - match_start) > VMS::MM_MATCH_CONFIRM_TIMEOUT
        partner     = nil
        match_start = nil
        $game_temp.vms[:state] = [queue_tag, nil, filter_key]
      end
    end
  end

  def self.open_battle_matchmaking_menu
    unless VMS.is_connected?
      VMS.message(VMS::MM_NOT_CONNECTED_MESSAGE)
      return
    end
    if $player.able_pokemon_count < 1
      VMS.message(VMS::MB_NO_ELIGIBLE_POKEMON)
      return
    end

    battle_type_choice = VMS.message(VMS::SELECT_BATTLE_TYPE_MESSAGE, [VMS::BATTLE_TYPE_SINGLE, VMS::BATTLE_TYPE_DOUBLE, _INTL("Cancel")])
    case battle_type_choice
    when 0 then type = :single
    when 1 then type = :double
    else return
    end

    size_choices = (type == :single) ? [VMS::PARTY_SIZE_3, VMS::PARTY_SIZE_6, _INTL("No Limit")] : [VMS::PARTY_SIZE_4, VMS::PARTY_SIZE_6, _INTL("No Limit")]
    size_choice = VMS.message(VMS::SELECT_PARTY_SIZE_MESSAGE, size_choices + [_INTL("Cancel")])
    return if size_choice == size_choices.length
    if size_choice == 2
      size = nil
    else
      size = (type == :single) ? (size_choice == 0 ? 3 : 6) : (size_choice == 0 ? 4 : 6)
    end
    if size && $player.able_pokemon_count < size
      VMS.message(VMS::NOT_ENOUGH_POKEMON_MESSAGE)
      return
    end

    partner = VMS.mm_queue_loop(:mm_battle_queue, :mm_battle_found, [type, size], VMS::MM_QUEUE_WAIT_MESSAGE)
    return if partner.nil?

    $game_temp.vms[:state] = [:battle, partner.id, type, size, nil]
    VMS.start_battle(partner, type, size, nil)
  end

  def self.open_trade_matchmaking_menu
    unless VMS.is_connected?
      VMS.message(VMS::MM_NOT_CONNECTED_MESSAGE)
      return
    end
    if $player.able_pokemon_trade_count == 0
      VMS.message(VMS::NO_TRADABLE_MESSAGE)
      return
    end

    partner = VMS.mm_queue_loop(:mm_trade_queue, :mm_trade_found, :any, VMS::MM_TRADE_QUEUE_WAIT_MESSAGE)
    return if partner.nil?

    $game_temp.vms[:state] = [:trade, partner.id]
    VMS.start_trade(partner)
  end
end
