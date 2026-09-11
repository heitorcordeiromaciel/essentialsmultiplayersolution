module VMS
  # Usage: VMS.start_gift(player #<VMS::Player>, is_sender #<Boolean>, kind #<Symbol>, item #<Symbol, nil>, amount #<Integer>)
  # (completes a gift exchange with the specified player; called symmetrically
  # on both clients once the :gift state has been mirrored)
  def self.start_gift(player, is_sender, kind, item, amount)
    begin
      # Check if the player is connected to the server.
      if !VMS.is_connected?
        VMS.message(VMS::NOT_CONNECTED_MESSAGE)
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      desc = (kind == :item) ? _INTL("{1}x {2}", amount, GameData::Item.get(item).name) : _INTL("${1}", amount)
      if is_sender
        # Re-check: the handshake took real time, so re-validate we still
        # have enough to give rather than trusting the value picked earlier.
        if kind == :item
          if $bag.quantity(item) < amount
            VMS.message(VMS::GIFT_INSUFFICIENT_MESSAGE)
            $game_temp.vms[:state] = [:idle, nil]
            return
          end
          $bag.remove_all(item, amount)
        else
          if $player.money < amount
            VMS.message(VMS::GIFT_INSUFFICIENT_MESSAGE)
            $game_temp.vms[:state] = [:idle, nil]
            return
          end
          $player.money -= amount
        end
        VMS.message(_INTL(VMS::GIFT_SENT_MESSAGE, desc, player.name))
      else
        if kind == :item
          if !$bag.can_add?(item, amount)
            VMS.message(VMS::GIFT_BAG_FULL_MESSAGE)
            $game_temp.vms[:state] = [:idle, nil]
            return
          end
          $bag.add_all(item, amount)
        else
          $player.money += amount
        end
        VMS.message(_INTL(VMS::GIFT_RECEIVED_MESSAGE, desc, player.name))
      end
      $game_temp.vms[:state] = [:idle, nil]

      if Game.save
        VMS.message("\\se[]" + _INTL("{1} saved the game.", $player.name) + "\\me[GUI save game]\\wtnp[30]")
      else
        VMS.message("\\se[]" + _INTL("Save failed.") + "\\wtnp[30]")
      end
    end
  rescue StandardError => e
    VMS.log("An error occurred whilst gifting: #{e.message}", true)
    VMS.message(VMS::BASIC_ERROR_MESSAGE)
    $game_temp.vms[:state] = [:idle, nil]
  end
end
