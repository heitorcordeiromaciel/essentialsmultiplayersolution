module VMS
  def self.start_battle(player, type = :single, size = 6)
    begin
      # In start_battle
      seed_str = VMS.get_cluster_id.to_s
      if $player.id < player.id
        seed_str += hash_pokemon($player.party).to_s
        seed_str += hash_pokemon(player.party).to_s
      else
        seed_str += hash_pokemon(player.party).to_s
        seed_str += hash_pokemon($player.party).to_s
      end

      seed_int = VMS.string_to_integer(seed_str)  # already integer
      srand(seed_int)
      $game_temp.vms[:seed] = seed_int  # MUST store integer
      $game_temp.vms[:battle_player] = player
      $game_temp.vms[:battle_type] = type
      
      # Party Selection Phase
      local_indices = (0...$player.party.length).to_a
      if size > 1 && size <= $player.party.length
        new_party = nil
        ruleset = PokemonRuleSet.new
        ruleset.setNumber(size)
        ruleset.addPokemonRule(AblePokemonRestriction.new)
        pbFadeOutIn {
          scene = PokemonParty_Scene.new
          screen = PokemonPartyScreen.new(scene, $player.party)
          new_party = screen.pbPokemonMultipleEntryScreenEx(ruleset)
        }
        if new_party
          local_indices = []
          new_party.each { |pkmn| local_indices.push($player.party.index(pkmn)) }
        else
          $game_temp.vms[:state] = [:idle, nil]
          return
        end
      end
      
      # Sync selection
      $game_temp.vms[:state] = [:battle_selection, player.id, local_indices]
      if !VMS.await_player_state(player, :battle_selection, _INTL("Waiting for {1} to select Pokémon...", player.name), true, true)
        $game_temp.vms[:state] = [:idle, nil]
        return
      end
      opponent_indices = player.state[2]
      
      # Filter parties
      full_opponent_party = VMS.update_party(player)
      filtered_opponent_party = []
      opponent_indices.each { |i| filtered_opponent_party.push(full_opponent_party[i]) }
      
      old_party = $player.party.dup
      filtered_local_party = []
      local_indices.each { |i| filtered_local_party.push($player.party[i]) }
      $player.party = filtered_local_party
      
      trainer = NPCTrainer.new(player.name, player.trainer_type, 0)
      trainer.id = player.id
      trainer.party = filtered_opponent_party
      
      TrainerBattle.start_core_VMS(trainer)
      
      # Restore party
      $player.party = old_party
      
      $game_temp.vms[:battle_player] = nil
      $game_temp.vms[:battle_type] = nil
      $game_temp.vms[:state] = [:idle, nil]
      VMS.sync_seed
    rescue StandardError => e
      VMS.log("An error occurred whilst battling: #{e.message}", true)
      VMS.message(VMS::BASIC_ERROR_MESSAGE)
      $player.party = old_party if old_party
      $game_temp.vms[:state] = [:idle, nil]
    end
  end
end

