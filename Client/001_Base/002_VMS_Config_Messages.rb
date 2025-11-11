module VMS
  # Toggle to display or hide player messages. (Set to false to disable)
  SHOW_PLAYER_MESSAGES = true

  # ===========
  # Errors
  # ===========
  # Message displayed when the server is inactive.
  SERVER_INACTIVE_MESSAGE = _INTL("The server seems to be inactive...")
  # Message displayed when the player is not connected to the server.
  NOT_CONNECTED_MESSAGE = _INTL("You are not currently connected to the server.")
  # Message displayed when the server is using a different game.
  DIFFERENT_GAME_MESSAGE = _INTL("The server you are attempting to connect to seems to be using a different game...")
  # Message displayed when the server is using a different version.
  DIFFERENT_VERSION_MESSAGE = _INTL("The server you are trying to connect to seems to be using a different version...")
  # Message displayed for a connection issue.
  CONNECTION_ISSUE_MESSAGE = _INTL("There seems to be a connection issue...\\wtnp[20]")
  # Basic error message.
  BASIC_ERROR_MESSAGE = _INTL("An error has occurred.")

  # ===========
  # General
  # ===========
  # Message displayed when disconnected from the server. (Set to "" to disable)
  DISCONNECTED_MESSAGE = _INTL("You have been disconnected.")
  # Message displayed upon server disconnection.
  SERVER_DISCONNECT_MESSAGE = _INTL("The server has disconnected you...")
  # Message displayed when attempting to connect to a full cluster.
  CLUSTER_FULL_MESSAGE = _INTL("The cluster you are trying to connect to appears to be full...")
  # Message displayed when asking for confirmation to disconnect from the server.
  DISCONNECT_CONFIRMATION_MESSAGE = _INTL("Are you sure you want to disconnect?")

  # ===========
  # Interaction
  # ===========
  # Message displayed when another player wants to interact. {1} is the name of the player initiating the interaction.
  INTERACT_MESSAGE = _INTL("{1} wants to interact with you!\\wtnp[20]")
  # Message displayed when waiting for the player to say something during interaction. {1} is the name of the player waiting.
  INTERACTION_WAITING_FOR_YOU_MESSAGE = _INTL("{1} is patiently waiting for you to say something...")
  # Message displayed during interaction, prompting for a choice.
  INTERACTION_CHOICE = _INTL("What action would you like to take?")
  # Message displayed when waiting for the player to say something during interaction. {1} is the name of the player waiting.
  INTERACTION_WAIT_MESSAGE = _INTL("Waiting for {1} to say something...")
  # Message displayed when waiting for the player to respond during interaction. {1} is the name of the player waiting.
  INTERACTION_WAIT_RESPONSE_MESSAGE = _INTL("Waiting for {1} to respond...")
  # Message displayed when waiting for the player to start talking during interaction. {1} is the name of the player waiting.
  INTERACTION_WAIT_SWITCH_MESSAGE = _INTL("Waiting for {1} to start talking...")
  # Message displayed when the other player wants to trade during interaction. {1} is the name of the other player.
  INTERACTION_TRADE_MESSAGE = _INTL("{1} would like to trade with you. \\wt[10]Do you accept?")
  # Message displayed when the other player wants to battle during interaction. {1} is the name of the other player.
  INTERACTION_BATTLE_MESSAGE = _INTL("{1} would like to battle with you. \\wt[10]Do you accept?")

  # ===========
  # Interaction (Errors)
  # ===========
  # Message displayed when the interaction is canceled. {1} is the name of the player canceling the interaction.
  INTERACTION_CANCEL_MESSAGE = _INTL("{1} is no longer interested in interacting with you. What a shame...")
  # Message shown when attempting to interact with someone already interacting with another player. {1} represents the name of the player you are trying to interact with.
  ALREADY_INTERACTING_MESSAGE = _INTL("{1} is already interacting with someone else.")
  # Message displayed when the other player is busy. {1} is the name of the other player.
  INTERACTION_BUSY_MESSAGE = _INTL("{1} is currently busy.")
  # Message displayed when a player is engaged in a battle. {1} is the name of the other player.
  IN_A_BATTLE_MESSAGE = _INTL("{1} is currently in a battle.")
  # Message displayed when a player is engaged in a trade. {1} is the name of the other player.
  IN_A_TRADE_MESSAGE = _INTL("{1} is currently in a trade.")
  # Message displayed when a player disconnects during an interaction. {1} is the name of the player who disconnected.
  PLAYER_DISCONNECT_MESSAGE = _INTL("{1} has disconnected...")
  # Message displayed when a player does not respond. {1} is the name of the player who did not respond.
  PLAYER_NO_RESPONSE_MESSAGE = _INTL("{1} did not respond.")
  # Message displayed when you or the other player are not able to battle.
  INTERACTION_NO_BATTLE_MESSAGE = _INTL("You or the other player are not able to battle.")

  # ===========
  # Trading
  # ===========
  # Message displayed when the player has no tradable Pokémon.
  NO_TRADABLE_MESSAGE = _INTL("You lack any tradable Pokémon.")
  # Message displayed when the trade is canceled by the other player. {1} is the name of the player canceling the trade.
  TRADE_CANCEL_MESSAGE = _INTL("{1} has decided not to trade. What a shame...")
  # Message displayed when the other player has no tradable Pokémon. {1} is the name of the other player.
  OTHER_NO_TRADABLE_MESSAGE = _INTL("{1} has no tradable Pokémon.")
  # Message displayed when waiting for the other player to confirm a trade. {1} is the name of the player waiting.
  TRADE_WAIT_CONFIRM_MESSAGE = _INTL("Waiting for {1} to select a Pokémon...")
  # Message displayed when confirming a trade. {1} is the name of the Pokémon you are offering, and {2} is the name of the Pokémon the other player is offering.
  TRADE_CONFIRMATION_MESSAGE = _INTL("Are you sure you want to trade {1} for {2}?")
  # Message displayed when waiting for the other player to accept a trade. {1} is the name of the player waiting.
  TRADE_WAIT_ACCEPT_MESSAGE = _INTL("Waiting for {1} to accept.")

  # ===========
  # Swap
  # ===========
  # Message displayed when initiating a swap during interaction. {1} is the name of the player being swapped to.
  SWAP_INITIATION_MESSAGE = _INTL("You intend to interact with {1}!\\wtnp[20]")
  # Message displayed when the other player wants you to talk to them during interaction. {1} is the name of the other player.
  INTERACTION_SWAP_MESSAGE = _INTL("{1} would like you to engage in conversation.\\wtnp[20]")

  # ===========
  # Menu
  # ===========
  # Message displayed for menu choices.
  MENU_CHOICES_MESSAGE = _INTL("What action would you like to take?")
  # Message displayed when entering a cluster ID in the menu.
  MENU_ENTER_CLUSTER_ID_MESSAGE = _INTL("Enter the cluster ID:")
  # Message displayed for an invalid cluster ID in the menu.
  MENU_INVALID_CLUSTER_MESSAGE = _INTL("Invalid cluster ID.")
  # Message displayed when a cluster is not found, and a new one is created instead.
  MENU_CLUSTER_NOT_FOUND_MESSAGE = _INTL("Cluster not found; creating a new cluster instead.")
end
