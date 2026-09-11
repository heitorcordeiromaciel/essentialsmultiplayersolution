module VMS
  class << self
    alias vms_follower_generate_player_data generate_player_data unless method_defined?(:vms_follower_generate_player_data)
    def generate_player_data
      data = vms_follower_generate_player_data
      if VMS::ENABLE_FOLLOWER_SYNC && defined?(FollowingPkmn)
        begin
          if FollowingPkmn.active? && !FollowingPkmn.hidden?
            ev = FollowingPkmn.get_event
            if ev
              data[VMS::PACKET_KEYS[:follower]] = [
                ev.x, ev.y, ev.real_x, ev.real_y, ev.direction, ev.pattern, ev.character_name, ev.opacity
              ]
            end
          end
        rescue StandardError => e
          VMS.log("FollowerSync: Error generating follower data: #{e.message}", true) rescue nil
        end
      end
      data
    end

    alias vms_follower_handle_player handle_player unless method_defined?(:vms_follower_handle_player)
    def handle_player(player)
      vms_follower_handle_player(player)
      VMS.handle_follower(player) if VMS::ENABLE_FOLLOWER_SYNC
    end
  end

  def self.create_follower_event(map_id, id)
    rf_event = Rf.create_event(map_id) do |event|
      event.x = 0
      event.y = 0
      event.name = "vms_follower_#{id}"
      page = RPG::Event::Page.new
      page.list.clear
      page.trigger = 0
      page.through = true
      event.pages = [page]
    end
    rf_event[:event].name = "vms_follower_#{id}"
    return rf_event
  end

  # Mirrors VMS.event_deletion_possible? (003_User_Functions/001_VMS_User_Functions.rb)
  # but scoped entirely to the follower's OWN event -- deliberately never
  # reads player.rf_event. Reusing event_deletion_possible? here was a bug:
  # it starts with `return false if player.rf_event.nil?`, and every path
  # that needs to delete the follower proxy because the PLAYER proxy is
  # already gone (map no longer connected, etc.) runs exactly when
  # player.rf_event has already been nulled a few lines earlier in
  # VMS.process, the same tick, before handle_player/handle_follower ever
  # runs. That made the guard always fail in precisely the case it needed to
  # pass, so Rf.delete_event never ran -- yet rf_follower_event was still
  # set to nil right after regardless, leaking the orphaned event/sprite.
  def self.follower_event_deletion_possible?(player)
    return false if player.rf_follower_event.nil?
    return false unless $scene.is_a?(Scene_Map)
    event_map_id = player.rf_follower_event[:event].map_id
    return false unless $map_factory.areConnected?(event_map_id, $game_map.map_id)
    return false if $scene.spriteset(event_map_id).nil?
    return true
  end

  def self.delete_follower_event(player)
    return unless player.rf_follower_event
    Rf.delete_event(player.rf_follower_event) if VMS.follower_event_deletion_possible?(player)
    player.rf_follower_event = nil
  end

  def self.handle_follower(player)
    if player.rf_event.nil?
      if player.rf_follower_event
        Rf.delete_event(player.rf_follower_event) if VMS.follower_event_deletion_possible?(player)
        player.rf_follower_event = nil
      end
      return
    end
    if player.follower.nil?
      if player.rf_follower_event
        Rf.delete_event(player.rf_follower_event) if VMS.follower_event_deletion_possible?(player)
        player.rf_follower_event = nil
      end
      return
    end
    fx, fy, frx, fry, fdirection, fpattern, fgraphic, fopacity = player.follower
    if player.rf_follower_event.nil? || player.rf_follower_event[:event].erased? ||
       player.rf_follower_event[:event].map_id != player.map_id
      if player.rf_follower_event
        Rf.delete_event(player.rf_follower_event) if VMS.follower_event_deletion_possible?(player)
        player.rf_follower_event = nil
      end
      return unless $map_factory.areConnected?(player.map_id, $game_map.map_id)
      player.rf_follower_event = VMS.create_follower_event(player.map_id, player.id)
    end
    ev = player.rf_follower_event[:event]
    ev.x = fx
    ev.y = fy
    ev.direction = fdirection
    ev.pattern = fpattern
    ev.character_name = fgraphic
    ev.through = true
    ev.opacity = player.rf_event.is_a?(Hash) ? player.rf_event[:event].opacity : fopacity
    if VMS::SMOOTH_MOVEMENT
      real_distance = Math.sqrt((ev.real_x - frx) ** 2 + (ev.real_y - fry) ** 2)
      if real_distance < VMS::SNAP_DISTANCE
        ev.real_x = Math.lerp(ev.real_x, frx, VMS::SMOOTH_MOVEMENT_ACCURACY)
        ev.real_y = Math.lerp(ev.real_y, fry, VMS::SMOOTH_MOVEMENT_ACCURACY)
      else
        ev.real_x = frx
        ev.real_y = fry
      end
    else
      ev.real_x = frx
      ev.real_y = fry
    end
    ev.calculate_bush_depth
    ev.refresh
  end
end
