
module VMS

  def self.gts_request(packet, expected_tag)
    begin
      host = $game_temp.vms[:using_external_server] ? VMS::EXTERNALHOST : VMS.target_host
      port = $game_temp.vms[:using_external_server] ? VMS::EXTERNALPORT : VMS::PORT
      if VMS::USE_TCP
        socket = TCPSocket.new(host, port)
      else
        socket = UDPSocket.new
        socket.connect(host, port)
      end

      message = Zlib::Deflate.deflate(Marshal.dump(packet), Zlib::BEST_SPEED)
      socket.send(message, 0)

      timeout = 3.0
      start_time = Time.now
      result = nil

      loop do
        data = socket.read_nonblock(65536, exception: false)

        if data != :wait_readable && data != :wait_writable && !data.nil?
          data = Marshal.load(Zlib::Inflate.inflate(data))
          if data.is_a?(Array) && data[0] == expected_tag
            result = data
            break
          end
        end

        if Time.now - start_time > timeout
          VMS.log("GTS request (#{expected_tag}) timed out", true)
          break
        end

        sleep(0.01)
      end

      socket.close
      result
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      VMS.log("Server is not active", true)
      nil
    rescue => e
      VMS.log("GTS request failed: #{e.message}", true)
      nil
    end
  end

  def self.gts_list
    return [] unless VMS.is_connected?
    result = VMS.gts_request(["gts_list"], :gts_list_result)
    return (result && result[1].is_a?(Array)) ? result[1] : []
  end

  def self.gts_create(kind, summary, payload, price, preview = nil)
    return [false, VMS::GTS_NOT_CONNECTED_MESSAGE] unless VMS.is_connected?
    seller = VMS.get_self
    seller_name = seller ? seller.name : $player.name
    result = VMS.gts_request(["gts_create", [kind, summary, payload, price, $player.id, seller_name, preview]], :gts_create_result)
    return [false, VMS::GTS_UNAVAILABLE_MESSAGE] if result.nil?
    [result[1], result[2]]
  end

  def self.gts_claim(listing_id, price)
    return [false, VMS::GTS_NOT_CONNECTED_MESSAGE] unless VMS.is_connected?
    result = VMS.gts_request(["gts_claim", [listing_id, $player.id]], :gts_claim_result)
    return [false, VMS::GTS_UNAVAILABLE_MESSAGE] if result.nil?
    success, payload_or_reason, kind = result[1], result[2], result[3]
    return [false, payload_or_reason] unless success
    VMS.gts_apply_received(kind, payload_or_reason)
    $player.money -= price
    Game.save
    [true, nil]
  end

  def self.gts_peek(listing_id)
    return [false, VMS::GTS_NOT_CONNECTED_MESSAGE, nil] unless VMS.is_connected?
    result = VMS.gts_request(["gts_peek", [listing_id]], :gts_peek_result)
    return [false, VMS::GTS_UNAVAILABLE_MESSAGE, nil] if result.nil?
    [result[1], result[2], result[3]]
  end

  def self.gts_my_listings
    return [] unless VMS.is_connected?
    result = VMS.gts_request(["gts_my_listings", [$player.id]], :gts_my_listings_result)
    return (result && result[1].is_a?(Array)) ? result[1] : []
  end

  def self.gts_collect(listing_id)
    return [false, VMS::GTS_NOT_CONNECTED_MESSAGE] unless VMS.is_connected?
    result = VMS.gts_request(["gts_collect", [listing_id, $player.id]], :gts_collect_result)
    return [false, VMS::GTS_UNAVAILABLE_MESSAGE] if result.nil?
    success, price_or_reason = result[1], result[2]
    if success
      $player.money += price_or_reason
      Game.save
    end
    [success, price_or_reason]
  end

  def self.gts_cancel(listing_id)
    return [false, VMS::GTS_NOT_CONNECTED_MESSAGE] unless VMS.is_connected?
    result = VMS.gts_request(["gts_cancel", [listing_id, $player.id]], :gts_cancel_result)
    return [false, VMS::GTS_UNAVAILABLE_MESSAGE] if result.nil?
    success, payload_or_reason, kind = result[1], result[2], result[3]
    return [false, payload_or_reason] unless success
    VMS.gts_apply_received(kind, payload_or_reason)
    Game.save
    [true, nil]
  end

  def self.gts_apply_received(kind, payload)
    if kind == :pokemon
      pokemon = VMS.dehash_pokemon(payload)
      pbStorePokemon(pokemon)
    elsif kind == :item
      item, amount = payload
      if $bag.can_add?(item, amount)
        $bag.add_all(item, amount)
      else
        VMS.message(VMS::GTS_BAG_FULL_MESSAGE)
      end
    end
  end

  def self.open_gts_menu
    unless VMS.is_connected?
      VMS.message(VMS::GTS_NOT_CONNECTED_MESSAGE)
      return
    end
    unless VMS::ENABLE_GTS
      VMS.message(VMS::GTS_UNAVAILABLE_MESSAGE)
      return
    end
    loop do
      choices = [VMS::GTS_MENU_BROWSE, VMS::GTS_MENU_LIST_POKEMON, VMS::GTS_MENU_LIST_ITEM, VMS::GTS_MENU_MY_LISTINGS, _INTL("Cancel")]
      choice = VMS.message(VMS::GTS_MENU_TITLE, choices, -1)
      case choice
      when 0 then VMS.gts_browse_menu
      when 1 then VMS.gts_list_pokemon_menu
      when 2 then VMS.gts_list_item_menu
      when 3 then VMS.gts_my_listings_menu
      else return
      end
    end
  end

  def self.gts_browse_menu
    listings = VMS.gts_list
    if listings.empty?
      VMS.message(VMS::GTS_BROWSE_EMPTY_MESSAGE)
      return
    end
    choices = listings.map { |l| _INTL("{1} - ${2} ({3})", l[:summary], l[:price], l[:seller_name]) }
    choices.push(_INTL("Cancel"))
    choice = VMS.message(VMS::GTS_BROWSE_TITLE, choices, -1)
    return if choice.nil? || choice < 0 || choice >= listings.length
    VMS.gts_listing_details_menu(listings[choice])
  end

  def self.gts_listing_details_menu(listing)
    is_own = listing[:seller_id] == $player.id
    loop do
      options = []
      options.push([:summary, VMS::GTS_MENU_VIEW_SUMMARY]) if listing[:kind] == :pokemon
      options.push(is_own ? [:take_back, VMS::GTS_MENU_TAKE_BACK] : [:claim, VMS::GTS_MENU_CLAIM])
      options.push([:back, _INTL("Back")])

      message = _INTL(VMS::GTS_LISTING_DETAILS_MESSAGE, listing[:summary], listing[:seller_name], listing[:price])
      choice = VMS.message(message, options.map { |o| o[1] }, -1)
      return if choice.nil? || choice < 0 || choice >= options.length

      case options[choice][0]
      when :summary
        VMS.gts_view_summary(listing[:id])
      when :take_back
        return unless pbConfirmMessage(_INTL(VMS::GTS_CANCEL_CONFIRM_MESSAGE, listing[:summary]))
        success, reason = VMS.gts_cancel(listing[:id])
        VMS.message(success ? VMS::GTS_CANCEL_SUCCESS_MESSAGE : _INTL(VMS::GTS_CANCEL_FAILURE_MESSAGE, reason.to_s))
        return
      when :claim
        if $player.money < listing[:price]
          VMS.message(VMS::GTS_CANT_AFFORD_MESSAGE)
          next
        end
        return unless pbConfirmMessage(_INTL(VMS::GTS_CLAIM_CONFIRM_MESSAGE, listing[:summary], listing[:price]))
        success, reason = VMS.gts_claim(listing[:id], listing[:price])
        if success
          VMS.message(VMS::GTS_CLAIM_SUCCESS_MESSAGE)
        elsif reason == "That listing is no longer available."
          VMS.message(VMS::GTS_CLAIM_UNAVAILABLE_MESSAGE)
        else
          VMS.message(_INTL(VMS::GTS_CLAIM_FAILURE_MESSAGE, reason.to_s))
        end
        return
      else
        return
      end
    end
  end

  def self.gts_view_summary(listing_id)
    success, payload_or_reason, kind = VMS.gts_peek(listing_id)
    unless success && kind == :pokemon
      VMS.message(success ? VMS::GTS_UNAVAILABLE_MESSAGE : _INTL(VMS::GTS_CLAIM_FAILURE_MESSAGE, payload_or_reason.to_s))
      return
    end
    pokemon = VMS.dehash_pokemon(payload_or_reason)
    pbFadeOutIn do
      scene = PokemonSummary_Scene.new
      screen = PokemonSummaryScreen.new(scene)
      screen.pbStartScreen([pokemon], 0)
    end
  end

  def self.gts_list_pokemon_menu
    VMS.message(VMS::GTS_CHOOSE_POKEMON_MESSAGE)
    pbChoosePokemon(1, 3, proc { |pkmn| !pkmn.egg? && !pkmn.shadowPokemon? })
    pokemon_index = $game_variables[1]
    return if pokemon_index == -1

    pokemon = $player.party[pokemon_index]
    unless $player.remove_pokemon_at_index(pokemon_index)
      VMS.message(VMS::GTS_NO_LISTABLE_POKEMON_MESSAGE)
      return
    end

    price = VMS.gts_prompt_price
    if price <= 0
      $player.party.insert(pokemon_index, pokemon)
      return
    end

    summary = _INTL("{1} Lv.{2}", pokemon.name, pokemon.level)
    unless pbConfirmMessage(_INTL(VMS::GTS_CONFIRM_LISTING_MESSAGE, summary, price))
      $player.party.insert(pokemon_index, pokemon)
      return
    end

    payload = VMS.hash_pokemon(pokemon)
    preview = { species: pokemon.species, form: pokemon.form, gender: pokemon.gender, shiny: pokemon.shiny? }
    VMS.gts_finish_listing(:pokemon, summary, payload, price, preview) do |success|
      $player.party.insert(pokemon_index, pokemon) unless success
    end
  end

  def self.gts_list_item_menu
    item = VMS.choose_giftable_item
    if item.nil? || item == :NONE || $bag.quantity(item) <= 0
      VMS.message(VMS::GTS_NO_LISTABLE_ITEMS_MESSAGE) if item.nil? || item == :NONE
      return
    end

    params = ChooseNumberParams.new
    params.setRange(1, $bag.quantity(item))
    params.setDefaultValue(1)
    params.setCancelValue(0)
    amount = pbMessageChooseNumber(_INTL(VMS::GTS_ITEM_QUANTITY_MESSAGE, GameData::Item.get(item).name), params)
    return if amount <= 0

    price = VMS.gts_prompt_price
    return if price <= 0

    summary = _INTL("{1} x{2}", GameData::Item.get(item).name, amount)
    return unless pbConfirmMessage(_INTL(VMS::GTS_CONFIRM_LISTING_MESSAGE, summary, price))

    return unless $bag.can_remove?(item, amount)
    $bag.remove_all(item, amount)

    payload = [item, amount]
    VMS.gts_finish_listing(:item, summary, payload, price, item) do |success|
      $bag.add_all(item, amount) unless success
    end
  end

  def self.gts_prompt_price
    params = ChooseNumberParams.new
    params.setRange(1, Settings::MAX_MONEY)
    params.setDefaultValue([$player.money, 1].max)
    params.setCancelValue(0)
    pbMessageChooseNumber(VMS::GTS_PRICE_MESSAGE, params)
  end

  def self.gts_finish_listing(kind, summary, payload, price, preview = nil)
    fee = VMS::GTS_LISTING_FEE
    if fee > 0
      if $player.money < fee
        yield false
        VMS.message(_INTL(VMS::GTS_CREATE_FAILURE_MESSAGE, VMS::GTS_CANT_AFFORD_MESSAGE))
        return
      end
      $player.money -= fee
    end

    success, id_or_reason = VMS.gts_create(kind, summary, payload, price, preview)
    yield success

    if success
      Game.save
      VMS.message(VMS::GTS_CREATE_SUCCESS_MESSAGE)
    else
      $player.money += fee if fee > 0
      if id_or_reason.to_s.include?("maximum number")
        VMS.message(VMS::GTS_MAX_LISTINGS_MESSAGE)
      else
        VMS.message(_INTL(VMS::GTS_CREATE_FAILURE_MESSAGE, id_or_reason.to_s))
      end
    end
  end

  def self.gts_my_listings_menu
    listings = VMS.gts_my_listings
    if listings.empty?
      VMS.message(VMS::GTS_MY_LISTINGS_EMPTY_MESSAGE)
      return
    end

    status_label = proc do |status|
      case status
      when :active    then VMS::GTS_STATUS_ACTIVE
      when :sold      then VMS::GTS_STATUS_SOLD
      when :collected then VMS::GTS_STATUS_COLLECTED
      else status.to_s
      end
    end

    choices = listings.map { |l| _INTL("{1} - ${2} [{3}]", l[:summary], l[:price], status_label.call(l[:status])) }
    choices.push(_INTL("Cancel"))
    choice = VMS.message(VMS::GTS_MY_LISTINGS_TITLE, choices, -1)
    return if choice.nil? || choice < 0 || choice >= listings.length
    listing = listings[choice]

    case listing[:status]
    when :active
      return unless pbConfirmMessage(_INTL(VMS::GTS_CANCEL_CONFIRM_MESSAGE, listing[:summary]))
      success, reason = VMS.gts_cancel(listing[:id])
      if success
        VMS.message(VMS::GTS_CANCEL_SUCCESS_MESSAGE)
      else
        VMS.message(_INTL(VMS::GTS_CANCEL_FAILURE_MESSAGE, reason.to_s))
      end
    when :sold
      return unless pbConfirmMessage(_INTL(VMS::GTS_COLLECT_CONFIRM_MESSAGE, listing[:price]))
      success, price_or_reason = VMS.gts_collect(listing[:id])
      if success
        VMS.message(_INTL(VMS::GTS_COLLECT_SUCCESS_MESSAGE, price_or_reason))
      else
        VMS.message(_INTL(VMS::GTS_COLLECT_FAILURE_MESSAGE, price_or_reason.to_s))
      end
    else
      return
    end
  end
end
