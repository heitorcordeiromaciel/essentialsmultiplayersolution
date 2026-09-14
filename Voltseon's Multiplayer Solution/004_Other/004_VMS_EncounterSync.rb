module VMS
  class << self
    alias vms_encounter_generate_player_data generate_player_data unless method_defined?(:vms_encounter_generate_player_data)
    def generate_player_data
      data = vms_encounter_generate_player_data
      if VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC
        begin
          VMS.ensure_voe_override_installed
          data[VMS::PACKET_KEYS[:encounters]] = VMS.build_encounter_broadcast
          data[VMS::PACKET_KEYS[:encounter_claim]] = $game_temp.vms[:voe_pending_claim]
        rescue StandardError => e
          VMS.log("EncounterSync: Error building broadcast: #{e.message}", true) rescue nil
        end
      end
      data
    end

    alias vms_encounter_handle_player handle_player unless method_defined?(:vms_encounter_handle_player)
    def handle_player(player)
      vms_encounter_handle_player(player)
      if VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC
        VMS.handle_encounters(player)
        VMS.check_encounter_claim(player)
      end
    end

    alias vms_encounter_update update unless method_defined?(:vms_encounter_update)
    def update
      vms_encounter_update
      return unless VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC
      begin
        VMS.drive_encounters_while_busy
        VMS.step_encounter_proxy_movement
      rescue StandardError => e
        VMS.log("EncounterSync: update error: #{e.message}", true) rescue nil
      end
    end
  end

  def self.currently_has_real_encounters?(map_id)
    return false unless $game_map && $game_map.map_id == map_id
    $game_map.events.each_value do |event|
      return true if event.name[/OverworldPkmn/i] && event.variable
    end
    false
  end

  def self.encounter_authority_for_map(map_id)
    candidates = VMS.get_players.reject { |p| p.id == $player.id }.select { |p| p.map_id == map_id }
    candidates << VMS.get_self if $game_map && $game_map.map_id == map_id && VMS.get_self
    return nil if candidates.empty?
    broadcasting = candidates.select do |p|
      if p.id == $player.id
        VMS.currently_has_real_encounters?(map_id)
      else
        p.encounters.is_a?(Array) && !p.encounters.empty?
      end
    end
    return broadcasting.min_by(&:id) unless broadcasting.empty?
    candidates.min_by(&:id)
  end

  def self.is_encounter_authority?
    return true unless VMS.is_connected?
    return true if $game_map.nil?
    authority = VMS.encounter_authority_for_map($game_map.map_id)
    authority.nil? || authority.id == $player.id
  end

  def self.encounter_uid_for(map_id, event_id, pkmn)
    table = ($game_temp.vms[:voe_uids] ||= {})
    key = [map_id, event_id]
    entry = table[key]
    if entry.nil? || !entry[0].equal?(pkmn)
      seq = ($game_temp.vms[:voe_uid_seq] || 0) + 1
      $game_temp.vms[:voe_uid_seq] = seq
      entry = [pkmn, "#{$player.id}_#{map_id}_#{event_id}_#{seq}"]
      table[key] = entry
    end
    entry[1]
  end

  def self.build_encounter_broadcast
    return [] unless VMS.is_connected? && VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC
    return [] if $game_map.nil?
    VMS.update_encounter_authority_transition
    in_grace = $game_temp.vms[:voe_relinquish_deadline] && $game_temp.vms[:voe_authority_map] == $game_map.map_id
    return [] unless VMS.is_encounter_authority? || in_grace
    list = []
    $game_map.events.each_value do |event|
      next unless event.name[/OverworldPkmn/i]
      data = event.variable
      next unless data.is_a?(Array) && data[0]
      pkmn = data[0]
      uid = VMS.encounter_uid_for(event.map_id, event.id, pkmn)
      list << [uid, event.x, event.y, event.real_x, event.real_y, event.direction, event.pattern, event.character_name, event.opacity, VMS.hash_pokemon(pkmn), event.move_speed]
    end
    list
  end

  GRACE_PERIOD_SECONDS = 1.0

  def self.update_encounter_authority_transition
    map_id = $game_map.map_id
    was_map = $game_temp.vms[:voe_authority_map]

    if was_map && was_map != map_id
      VMS.relinquish_authority(was_map)
      $game_temp.vms[:voe_authority_map] = nil
      $game_temp.vms[:voe_relinquish_deadline] = nil
      was_map = nil
    end

    now_authority = VMS.is_encounter_authority?
    if now_authority
      if was_map != map_id
        VMS.adopt_proxies_as_authority(map_id)
      end
      $game_temp.vms[:voe_authority_map] = map_id
      $game_temp.vms[:voe_relinquish_deadline] = nil
    elsif was_map == map_id
      deadline = ($game_temp.vms[:voe_relinquish_deadline] ||= Time.now + GRACE_PERIOD_SECONDS)
      if Time.now >= deadline
        VMS.relinquish_authority(map_id)
        $game_temp.vms[:voe_authority_map] = nil
        $game_temp.vms[:voe_relinquish_deadline] = nil
      end
    end
  end

  def self.adopt_proxies_as_authority(map_id)
    adopted = 0
    adopted_uids = {}
    VMS.get_players.each do |remote|
      next if remote.id == $player.id
      next unless remote.rf_encounter_events.is_a?(Hash) && !remote.rf_encounter_events.empty?
      remote.rf_encounter_events.each do |uid, rf|
        begin
          ev = rf.is_a?(Hash) ? rf[:event] : nil
          next unless ev && !ev.erased? && ev.map_id == map_id
          data = $game_temp.vms[:voe_proxy_data] && $game_temp.vms[:voe_proxy_data][uid]
          next unless data
          pkmn = VMS.dehash_pokemon(data[1])
          next unless pkmn
          VMS.promote_proxy_to_real_encounter(ev, rf, pkmn, uid)
          $game_temp.vms[:voe_proxy_data]&.delete(uid)
          adopted_uids[uid] = true
          adopted += 1
        rescue StandardError => e
          VMS.log("EncounterSync: Failed to adopt #{uid}: #{e.message}", true) rescue nil
        end
      end
      remote.rf_encounter_events.clear
    end
    VMS.get_players.each do |remote|
      next if remote.id == $player.id || remote.map_id != map_id
      next unless remote.encounters.is_a?(Array)
      remote.encounters.each do |tuple|
        next unless tuple.is_a?(Array) && tuple.length >= 10
        uid = tuple[0]
        next if adopted_uids[uid]
        begin
          _, x, y, real_x, real_y, direction, pattern, graphic, opacity, pkmn_hash = tuple
          pkmn = VMS.dehash_pokemon(pkmn_hash)
          next unless pkmn
          rf = VMS.create_encounter_event(map_id, "adopted_#{uid}", pkmn_hash)
          ev = rf[:event]
          ev.x = x
          ev.y = y
          ev.real_x = real_x
          ev.real_y = real_y
          ev.direction = direction
          ev.pattern = pattern
          VMS.promote_proxy_to_real_encounter(ev, rf, pkmn, uid)
          adopted_uids[uid] = true
          adopted += 1
        rescue StandardError => e
          VMS.log("EncounterSync: Failed to adopt (fallback) #{uid}: #{e.message}", true) rescue nil
        end
      end
    end
    begin
      VOESettings.current_encounters = adopted
    rescue StandardError
    end
  end

  def self.promote_proxy_to_real_encounter(ev, rf, pkmn, uid)
    raw = ev.instance_variable_get(:@event)
    page = RPG::Event::Page.new
    page.list.clear
    page.trigger = 0
    Compiler.push_script(page.list, "pbInteractOverworldEncounter")
    Compiler.push_end(page.list)
    raw.name = "OverworldPkmn"
    raw.pages = [page]
    ev.refresh
    ev.setVariable([pkmn, rf])
    ($game_temp.vms[:voe_uids] ||= {})[[ev.map_id, ev.id]] = [pkmn, uid]
  end

  def self.relinquish_authority(map_id)
    map = $map_factory && $map_factory.getMapNoAdd(map_id)
    return unless map
    removed = 0
    map.events.values.each do |event|
      next unless event.name[/OverworldPkmn/i]
      data = event.variable
      next unless data
      $PokemonGlobal.eventvars.delete([map_id, event.id])
      begin
        Rf.delete_event(data[1])
      rescue StandardError
        event.erase
      end
      removed += 1
    end
    begin
      VOESettings.current_encounters = 0 if $game_map && $game_map.map_id == map_id
    rescue StandardError
    end
    $game_temp.vms[:voe_uids]&.delete_if { |key, _| key.is_a?(Array) && key[0] == map_id }
  end

  def self.check_encounter_claim(player)
    claim = player.encounter_claim
    return unless claim.is_a?(Array) && claim.length >= 2
    uid, seq = claim
    seen = ($game_temp.vms[:voe_seen_claims] ||= {})
    return if seen[player.id] == seq
    seen[player.id] = seq
    return if VMS.get_variable("voe_claimed_#{uid}")
    table = $game_temp.vms[:voe_uids]
    return unless table
    table.each do |key, entry|
      next unless entry[1] == uid
      map_id, event_id = key
      next unless $game_map && map_id == $game_map.map_id
      ev = $game_map.events[event_id]
      if ev && ev.variable
        pbDestroyOverworldEncounter(ev, false, false)
        VMS.set_variable("voe_claimed_#{uid}", true)
      end
      table.delete(key)
      break
    end
  end

  def self.create_encounter_event(map_id, uid, pkmn_hash)
    rf_event = Rf.create_event(map_id) do |event|
      event.x = 0
      event.y = 0
      event.name = "vms_encounter_#{uid}"
      page = RPG::Event::Page.new
      page.list.clear
      page.trigger = 0
      Compiler.push_script(page.list, "VMS.pbInteractSyncedEncounter(#{uid.inspect})")
      Compiler.push_end(page.list)
      event.pages = [page]
    end
    rf_event[:event].name = "vms_encounter_#{uid}"
    return rf_event
  end

  def self.delete_encounter_proxy(player, uid)
    rf = player.rf_encounter_events[uid]
    return unless rf
    VMS.force_delete_event(rf)
    player.rf_encounter_events.delete(uid)
    $game_temp.vms[:voe_proxy_data]&.delete(uid)
    $game_temp.vms[:voe_proxy_motion]&.delete(uid)
  end

  def self.clear_encounter_proxies(player)
    return if player.rf_encounter_events.nil? || player.rf_encounter_events.empty?
    player.rf_encounter_events.keys.each { |uid| VMS.delete_encounter_proxy(player, uid) }
  end

  def self.handle_encounters(player)
    has_encounters = player.encounters.is_a?(Array) && !player.encounters.empty?
    map_mismatch = !$game_map.nil? && player.map_id != $game_map.map_id
    if player.rf_event.nil? || $game_map.nil? || map_mismatch || !has_encounters
      if map_mismatch && player.rf_encounter_events.is_a?(Hash) && !player.rf_encounter_events.empty?
        grace = ($game_temp.vms[:voe_departed_grace] ||= {})
        deadline = (grace[player.id] ||= Time.now + GRACE_PERIOD_SECONDS)
        if Time.now >= deadline
          grace.delete(player.id)
          VMS.clear_encounter_proxies(player)
        end
        return
      end
      $game_temp.vms[:voe_departed_grace]&.delete(player.id)
      VMS.clear_encounter_proxies(player)
      return
    end
    $game_temp.vms[:voe_departed_grace]&.delete(player.id)
    claimed = ($game_temp.vms[:voe_claimed_uids] ||= {})
    motion = ($game_temp.vms[:voe_proxy_motion] ||= {})
    live_uids = []
    player.encounters.each do |tuple|
      next unless tuple.is_a?(Array) && tuple.length >= 10
      uid = tuple[0]
      next if claimed[uid]
      _, x, y, real_x, real_y, direction, pattern, graphic, opacity, pkmn_hash, move_speed = tuple
      live_uids << uid
      ($game_temp.vms[:voe_proxy_data] ||= {})[uid] = [player.id, pkmn_hash]
      rf = player.rf_encounter_events[uid]
      if rf.nil? || rf[:event].erased?
        player.rf_encounter_events.delete(uid) if rf
        rf = VMS.create_encounter_event(player.map_id, uid, pkmn_hash)
        player.rf_encounter_events[uid] = rf
      end
      ev = rf[:event]
      ev.x = x
      ev.y = y
      ev.direction = direction
      ev.pattern = pattern
      ev.character_name = graphic
      ev.opacity = opacity
      real_distance = Math.sqrt((ev.real_x - real_x) ** 2 + (ev.real_y - real_y) ** 2)
      if !VMS::SMOOTH_MOVEMENT || real_distance >= VMS::SNAP_DISTANCE
        ev.real_x = real_x
        ev.real_y = real_y
        motion.delete(uid)
      else
        m = motion[uid]
        if m.nil? || m[:target_x] != real_x || m[:target_y] != real_y
          prev_grid_x = m ? m[:target_grid_x] : x
          prev_grid_y = m ? m[:target_grid_y] : y
          dist_tiles = [1, Math.sqrt((x - prev_grid_x) ** 2 + (y - prev_grid_y) ** 2)].max
          motion[uid] = {
            event: ev,
            start_x: ev.real_x, start_y: ev.real_y,
            target_x: real_x, target_y: real_y,
            target_grid_x: x, target_grid_y: y,
            duration: VMS.move_time_for_speed(move_speed) * dist_tiles,
            elapsed: 0.0
          }
        else
          m[:event] = ev
        end
      end
      ev.calculate_bush_depth
      ev.refresh
    end
    (player.rf_encounter_events.keys - live_uids).each { |uid| VMS.delete_encounter_proxy(player, uid) }
    incoming_uids = player.encounters.map { |t| t[0] if t.is_a?(Array) }.compact
    claimed.keys.each { |uid| claimed.delete(uid) unless incoming_uids.include?(uid) }
  end

  def self.move_time_for_speed(move_speed)
    val = move_speed || 3
    return 0.05 if val >= 6
    return 0.1 if val == 5
    2.0 / (2**val)
  end

  def self.step_encounter_proxy_movement
    motion = $game_temp.vms[:voe_proxy_motion]
    return if motion.nil? || motion.empty?
    now = System.uptime
    last = $game_temp.vms[:voe_proxy_motion_tick] || now
    $game_temp.vms[:voe_proxy_motion_tick] = now
    delta_t = now - last
    return if delta_t <= 0
    motion.each_value do |m|
      ev = m[:event]
      next unless ev && !ev.erased?
      m[:elapsed] += delta_t
      if m[:duration] <= 0 || m[:elapsed] >= m[:duration]
        ev.real_x = m[:target_x]
        ev.real_y = m[:target_y]
      else
        t = m[:elapsed] / m[:duration]
        ev.real_x = m[:start_x] + (m[:target_x] - m[:start_x]) * t
        ev.real_y = m[:start_y] + (m[:target_y] - m[:start_y]) * t
      end
    end
    motion.delete_if { |_, m| m[:duration] <= 0 || m[:elapsed] >= m[:duration] }
  end

  def self.pbInteractSyncedEncounter(uid)
    data = $game_temp.vms[:voe_proxy_data] && $game_temp.vms[:voe_proxy_data][uid]
    unless data
      VMS.log("EncounterSync: pbInteractSyncedEncounter(#{uid}) found no proxy data -- claim not sent", true)
      return
    end
    owner_id, pkmn_hash = data
    pkmn = VMS.dehash_pokemon(pkmn_hash)
    return unless pkmn
    ($game_temp.vms[:voe_claimed_uids] ||= {})[uid] = true
    seq = ($game_temp.vms[:voe_claim_seq] || 0) + 1
    $game_temp.vms[:voe_claim_seq] = seq
    $game_temp.vms[:voe_pending_claim] = [uid, seq]
    owner = VMS.get_player(owner_id)
    VMS.delete_encounter_proxy(owner, uid) if owner
    WildBattle.start(pkmn)
  end

  def self.drive_encounters_while_busy
    scene_map_ticking = $scene.is_a?(Scene_Map) && !$game_temp.in_menu && !$game_temp.message_window_showing
    return if scene_map_ticking
    return if $game_map.nil? || $game_map.map_id < 2
    return unless VMS.is_encounter_authority?
    return if VOESettings::BLACK_LIST_MAPS.include?($game_map.map_id)
    return if VOESettings::DISABLE_SETTINGS || $PokemonSystem.owpkmnenabled == 1
    return unless $PokemonEncounters
    $game_temp.vms[:voe_busy_drive_frames] ||= 0
    $game_temp.vms[:voe_busy_drive_frames] += 1
    return if $game_temp.vms[:voe_busy_drive_frames] < 600
    $game_temp.vms[:voe_busy_drive_frames] = 0
    $game_map.events.each_value do |event|
      next unless event.name[/OverworldPkmn/i]
      next if event.variable.nil?
      pbPokemonIdle(event)
    end
    pbGenerateOverworldEncounters
  end

  def self.ensure_voe_override_installed
    return if @voe_override_installed
    return unless Object.private_method_defined?(:pbGenerateOverworldEncounters) ||
                  Object.method_defined?(:pbGenerateOverworldEncounters)
    Object.class_eval do
      alias_method :vms_voe_generate_overworld_encounters, :pbGenerateOverworldEncounters
      def pbGenerateOverworldEncounters(water = false)
        if VMS.is_connected? && VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC && $game_map
          begin
            VMS.update_encounter_authority_transition
          rescue StandardError => e
            VMS.log("EncounterSync: transition error: #{e.message}", true) rescue nil
          end
          return unless VMS.is_encounter_authority?
        end
        vms_voe_generate_overworld_encounters(water)
      end

      if Object.private_method_defined?(:pbPokemonIdle) || Object.method_defined?(:pbPokemonIdle)
        alias_method :vms_voe_pokemon_idle, :pbPokemonIdle
        def pbPokemonIdle(evt)
          return if VMS.is_connected? && VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC && !VMS.is_encounter_authority?
          vms_voe_pokemon_idle(evt)
        end
      end
    end
    EventHandlers.add(:on_enter_map, :clear_previous_overworld_encounters, proc { |old_map_id|
      next if VOESettings::BLACK_LIST_MAPS.include?($game_map.map_id)
      next if $game_map.map_id < 2
      next if old_map_id.nil? || old_map_id < 2
      next unless $map_factory

      skip_destroy = false
      if VMS.is_connected? && VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC
        skip_destroy = VMS.get_players.any? { |p| p.id != $player.id && p.map_id == old_map_id }
      end

      unless skip_destroy
        map = $map_factory.getMapNoAdd(old_map_id)
        map.events.each_value do |event|
          next unless event.name[/OverworldPkmn/i]
          pbDestroyOverworldEncounter(event, true, false)
        end
      end
      VOESettings.current_encounters = 0

      pbGenerateOverworldEncounters
    })

    EventHandlers.add(:on_frame_update, :move_overworld_encounters, proc {
      next if VOESettings::BLACK_LIST_MAPS.include?($game_map.map_id)
      next if $game_map.map_id < 2
      next if VOESettings::DISABLE_SETTINGS || $PokemonSystem.owpkmnenabled == 1
      connected_sync = VMS.is_connected? && VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC
      next if $game_temp.in_menu && !connected_sync
      next if !$PokemonEncounters
      $game_temp.frames_updated += 1
      next if $game_temp.frames_updated < 600
      $game_temp.frames_updated = 0
      $game_map.events.each_value do |event|
        next unless event.name[/OverworldPkmn/i]
        next if event.variable.nil?
        pbPokemonIdle(event)
      end
      pbGenerateOverworldEncounters
    })
    @voe_override_installed = true
  end
end
