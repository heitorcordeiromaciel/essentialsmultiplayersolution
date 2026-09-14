module VMS
  def self.start_trade(player)
    begin
      player_name = player.name
      if !VMS.is_connected?
        VMS.message(VMS::NOT_CONNECTED_MESSAGE)
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      if $player.able_pokemon_trade_count == 0
        VMS.message(VMS::NO_TRADABLE_MESSAGE)
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      party = VMS.update_party(player)
      if party.count { |pkmn| !pkmn.egg? && !pkmn.shadowPokemon? } == 0
        VMS.message(_INTL(VMS::OTHER_NO_TRADABLE_MESSAGE, player.name))
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      pbChoosePokemon(1, 3, proc { |pkmn| !pkmn.egg? && !pkmn.shadowPokemon? })
      pokemon_index = $game_variables[1]
      pokemon_name = $game_variables[3]
      if pokemon_index == -1
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      $game_temp.vms[:state] = [:trade_confirm, player.id, pokemon_index, pokemon_name]
      if !VMS.await_player_state(player, :trade_confirm, _INTL(VMS::TRADE_WAIT_CONFIRM_MESSAGE, player_name), true, true)
        VMS.message(_INTL(VMS::TRADE_CANCEL_MESSAGE, player.name))
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      party = VMS.update_party(player)
      trade_pokemon_index = player.state[2]
      trade_pokemon_name = player.state[3]
      if trade_pokemon_index == -1 || trade_pokemon_index >= party.length
        VMS.message(_INTL(VMS::TRADE_CANCEL_MESSAGE, player.name))
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      trade_pokemon = party[trade_pokemon_index]
      choices = [_INTL("Confirm Trade"), _INTL("Check my Pokémon"), _INTL("Check {1}'s Pokémon", player.name), _INTL("Cancel")]
      loop do
        choice = VMS.message(_INTL(VMS::TRADE_CONFIRMATION_MESSAGE, pokemon_name, trade_pokemon_name), choices, -1)
        case choice
        when 0
          $game_temp.vms[:state] = [:trade_accept, player.id, pokemon_index, pokemon_name]
          break
        when 1
          pbFadeOutIn do
            summary_scene = PokemonSummary_Scene.new
            summary_screen = PokemonSummaryScreen.new(summary_scene, true)
            summary_screen.pbStartScreen([$player.party[pokemon_index]], 0)
          end
          next
        when 2
          pbFadeOutIn do
            summary_scene = PokemonSummary_Scene.new
            summary_screen = PokemonSummaryScreen.new(summary_scene, true)
            summary_screen.pbStartScreen([trade_pokemon], 0)
          end
          next
        when 3
          $game_temp.vms[:state] = [:idle, nil]
          return
        end
      end

      if !VMS.await_player_state(player, :trade_accept, _INTL(VMS::TRADE_WAIT_ACCEPT_MESSAGE, player_name), true, true)
        VMS.message(_INTL(VMS::TRADE_CANCEL_MESSAGE, player.name))
        $game_temp.vms[:state] = [:idle, nil]
        return
      end

      pbStartTrade(pokemon_index, trade_pokemon, trade_pokemon_name, player.name)
      $game_temp.vms[:state] = [:idle, nil]

      if Game.save
        VMS.message("\\se[]" + _INTL("{1} saved the game.", $player.name) + "\\me[GUI save game]\\wtnp[30]")
      else
        VMS.message("\\se[]" + _INTL("Save failed.") + "\\wtnp[30]")
      end
    end
  rescue StandardError => e
    VMS.log("An error occurred whilst trading: #{e.message}", true)
    VMS.message(VMS::BASIC_ERROR_MESSAGE)
    $game_temp.vms[:state] = [:idle, nil]
  end
end