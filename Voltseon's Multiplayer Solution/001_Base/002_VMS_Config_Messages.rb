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
  # Message displayed when the other player wants to battle during interaction. {1} is the name of the other player, {2} is the battle type.
  INTERACTION_BATTLE_MESSAGE = _INTL("{1} would like to have a {2} with you. \\wt[10]Do you accept?", "{1}", "{2}")
  # Message displayed when selecting a battle type.
  SELECT_BATTLE_TYPE_MESSAGE = _INTL("Select a battle type:")
  # Battle type names.
  BATTLE_TYPE_SINGLE = _INTL("Single Battle")
  BATTLE_TYPE_DOUBLE = _INTL("Double Battle")
  # Message displayed when selecting a party size.
  SELECT_PARTY_SIZE_MESSAGE = _INTL("Select the number of Pokémon to use:")
  # Party size options.
  PARTY_SIZE_3 = _INTL("3 Pokémon")
  PARTY_SIZE_4 = _INTL("4 Pokémon")
  PARTY_SIZE_6 = _INTL("6 Pokémon")
  # Message displayed when a player doesn't have enough Pokémon for the selected size.
  NOT_ENOUGH_POKEMON_MESSAGE = _INTL("One of the players doesn't have enough Pokémon for this battle size.")

  # ===========
  # Interaction (Errors)
  # ===========
  # Message displayed when the interaction is canceled. {1} is the name of the player canceling the interaction.
  INTERACTION_CANCEL_MESSAGE = _INTL("{1} is no longer interested in interacting with you. What a shame...")
  # Message shown when attempting to interact with someone already interacting with another player. {1} represents the name of the player you are trying to interact with.
  ALREADY_INTERACTING_MESSAGE = _INTL("{1} is already interacting with someone else.")
  # Message displayed when the other player is busy. {1} is the name of the other player.
  INTERACTION_BUSY_MESSAGE = _INTL("{1} is currently busy.")
  # Tag appended to a player's name tag while they are busy.
  INTERACTION_BUSY_TAG = _INTL("(Busy)")
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
  # Gifting
  # ===========
  # Message displayed when a player is engaged in a gift exchange. {1} is the name of the other player.
  IN_A_GIFT_MESSAGE = _INTL("{1} is currently exchanging a gift.")
  # Message displayed when choosing what type of gift to give.
  GIFT_TYPE_CHOICE = _INTL("What would you like to gift?")
  # Message displayed when choosing how many of an item to gift. {1} is the name of the item.
  GIFT_ITEM_QUANTITY_MESSAGE = _INTL("How many {1} would you like to give?")
  # Message displayed when choosing how much money to gift.
  GIFT_MONEY_AMOUNT_MESSAGE = _INTL("How much money would you like to give?")
  # Message displayed when the player has no money to gift.
  NO_GIFTABLE_MONEY_MESSAGE = _INTL("You don't have any money to give.")
  # Message displayed when the other player offers a gift. {1} is the name of the other player, {2} is a description of the gift.
  GIFT_OFFER_MESSAGE = _INTL("{1} wants to give you {2}. Accept?")
  # Message displayed when the receiving player's Bag is full.
  GIFT_BAG_FULL_MESSAGE = _INTL("Your Bag doesn't have room for that.")
  # Message displayed when the sending player no longer has enough of what they offered to give.
  GIFT_INSUFFICIENT_MESSAGE = _INTL("You no longer have enough to give.")
  # Message displayed to the sender when a gift is successfully given. {1} is a description of the gift, {2} is the name of the recipient.
  GIFT_SENT_MESSAGE = _INTL("You gave {1} to {2}.\\wtnp[30]")
  # Message displayed to the recipient when a gift is successfully received. {1} is a description of the gift, {2} is the name of the sender.
  GIFT_RECEIVED_MESSAGE = _INTL("You received {1} from {2}!\\wtnp[30]")

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
  # Message displayed when no clusters are available.
  NO_CLUSTERS_AVAILABLE_MESSAGE = _INTL("No clusters are currently available. Create a new one?")
  # Message displayed when selecting a cluster to join.
  SELECT_CLUSTER_MESSAGE = _INTL("Select a cluster to join:")

  # ===========
  # Multi Battle
  # ===========
  # Title shown above the lobby browser list.
  MB_MENU_TITLE = _INTL("Multi Battle Lobbies")
  # Label for the "create new lobby" option.
  MB_CREATE_LOBBY_OPTION = _INTL("Create New Lobby")
  # Shown when no lobbies exist; asks if the player wants to create one.
  MB_NO_LOBBIES_MESSAGE = _INTL("No multi battle lobbies found. Create a new one?")
  # Prompt asking the player to choose a team.
  MB_SELECT_TEAM_MESSAGE = _INTL("Choose your team:")
  # Team and slot label options.
  MB_TEAM_0_SLOT_0 = _INTL("Team 0 (Slot A)")
  MB_TEAM_0_SLOT_1 = _INTL("Team 0 (Slot B)")
  MB_TEAM_1_SLOT_0 = _INTL("Team 1 (Slot A)")
  MB_TEAM_1_SLOT_1 = _INTL("Team 1 (Slot B)")
  # Shown when the chosen lobby is already full.
  MB_LOBBY_FULL_MESSAGE = _INTL("That lobby is already full.")
  # Shown when the lobby wait times out.
  MB_LOBBY_TIMEOUT_MESSAGE = _INTL("The lobby timed out.")
  # Shown while waiting for all players to ready up.
  MB_READY_WAIT_MESSAGE = _INTL("Waiting for all players to ready up...")
  # Shown while waiting for all players to select their Pokémon.
  MB_SELECTION_WAIT_MESSAGE = _INTL("Waiting for all players to select Pokémon...")
  # Shown when auto-reassigned to a different slot. {1} is the new slot label.
  MB_SLOT_CONFLICT_MESSAGE = _INTL("Slot taken — moved to {1}.")
  # Shown when a player disconnects mid-battle. {1} is their name.
  MB_DISCONNECT_BATTLE_MESSAGE = _INTL("{1} has disconnected. The battle has ended.")
  # Shown to indicate that you must already be connected to use Multi Battle.
  MB_NOT_CONNECTED_MESSAGE = _INTL("You must be connected to a server to use Multi Battle.")
  # Prompt asking the player to confirm they are ready.
  MB_READY_CONFIRM_MESSAGE = _INTL("Ready to battle?")
  # Shown when a player has no eligible Pokémon for the multibattle.
  MB_NO_ELIGIBLE_POKEMON = _INTL("You don't have enough able Pokémon to participate.")

  # ===========
  # Matchmaking
  # ===========
  # Shown when trying to use matchmaking while not connected.
  MM_NOT_CONNECTED_MESSAGE = _INTL("You must be connected to a server to use matchmaking.")
  # Shown while searching for a battle matchmaking opponent.
  MM_QUEUE_WAIT_MESSAGE = _INTL("Searching for an opponent...")
  # Shown while searching for a trade matchmaking partner.
  MM_TRADE_QUEUE_WAIT_MESSAGE = _INTL("Searching for a trade partner...")
  # Shown when the matchmaking queue times out without finding a match.
  MM_QUEUE_TIMEOUT_MESSAGE = _INTL("No match was found in time.")
  # Shown when the player cancels matchmaking manually.
  MM_QUEUE_CANCELLED_MESSAGE = _INTL("Left the matchmaking queue.")
  # Shown once a match is found and mutually confirmed. {1} is the opponent/partner's name.
  MM_MATCH_FOUND_MESSAGE = _INTL("Match found with {1}!")

  # ===========
  # Chat
  # ===========
  # Prompt shown in the text-entry box when composing a chat message.
  CHAT_INPUT_PROMPT = _INTL("Enter chat message:")

  # ===========
  # GTS
  # ===========
  # Shown when trying to use the GTS while not connected.
  GTS_NOT_CONNECTED_MESSAGE = _INTL("You must be connected to a server to use the GTS.")
  # Shown when the GTS is disabled, or its listings file failed to load
  # server-side (so all GTS operations are being refused).
  GTS_UNAVAILABLE_MESSAGE = _INTL("The GTS is currently unavailable.")
  # Title/prompt shown for the main GTS menu.
  GTS_MENU_TITLE = _INTL("Welcome to the GTS! What would you like to do?")
  # Main GTS menu option labels.
  GTS_MENU_BROWSE = _INTL("Browse Listings")
  GTS_MENU_LIST_POKEMON = _INTL("List a Pokémon")
  GTS_MENU_LIST_ITEM = _INTL("List an Item")
  GTS_MENU_MY_LISTINGS = _INTL("My Listings & Collect Payment")
  # Shown above the browse list.
  GTS_BROWSE_TITLE = _INTL("Select a listing to view, or Cancel to go back:")
  # Shown when there are no active listings to browse.
  GTS_BROWSE_EMPTY_MESSAGE = _INTL("There are no active GTS listings right now.")
  # Shown for a single listing's details, alongside the View Summary/
  # Claim-or-Take-Back/Back choice menu. {1} is the summary, {2} is the
  # seller's name, {3} is the price.
  GTS_LISTING_DETAILS_MESSAGE = _INTL("{1}\\nSeller: {2}\\nPrice: ${3}", "{1}", "{2}", "{3}")
  # Listing-details menu option labels.
  GTS_MENU_VIEW_SUMMARY = _INTL("View Pokémon Summary")
  GTS_MENU_TAKE_BACK = _INTL("Take Back")
  GTS_MENU_CLAIM = _INTL("Claim")
  # Shown to confirm claiming someone else's listing. {1} is the summary,
  # {2} is the price.
  GTS_CLAIM_CONFIRM_MESSAGE = _INTL("Claim {1} for ${2}?", "{1}", "{2}")
  # Shown when choosing which Pokémon to list.
  GTS_CHOOSE_POKEMON_MESSAGE = _INTL("Choose a Pokémon to list on the GTS.")
  # Shown when the player has no listable Pokémon (would empty their party).
  GTS_NO_LISTABLE_POKEMON_MESSAGE = _INTL("You don't have another able Pokémon to leave in your party.")
  # Shown when choosing which item to list.
  GTS_CHOOSE_ITEM_MESSAGE = _INTL("Choose an item to list on the GTS.")
  # Shown when the player has no listable items.
  GTS_NO_LISTABLE_ITEMS_MESSAGE = _INTL("You don't have any items to list.")
  # Shown when choosing how many of an item to list. {1} is the item's name.
  GTS_ITEM_QUANTITY_MESSAGE = _INTL("How many {1} would you like to list?")
  # Shown when choosing a price for a new listing.
  GTS_PRICE_MESSAGE = _INTL("How much should this listing cost?")
  # Shown to confirm a new listing before it's sent to the server. {1} is
  # the summary, {2} is the price.
  GTS_CONFIRM_LISTING_MESSAGE = _INTL("List {1} for ${2}?", "{1}", "{2}")
  # Shown when a listing is created successfully.
  GTS_CREATE_SUCCESS_MESSAGE = _INTL("Your listing was posted to the GTS.")
  # Shown when a listing fails to be created. {1} is the server's reason.
  GTS_CREATE_FAILURE_MESSAGE = _INTL("Your listing could not be posted: {1}")
  # Shown when the player has reached the maximum number of active listings.
  GTS_MAX_LISTINGS_MESSAGE = _INTL("You have reached the maximum number of active GTS listings.")
  # Shown when a listing is claimed successfully.
  GTS_CLAIM_SUCCESS_MESSAGE = _INTL("You claimed the listing!")
  # Shown when a claim fails because someone else claimed it first.
  GTS_CLAIM_UNAVAILABLE_MESSAGE = _INTL("That listing is no longer available -- someone else may have already claimed it.")
  # Shown when a claim fails for another reason. {1} is the server's reason.
  GTS_CLAIM_FAILURE_MESSAGE = _INTL("That listing could not be claimed: {1}")
  # Shown when the player can't afford the listing they're trying to claim.
  GTS_CANT_AFFORD_MESSAGE = _INTL("You don't have enough money for that.")
  # Shown when the player's Bag has no room for a claimed item.
  GTS_BAG_FULL_MESSAGE = _INTL("Your Bag doesn't have room for that.")
  # Shown when the player's party is full and can't receive a claimed/
  # cancelled Pokémon.
  GTS_PARTY_FULL_MESSAGE = _INTL("Your party is full.")
  # Title shown above the "My Listings" browser.
  GTS_MY_LISTINGS_TITLE = _INTL("Select one of your listings:")
  # Shown when the player has no listings of their own.
  GTS_MY_LISTINGS_EMPTY_MESSAGE = _INTL("You don't have any GTS listings.")
  # Status labels shown next to each of the player's own listings.
  GTS_STATUS_ACTIVE = _INTL("Active")
  GTS_STATUS_SOLD = _INTL("Sold -- payment ready to collect")
  GTS_STATUS_COLLECTED = _INTL("Collected")
  # Shown for one of the player's own active listings, asking to cancel it.
  GTS_CANCEL_CONFIRM_MESSAGE = _INTL("Cancel this listing and take {1} back?", "{1}")
  # Shown for one of the player's own sold listings, asking to collect payment.
  GTS_COLLECT_CONFIRM_MESSAGE = _INTL("Collect ${1} in payment for this listing?", "{1}")
  # Shown when payment is collected successfully. {1} is the amount.
  GTS_COLLECT_SUCCESS_MESSAGE = _INTL("You collected ${1}.", "{1}")
  # Shown when collecting payment fails. {1} is the server's reason.
  GTS_COLLECT_FAILURE_MESSAGE = _INTL("Payment could not be collected: {1}")
  # Shown when a listing is cancelled successfully.
  GTS_CANCEL_SUCCESS_MESSAGE = _INTL("Your listing was cancelled and returned to you.")
  # Shown when cancelling a listing fails. {1} is the server's reason.
  GTS_CANCEL_FAILURE_MESSAGE = _INTL("That listing could not be cancelled: {1}")
end
