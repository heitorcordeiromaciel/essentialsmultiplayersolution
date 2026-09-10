class Game_Event
  def erased
    return @erased
  end

  def vms_sync_tagged?
    return @event.name[/VMSSync/i] ? true : false
  end

  alias vms_sync_initialize initialize unless method_defined?(:vms_sync_initialize)
  def initialize(map_id, event, map = nil)
    vms_sync_initialize(map_id, event, map)
    # Catch-up: if this tagged event was already erased by someone else
    # before this client ever loaded the map it's on, apply that now.
    if VMS.is_connected? && vms_sync_tagged? && !@erased
      if VMS.get_variable("vmssync_erased_#{@map_id}_#{id}")
        $game_temp.vms[:vms_sync_applying_remote] = true
        erase
        $game_temp.vms[:vms_sync_applying_remote] = false
      end
    end
  end

  alias vms_sync_erase erase unless method_defined?(:vms_sync_erase)
  def erase
    vms_sync_erase
    if VMS.is_connected? && !$game_temp.vms[:vms_sync_applying_remote] && vms_sync_tagged?
      VMS.set_variable("vmssync_erased_#{@map_id}_#{id}", true)
    end
  end
end

class Game_SelfSwitches
  def self.vms_sync_key_tagged?(map_id, event_id)
    if $game_map && $game_map.map_id == map_id
      event = $game_map.events[event_id]
      return event.vms_sync_tagged? if event
    end
    begin
      return false unless $map_factory&.hasMap?(map_id)
      map_data = $map_factory.getMap(map_id, false)
      event = map_data&.events&.[](event_id)
      return event.vms_sync_tagged? if event
    rescue StandardError
    end
    return false
  end

  alias vms_sync_self_switch_set []= unless method_defined?(:vms_sync_self_switch_set)
  def []=(key, value)
    vms_sync_self_switch_set(key, value)
    if VMS.is_connected? && !$game_temp.vms[:vms_sync_applying_remote] && key.is_a?(Array) && key.length == 3
      map_id, event_id, letter = key
      if Game_SelfSwitches.vms_sync_key_tagged?(map_id, event_id)
        VMS.set_variable("vmssync_ss_#{map_id}_#{event_id}_#{letter}", value)
      end
    end
  end
end

module VMS
  # Diffs old vs. new online_variables and applies any changed VMSSync keys
  # locally. Called from VMS.process right after online_variables is
  # replaced wholesale with the server's current snapshot.
  def self.apply_vmssync_variables(old_vars, new_vars)
    return unless new_vars.is_a?(Hash)
    new_vars.each do |key, value|
      next unless key.is_a?(String) && key.start_with?("vmssync_")
      next if old_vars.is_a?(Hash) && old_vars[key] == value
      parts = key.split("_")
      $game_temp.vms[:vms_sync_applying_remote] = true
      begin
        if parts[1] == "ss" && parts.length >= 5
          map_id   = parts[2].to_i
          event_id = parts[3].to_i
          letter   = parts[4]
          $game_self_switches[[map_id, event_id, letter]] = value
          $game_map.need_refresh = true if $game_map && $game_map.map_id == map_id
        elsif parts[1] == "erased" && value && parts.length >= 4
          map_id   = parts[2].to_i
          event_id = parts[3].to_i
          if $game_map && $game_map.map_id == map_id
            ev = $game_map.events[event_id]
            ev.erase if ev && !ev.erased
          end
        elsif parts[1] == "gs" && parts.length >= 3
          number = parts[2].to_i
          $game_switches[number] = value
          $game_map.need_refresh = true if $game_map
        elsif parts[1] == "gv" && parts.length >= 3
          number = parts[2].to_i
          $game_variables[number] = value
          $game_map.need_refresh = true if $game_map
        end
      rescue StandardError => e
        VMS.log("EventSync: Error applying #{key}: #{e.message}", true) rescue nil
      ensure
        $game_temp.vms[:vms_sync_applying_remote] = false
      end
    end
  end

  # Sets a regular (non-self) Game Switch and relays it to every other
  # connected client, Usage:
  #   VMS.sync_switch(42, true)
  def self.sync_switch(number, value)
    $game_switches[number] = value
    $game_map.need_refresh = true if $game_map
    VMS.set_variable("vmssync_gs_#{number}", value) if VMS.is_connected?
  end

  # Sets a regular Game Variable and relays it to every other connected client, Usage:
  #   VMS.sync_variable(12, 5)
  #   VMS.sync_variable(13, "Hello")
  def self.sync_variable(number, value)
    $game_variables[number] = value
    $game_map.need_refresh = true if $game_map
    VMS.set_variable("vmssync_gv_#{number}", value) if VMS.is_connected?
  end
end
