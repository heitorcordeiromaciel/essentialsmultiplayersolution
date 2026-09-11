module VMS
  class << self
    alias vms_encounter_generate_player_data generate_player_data unless method_defined?(:vms_encounter_generate_player_data)
    def generate_player_data
      data = vms_encounter_generate_player_data
      if VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC
        begin
          VMS.ensure_voe_override_installed
          data[VMS::PACKET_KEYS[:encounters]] = VMS.build_encounter_broadcast
          # Must read from $game_temp.vms[:voe_pending_claim] (a plain local
          # variable), NOT VMS.get_self.encounter_claim -- the outgoing diff
          # in VMS.update compares against own_player's OWN stored field, so
          # setting the field directly means "old" and "new" are always the
          # same object and the diff never sees a change to transmit.
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

    # Runs every Graphics.update call regardless of scene, so the local
    # authority's own encounters keep moving/despawning/spawning even while
    # busy (menu/battle), and proxy movement keeps interpolating smoothly
    # independent of network tick rate.
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

  # -------------------------------------------------------------------------
  # Authority election
  # -------------------------------------------------------------------------

  # Uses live $game_map for self instead of the synced player mirror, which
  # lags one round trip behind right after actually changing maps.
  def self.currently_has_real_encounters?(map_id)
    return false unless $game_map && $game_map.map_id == map_id
    $game_map.events.each_value do |event|
      return true if event.name[/OverworldPkmn/i] && event.variable
    end
    false
  end

  # Deliberately ignores busy status: authority only changes hands when the
  # holder actually leaves the map, not on every menu/battle -- busy-
  # triggered handoffs used to be constant and were the source of most sync
  # bugs. VMS.update (broadcast + claim handling) still runs regardless of
  # scene while busy; only VOE's own movement/spawn tick pauses, same as
  # solo play.
  def self.encounter_authority_for_map(map_id)
    candidates = VMS.get_players.reject { |p| p.id == $player.id }.select { |p| p.map_id == map_id }
    candidates << VMS.get_self if $game_map && $game_map.map_id == map_id && VMS.get_self
    return nil if candidates.empty?
    # Sticky via observable shared state (who's actually broadcasting real
    # data) rather than private per-client memory, so all clients converge
    # on the same winner independently.
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

  # -------------------------------------------------------------------------
  # Authority side: broadcast current encounters
  # -------------------------------------------------------------------------

  # event.id is a per-map, recycled sequence number, not a stable identity
  # -- this mints/reuses a synthetic uid per live Pokemon object so proxies
  # and claims stay consistent across handoffs and recycled ids.
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

  # How long a former authority keeps broadcasting its frozen real data
  # after losing an election before actually destroying it, giving the new
  # authority a chance to adopt it via the normal proxy-rendering path
  # instead of losing it outright (map/authority-leave races otherwise
  # tend to destroy-and-recreate in the same tick, with nothing to adopt).
  GRACE_PERIOD_SECONDS = 1.0

  def self.update_encounter_authority_transition
    map_id = $game_map.map_id
    was_map = $game_temp.vms[:voe_authority_map]

    # Leaving a map we held authority for is unconditionally relinquished
    # right away, independent of whether we also become authority for our
    # NEW map (the common solo-play case) -- those are independent facts,
    # not two outcomes of one check. A grace window is pointless here since
    # build_encounter_broadcast only ever scans $game_map (the new map), so
    # we can't keep broadcasting the old map's data regardless.
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
      # Still on the same map, but a lower-id candidate now outranks us --
      # grace period before relinquishing so they can adopt our live data.
      deadline = ($game_temp.vms[:voe_relinquish_deadline] ||= Time.now + GRACE_PERIOD_SECONDS)
      if Time.now >= deadline
        VMS.relinquish_authority(map_id)
        $game_temp.vms[:voe_authority_map] = nil
        $game_temp.vms[:voe_relinquish_deadline] = nil
      end
    end
  end

  # Reuses the exact Game_Event objects already rendered as proxies (real
  # local events via Rf.create_event) instead of letting VOE spawn a fresh
  # random set once it notices we're authority.
  def self.adopt_proxies_as_authority(map_id)
    adopted = 0
    adopted_uids = {}
    # Pass 1: reuse proxies we already happen to have rendered -- seamless,
    # same sprite/object already on screen.
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
          # A single bad proxy must not poison the whole adoption, or the
          # exception would propagate before voe_authority_map gets set,
          # causing adoption to retry (and potentially fail again) forever.
          VMS.log("EncounterSync: Failed to adopt #{uid}: #{e.message}", true) rescue nil
        end
      end
      remote.rf_encounter_events.clear
    end
    # Pass 2: reconstruct anything still-broadcast (thanks to the grace
    # period) that we had no rendered proxy for, straight from the raw
    # synced data -- doesn't depend on our own rendering pipeline having
    # run first, which isn't guaranteed (e.g. the sender is a compiled
    # build we have no visibility into).
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
    # Carry the ORIGINAL uid forward instead of letting the next broadcast
    # scan mint a fresh one embedding this new holder's own id -- otherwise
    # a claim referencing the pre-handoff uid would never match anything in
    # the new holder's voe_uids table, and the real event would never get
    # destroyed on battle.
    ($game_temp.vms[:voe_uids] ||= {})[[ev.map_id, ev.id]] = [pkmn, uid]
  end

  # Removes our own real encounters for a map we're no longer authority
  # for. Operates on $map_factory.getMapNoAdd(map_id) rather than requiring
  # $game_map.map_id == map_id, since this is called for the map being
  # LEFT -- by definition no longer the active map -- and $map_factory
  # keeps recently-visited/connected maps loaded, so its events are still
  # reachable and need cleaning up there.
  def self.relinquish_authority(map_id)
    map = $map_factory && $map_factory.getMapNoAdd(map_id)
    return unless map
    removed = 0
    # Snapshot first -- Rf.delete_event mutates map.events (the same hash).
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
    # Drop this map's uid registrations too, so a stale entry can't coexist
    # with a fresh one minted for the same map/event_id slot later.
    $game_temp.vms[:voe_uids]&.delete_if { |key, _| key.is_a?(Array) && key[0] == map_id }
  end

  # -------------------------------------------------------------------------
  # Authority side: accept remote claims
  # -------------------------------------------------------------------------

  def self.check_encounter_claim(player)
    claim = player.encounter_claim
    return unless claim.is_a?(Array) && claim.length >= 2
    uid, seq = claim
    seen = ($game_temp.vms[:voe_seen_claims] ||= {})
    return if seen[player.id] == seq
    seen[player.id] = seq
    # Deliberately NOT gated on is_encounter_authority? -- during the grace
    # period, the client actually holding the real event has already LOST
    # the election but is still the one broadcasting/holding it, so gating
    # on that would skip the one client that can actually destroy it.
    # voe_uids only ever contains entries THIS client created for its own
    # real events, so checking it directly is already the precise test.
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
        # Shared, cluster-wide flag -- since uids are stable across
        # handoffs, a claim can outlive the specific holder it was meant
        # for; without this a later holder of the same uid could re-apply
        # an already-handled claim and destroy its own fresh copy too.
        VMS.set_variable("voe_claimed_#{uid}", true)
      end
      table.delete(key)
      break
    end
  end

  # -------------------------------------------------------------------------
  # Non-authority side: render + interact with proxies
  # -------------------------------------------------------------------------

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

  # Scoped entirely to the proxy's own event/map rather than reusing the
  # generic VMS.event_deletion_possible?(player), which starts with
  # `return false if player.rf_event.nil?` -- exactly the state right when
  # this needs to succeed, since handle_encounters calls this after
  # player.rf_event has already been nulled elsewhere the same tick.
  def self.encounter_proxy_deletion_possible?(rf)
    return false if rf.nil?
    return false unless $scene.is_a?(Scene_Map)
    event_map_id = rf[:event].map_id
    return false unless $map_factory.areConnected?(event_map_id, $game_map.map_id)
    return false if $scene.spriteset(event_map_id).nil?
    return true
  end

  def self.delete_encounter_proxy(player, uid)
    rf = player.rf_encounter_events[uid]
    return unless rf
    Rf.delete_event(rf) if VMS.encounter_proxy_deletion_possible?(rf)
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
        # This player just left the map their cached proxies belong to.
        # Give our own authority election a beat to notice and adopt these
        # cached proxies (see adopt_proxies_as_authority) before clearing
        # them -- clearing immediately destroyed the only path to that
        # data one tick before adoption could ever use it.
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
    # Uids we ourselves already claimed locally -- the authority takes at
    # least one round trip to process a claim, so its broadcast still
    # lists the uid for a tick or two after we deleted our own proxy for
    # it. Without this we'd immediately recreate it, then delete it again
    # once the claim lands: a visible disappear-then-respawn flicker.
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
      # Real VOE encounters collide by default (that's what makes an
      # adjacent-facing Action Button press trigger them) -- unlike
      # follower proxies, leave through=false so this matches.
      real_distance = Math.sqrt((ev.real_x - real_x) ** 2 + (ev.real_y - real_y) ** 2)
      if !VMS::SMOOTH_MOVEMENT || real_distance >= VMS::SNAP_DISTANCE
        ev.real_x = real_x
        ev.real_y = real_y
        motion.delete(uid)
      else
        # Constant-speed interpolation matching the real event's own
        # move_speed (see Game_Character#move_speed=/update_move), rather
        # than a generic fixed-ratio ease -- so a synced proxy visibly
        # moves at the same pace as VOE's own real movement. The actual
        # per-frame stepping happens in step_encounter_proxy_movement;
        # this just (re)establishes the current target whenever it changes.
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
    # Remove any proxies the authority no longer reports (despawned/claimed).
    (player.rf_encounter_events.keys - live_uids).each { |uid| VMS.delete_encounter_proxy(player, uid) }
    # Forget claims once the authority's own broadcast confirms the uid is
    # actually gone -- keeps voe_claimed_uids from growing forever.
    incoming_uids = player.encounters.map { |t| t[0] if t.is_a?(Array) }.compact
    claimed.keys.each { |uid| claimed.delete(uid) unless incoming_uids.include?(uid) }
  end

  # Mirrors Game_Character#move_speed=: converts a move_speed integer into
  # seconds-to-cross-one-tile (Data/Scripts/004_Game classes/
  # 006_Game_Character.rb:110-124), so proxy interpolation runs at the same
  # rate a real VOE event would move at that same move_speed.
  def self.move_time_for_speed(move_speed)
    val = move_speed || 3
    return 0.05 if val >= 6
    return 0.1 if val == 5
    2.0 / (2**val)
  end

  # Advances every tracked proxy's real_x/real_y toward its current target
  # at a constant rate derived from move_time_for_speed, every frame
  # (independent of network tick rate) -- mirroring Game_Character#
  # update_move's own real-time delta-based interpolation instead of a
  # fixed-ratio-per-received-packet ease.
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

  # Claims BEFORE starting the (blocking) battle, not after: WildBattle.start
  # doesn't return until the fight finishes, so claiming afterward left the
  # real encounter broadcasting as alive for every observer the whole fight.
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
    # See generate_player_data for why this is a plain local variable and
    # NOT VMS.get_self.encounter_claim.
    $game_temp.vms[:voe_pending_claim] = [uid, seq]
    owner = VMS.get_player(owner_id)
    VMS.delete_encounter_proxy(owner, uid) if owner
    WildBattle.start(pkmn)
  end

  # -------------------------------------------------------------------------
  # Keep the world moving even while the local (authority) player is busy
  # -------------------------------------------------------------------------

  # VOE's own :on_frame_update tick only fires from Scene_Map#update ->
  # updateSpritesets (Data/Scripts/003_Game processing/002_Scene_Map.rb:162
  # is the sole call site). The pause menu, dialogue boxes, and the bag
  # never actually reassign $scene in this engine -- they run their own
  # nested blocking render loop from deep inside Scene_Map#update's call
  # stack, so $scene keeps pointing at the original Scene_Map instance the
  # whole time, while Scene_Map#update() itself is paused mid-call and
  # never reaches on_frame_update until they close. So "not busy" can't be
  # tested via $scene.is_a?(Scene_Map) alone -- $game_temp.in_menu/
  # message_window_showing cover the nested-loop cases; a real battle is
  # the one case that genuinely does reassign $scene. Graphics.update (and
  # VMS.update, aliased onto it) keeps firing throughout all of these,
  # which is how this stays reachable in every one of them.
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

  # -------------------------------------------------------------------------
  # Non-authority side: suppress local spawning
  # -------------------------------------------------------------------------

  def self.ensure_voe_override_installed
    return if @voe_override_installed
    return unless Object.private_method_defined?(:pbGenerateOverworldEncounters) ||
                  Object.method_defined?(:pbGenerateOverworldEncounters)
    Object.class_eval do
      alias_method :vms_voe_generate_overworld_encounters, :pbGenerateOverworldEncounters
      def pbGenerateOverworldEncounters(water = false)
        if VMS.is_connected? && VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC && $game_map
          # VOE's own frame-driven tick can race ahead of the (separately
          # network-tick-driven) adoption logic and spawn a fresh random
          # set before there's anything to adopt from -- run the transition
          # check synchronously here so adoption always precedes any
          # possible vanilla generation, on every call path.
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
          # Freeze a relinquished-but-still-in-grace-window encounter in
          # place instead of letting it keep evolving independently of
          # whichever client is about to adopt it.
          return if VMS.is_connected? && VMS::ENABLE_OVERWORLD_ENCOUNTER_SYNC && !VMS.is_encounter_authority?
          vms_voe_pokemon_idle(evt)
        end
      end
    end
    # Replaces VOE's own :on_enter_map handler (NamedEvent#add is a plain
    # hash keyed by this symbol, so re-registering under the same key
    # overrides it outright): the original unconditionally destroys every
    # real OverworldPkmn event on the map being left, with no regard for
    # whether another connected player is still standing on it.
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

    # Replaces VOE's own :on_frame_update handler: the original bails
    # outright while $game_temp.in_menu is true, which would otherwise
    # pause the whole map's simulation for everyone whenever any player has
    # a message box or menu open. Authority gating still happens correctly
    # inside pbPokemonIdle/pbGenerateOverworldEncounters (aliased above) --
    # this only removes VOE's own blanket in_menu bail.
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