class Battle
  def battleAI=(value)
    @battleAI = value
  end

  def pbRandom(x)
    if VMS.is_connected? && !@internalBattle && !$game_temp.vms[:battle_player].nil?
      seed = $game_temp.vms[:seed]
      seed = seed.to_i unless seed.is_a?(Integer)  # force integer just in case
      srand(seed + @turnCount)
      return rand(x)
    end
    return rand(x)
  end

  alias vms_pbCommandPhaseLoop pbCommandPhaseLoop unless method_defined?(:vms_pbCommandPhaseLoop)
  def pbCommandPhaseLoop(isPlayer)
    vms_pbCommandPhaseLoop(isPlayer)
    if VMS.is_connected? && isPlayer
      picks = @choices.map do |choice|
        next nil if choice.nil?
        # @choices is an array of arrays: [type, index, move_object, target, item]
        [choice[0], choice[1], nil, choice[3], choice[4]]
      end
      owner = pbGetOwnerIndexFromBattlerIndex(@battlers[0].index)
      mega_idx = @megaEvolution[0][owner]
      zmove_idx = @zMove[0][owner] rescue -1
      dynamax_idx = @dynamax[0][owner] rescue -1
      tera_idx = @terastallize[0][owner] rescue -1
      $game_temp.vms[:state] = [:battle_command, $game_temp.vms[:state][1], @turnCount, picks, mega_idx, zmove_idx, dynamax_idx, tera_idx]
    end
  end

  alias vms_pbConsumeItemInBag pbConsumeItemInBag unless method_defined?(:vms_pbConsumeItemInBag)
  def pbConsumeItemInBag(item, idxBattler)
    return if !item
    return if !GameData::Item.get(item).consumed_after_use?
    return if VMS.is_connected? && @battleAI.is_a?(Battle::VMS_AI)
    vms_pbConsumeItemInBag(item, idxBattler)
  end

  alias vms_pbItemMenu pbItemMenu unless method_defined?(:vms_pbItemMenu)
  def pbItemMenu(idxBattler, firstAction)
    @internalBattle = true if VMS.is_connected? && @battleAI.is_a?(Battle::VMS_AI)
    ret = vms_pbItemMenu(idxBattler, firstAction)
    @internalBattle = false if VMS.is_connected? && @battleAI.is_a?(Battle::VMS_AI)
    return ret
  end

  # For choosing a replacement Pokémon when prompted in the middle of other
  # things happening (U-turn, Baton Pass, in def pbEORSwitch).
  def pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
    if !@controlPlayer && pbOwnedByPlayer?(idxBattler)
      newIndex = pbPartyScreen(idxBattler, checkLaxOnly, canCancel)
      $game_temp.vms[:state] = [:battle_new_switch, $game_temp.vms[:state][1], idxBattler, newIndex] if VMS.is_connected?
      return newIndex
    end
    return @battleAI.pbDefaultChooseNewEnemy(idxBattler)
  end

  class VMS_AI < AI
    # Choosing a new switch in pokémon
    def pbDefaultChooseNewEnemy(idxBattler)
      set_up(idxBattler)
      player_name = $game_temp.vms[:state][1] ? VMS.get_player($game_temp.vms[:state][1])&.name : "Unknown"
      msgwindow = @battle.scene.sprites["messageWindow"]
      loop do
        player = VMS.get_player($game_temp.vms[:state][1])
        if player.nil?
          @battle.pbDisplayPaused(_INTL("{1} has disconnected...", player_name))
          @battle.decision = 1
          msgwindow.visible = false
          msgwindow.setText("")
          return -1
        end
        if !VMS.is_connected?
          @battle.pbDisplayPaused(_INTL("You have disconnected..."))
          @battle.decision = 2
          msgwindow.visible = false
          msgwindow.setText("")
          return -1
        end
        if player.state&.length >= 4 && player.state[0] == :battle_new_switch
          # player.state[2] is the battler index from the opponent's perspective
          # If they are switching their battler 0, it's my battler 1.
          # If they are switching their battler 2, it's my battler 3.
          opp_idx = (idxBattler == 1) ? 0 : 2
          if player.state[2] == opp_idx
            msgwindow.visible = false
            msgwindow.setText("")
            return player.state[3]
          end
        end
        if msgwindow.text == ""
          @battle.scene.pbShowWindow(Battle::Scene::MESSAGE_BOX)
          msgwindow.visible = true
          msgwindow.setText(_INTL("Waiting for {1} to select a new Pokémon...", player.name))
          while msgwindow.busy?
            @battle.scene.pbUpdate(msgwindow)
          end
        end
        @battle.scene.pbUpdate
      end
    end

    # Choose an action.
    def pbDefaultChooseEnemyCommand(idxBattler)
      set_up(idxBattler)
      ret = false
      player = $game_temp.vms[:battle_player]
      player_name = player.name
      msgwindow = @battle.scene.sprites["messageWindow"]
      loop do
        player = VMS.get_player(player.id)
        if player.nil?
          @battle.pbDisplayPaused(_INTL("{1} has disconnected...", player_name))
          @battle.decision = 1
          msgwindow.visible = false
          msgwindow.setText("")
          return
        end
        if !VMS.is_connected?
          @battle.pbDisplayPaused(_INTL("You have disconnected..."))
          @battle.decision = 2
          msgwindow.visible = false
          msgwindow.setText("")
          return
        end
        # Check if opponent has forfeited (state is :idle, meaning they left the battle)
        if player.state&.length >= 1 && player.state[0] == :idle
          msgwindow.visible = false
          msgwindow.setText("")
          @battle.pbDisplayPaused(_INTL("{1} has forfeited.", player_name))
          @battle.decision = 1
          return
        end
        if player.state&.length >= 3 && player.state[2] == @battle.turnCount
          msgwindow.visible = false
          msgwindow.setText("")
          opp_idx = (idxBattler == 1) ? 0 : 2
          if player.state.length >= 4 && player.state[3]&.length > opp_idx && player.state[3][opp_idx]&.length >= 1
            case player.state[3][opp_idx][0]
            when :SwitchOut
              @battle.pbRegisterSwitch(idxBattler, player.state[3][opp_idx][1])
              return
            when :UseItem
              @battle.pbRegisterItem(idxBattler, player.state[3][opp_idx][1], player.state[3][opp_idx][2], player.state[3][opp_idx][3])
              return
            when :UseMove
              target = player.state[3][opp_idx][3]
              if @battle.pbSideSize(0) > 1 && target.is_a?(Integer) && target >= 0
                target = case target
                         when 0 then 1
                         when 1 then 0
                         when 2 then 3
                         when 3 then 2
                         else target
                         end
              end
              @battle.pbRegisterMove(idxBattler, player.state[3][opp_idx][1], false)
              @battle.pbRegisterTarget(idxBattler, target)
              @battle.pbRegisterMegaEvolution(idxBattler) if player.state.length > 4 && player.state[4] == opp_idx
              @battle.pbRegisterZMove(idxBattler) if player.state.length > 5 && player.state[5] == opp_idx
              @battle.pbRegisterDynamax(idxBattler) if player.state.length > 6 && player.state[6] == opp_idx
              @battle.pbRegisterTerastallize(idxBattler) if player.state.length > 7 && player.state[7] == opp_idx
              return
            end
          end
        end
        if msgwindow.text == ""
          @battle.scene.pbShowWindow(Battle::Scene::MESSAGE_BOX)
          msgwindow.visible = true
          msgwindow.setText(_INTL("Waiting for {1} to select a move...", player_name))
          while msgwindow.busy?
            @battle.scene.pbUpdate(msgwindow)
          end
        end
        @battle.scene.pbUpdate
      end
    end
  end
end

class TrainerBattle
  def self.start_core_VMS(*args)
    outcome_variable = $game_temp.battle_rules["outcomeVar"] || 1
    can_lose         = $game_temp.battle_rules["canLose"] || false
    # Skip battle if the player has no able Pokémon, or if holding Ctrl in Debug mode
    if BattleCreationHelperMethods.skip_battle?
      return BattleCreationHelperMethods.skip_battle(outcome_variable, true)
    end
    # Record information about party Pokémon to be used at the end of battle (e.g.
    # comparing levels for an evolution check)
    EventHandlers.trigger(:on_start_battle)
    # Generate information for the foes
    foe_trainers, foe_items, foe_party, foe_party_starts = TrainerBattle.generate_foes(*args)
    # Generate information for the player and partner trainer(s)
    player_trainers, ally_items, player_party, player_party_starts = BattleCreationHelperMethods.set_up_player_trainers(foe_party)
    # Create the battle scene (the visual side of it)
    scene = BattleCreationHelperMethods.create_battle_scene
    # Create the battle class (the mechanics side of it)
    battle = Battle.new(scene, player_party, foe_party, player_trainers, foe_trainers)
    battle.battleAI     = Battle::VMS_AI.new(battle)
    battle.party1starts = player_party_starts
    battle.party2starts = foe_party_starts
    battle.ally_items   = ally_items
    battle.items        = foe_items
    battle.internalBattle = false
    # Set various other properties in the battle class
    setBattleRule("canLose")
    if $game_temp.vms[:battle_type] == :double
      setBattleRule("double")
    else
      setBattleRule("#{foe_trainers.length}v#{foe_trainers.length}") if $game_temp.battle_rules["size"].nil?
    end
    BattleCreationHelperMethods.prepare_battle(battle)
    $game_temp.clear_battle_rules
    # Perform the battle itself
    outcome = 0
    pbBattleAnimation(pbGetTrainerBattleBGM(foe_trainers), (battle.singleBattle?) ? 1 : 3, foe_trainers) do
      pbSceneStandby { outcome = battle.pbStartBattle }
      BattleCreationHelperMethods.after_battle(outcome, can_lose)
    end
    Input.update
    # Save the result of the battle in a Game Variable (1 by default)
    BattleCreationHelperMethods.set_outcome(outcome, outcome_variable, true)
    return outcome
  end
end