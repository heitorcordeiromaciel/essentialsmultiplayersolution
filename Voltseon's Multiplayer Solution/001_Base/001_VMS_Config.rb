require "zlib"

module VMS
  # ===========
  # Debug
  # ===========

  # If true, the menu will show "Local Play" and "Online Play" options.
  # If false, only integrated server (local play) options will be available.
  USE_EXTERNAL_SERVER = false

  # External server connection settings (used when "Online Play" is selected)
  EXTERNALHOST = "127.0.0.1"
  EXTERNALPORT = 12345

  # Default port for hosting, integrated server is always hosted on 0.0.0.0:PORT.
  PORT = 25565

  # The current target IP for connecting. Can be changed at runtime.
  class << self
    attr_accessor :target_host
  end

  # Whether or not to log messages to the console.
  LOG_TO_CONSOLE = true
  # Whether or not to show yourself from the server's perspective. This is useful for testing.
  SHOW_SELF = false

  # ===========
  # Server
  # ===========
  # Whether or not to use TCP instead of UDP. TCP is more reliable, but UDP is faster.
  USE_TCP = false
  # The maximum number of players allowed in the integrated server.
  MAX_PLAYERS = 4
  # Zlib compression level for the integrated server's per-tick broadcast.
  # BEST_SPEED keeps the hot path cheap; use BEST_COMPRESSION to trade CPU for smaller packets.
  TICK_COMPRESSION_LEVEL = Zlib::BEST_SPEED

  # ===========
  # Connection
  # ===========
  # How many times per second to send packets. (can't be higher than the server's tick rate) (set to 0 to disable)
  TICK_RATE = 30
  # Whether or not to handle more packets. If this is set to false you will only receive the latest packet, being faster but more snappy.
  HANDLE_MORE_PACKETS = true
  # This is the delay where packet recency bias will be offset. Meaning if HANDLE_MORE_PACKETS is false, you will receive the latest packet that was sent within this delay. (in seconds)
  ADDED_DELAY = 0.09
  # The timeout in seconds. If the server does not respond within this time, the client will disconnect.
  TIMEOUT_SECONDS = 30
  # Whether or not to sync the seed with the server. This means that all players will have the same random numbers.
  HEARTBEAT_TIMEOUT = 30
  SEED_SYNC = false
  # Whether the Integrated Server should reject connecting players whose
  # game name/version (System.game_title/Settings::GAME_VERSION) don't
  # match the host's own. Off by default; the External Server has its own
  # equivalent config.ini setting.
  CHECK_GAME_AND_VERSION = false

  # ===========
  # Events
  # ===========
  # Whether other players can be walked through.
  THROUGH = false
  # What happens when interacting with another player. (set to 'proc { }' to disable) (yields: player_id #<Integer>, player #<VMS::Player>, event #<Game_Event>)
  INTERACTION_PROC = proc { |player_id, player, event| VMS.interact_with_player(player_id) }
  # How long to wait for another player to check for interactions. (in seconds) (set to 0 to instead wait until confirmed or denied)
  INTERACTION_WAIT = 30
  # IDs of animations that should be synced. (set to [] to sync all animations, set to [0] to sync no animations)
  SYNC_ANIMATIONS = [2, 3, 4]
  # How far away a player can be from the player before it is considered out of range. (in tiles) (out of range players will not be visible)
  CULL_DISTANCE = 10
  # Whether or not players their movement should be smoothed. This will make positions less accurate, but will make movement look smoother.
  SMOOTH_MOVEMENT = true
  # How accurate the movement should be. (closer to 0 means smoother, closer to 1 means more accurate) (only used if SMOOTH_MOVEMENT is true)
  SMOOTH_MOVEMENT_ACCURACY = 0.5
  # How far away a player has to move before they are teleported to the server's position. (in pixels) (only used if SMOOTH_MOVEMENT is true)
  SNAP_DISTANCE = 192

  # ===========
  # Menu
  # ===========
  # Whether or not VMS is accessible from the pause menu.
  ACCESSIBLE_FROM_PAUSE_MENU = true
  # Whether or not VMS is accessible. (set to 'proc { next true }' to always be accessible) (only used if ACCESSIBLE_FROM_PAUSE_MENU is true)
  ACCESSIBLE_PROC = proc { next true }
  # The name of the VMS option in the pause menu. (only used if ACCESSIBLE_FROM_PAUSE_MENU is true)
  MENU_NAME = "Link Play"
  # Whether or not to show the cluster ID in the pause menu.
  SHOW_CLUSTER_ID_IN_PAUSE_MENU = true
  
  # ===========
  # Other
  # ===========
  # Whether or not to show the ping in the window title.
  SHOW_PING = true
  # Whether or not to show other players on the region map.
  SHOW_PLAYERS_ON_REGION_MAP = true
  # Whether or not to show other players' name tags above their sprites.
  SHOW_PLAYER_NAMETAGS = true
  # Default values for encryption.
  ENCRYPTION_DEFAULTS = {
    "Pokemon" => [:BULBASAUR, 5],
    "Pokemon::Owner" => [0, "", 0, 0],
    "Pokemon::Move" => [:TACKLE],
    "Battle::Move" => [:TACKLE]
  }
  
  # ===========
  # Multi Battle
  # ===========
  # Maximum seconds to wait in a lobby for all 4 players to join before auto-cancelling.
  MB_LOBBY_TIMEOUT = 120
  # Maximum seconds to wait for all players to ready up once 4 slots are filled.
  MB_READY_TIMEOUT = 60
  # The name of the Multi Battle option in the Matchmaking pause menu.
  MB_MENU_NAME = "Multi Battle"

  # ===========
  # Matchmaking
  # ===========
  # Maximum seconds to wait in the matchmaking queue before auto-cancelling.
  MM_QUEUE_TIMEOUT = 120
  # Maximum seconds to wait for a tentative match to mutually confirm before
  # dropping it and returning to the queue
  MM_MATCH_CONFIRM_TIMEOUT = 5
  # The name of the Matchmaking option in the pause menu
  MM_MENU_NAME = "Matchmaking"
  # The name of the Battle Matchmaking option in the Matchmaking pause menu.
  MM_BATTLE_MENU_NAME = "Battle Matchmaking"
  # The name of the Trade Matchmaking option in the Matchmaking pause menu.
  MM_TRADE_MENU_NAME = "Trade Matchmaking"

  # ===========
  # Chat
  # ===========
  # Whether or not the chat system is enabled at all. Set to false to disable it entirely
  ENABLE_CHAT = true
  # Maximum number of characters allowed in a single chat message.
  # WARNING: Setting this to more than 15 will cause the message screen to ovrflow
  # this is merely a visual issue and will not break anything, but will cause
  # overly long messages to be unreadable while writing them
  CHAT_MAX_MESSAGE_LENGTH = 15
  # How many messages to retain in the chat log (older ones are dropped).
  CHAT_LOG_MAX_MESSAGES = 50
  # How many of the most recent lines the on-screen overlay shows at once.
  CHAT_VISIBLE_LINES = 6
  # Fixed pixel width of the chat overlay box.
  CHAT_BOX_WIDTH = 260
  # Opacity (0-255) of the chat overlay's background box.
  CHAT_BOX_OPACITY = 160
  # Corner radius (in pixels) of the chat overlay box.
  CHAT_BOX_RADIUS = 8
  # Width (in pixels) of the chat overlay box's outline. Set to 0 to disable.
  CHAT_BOX_OUTLINE_WIDTH = 2
  # Color of the chat overlay box's outline.
  CHAT_BOX_OUTLINE_COLOR = Color.new(255, 255, 255, 200)
  # The key that opens the chat message input box while on the map.
  # Falls back to Input::CTRL if not defined.
  CHAT_OPEN_KEY = begin
    Input::CTRL
  rescue NameError
    Input::CTRL
  end
  # The name of the Toggle Chat option in the pause menu
  CHAT_TOGGLE_MENU_NAME = "Toggle Chat"
  # Seconds of no new messages before the chat overlay starts fading out.
  # Set to 0 to disable fading
  CHAT_FADE_DELAY = 10
  # Seconds the fade-out itself takes once it starts.
  CHAT_FADE_DURATION = 1.0

  # ===========
  # GTS
  # ===========
  # Whether or not the GTS is enabled at all. Set to false to disable it entirely
  ENABLE_GTS = true
  # Maximum number of simultaneous active GTS listings a single player may
  # have (0 = unlimited). Enforced server-side.
  GTS_MAX_LISTINGS_PER_PLAYER = 5
  # Maximum number of simultaneous active GTS listings across all players
  # (0 = unlimited). Enforced server-side.
  GTS_MAX_LISTINGS_TOTAL = 200
  # Optional money cost to create a GTS listing, charged client-side before
  # the create request is sent and refunded if the server rejects it. Set to 0 to disable
  GTS_LISTING_FEE = 0
  # Server-only key used to encrypt the Integrated Server's GTS listings file.
  GTS_ENCRYPTION_KEY = "change-me-to-a-random-secret-string"

  # ===========
  # Compatibility
  # ===========
  # Enable Following Pokemon support? Requires Following Pokemon EX
  # WARNING: This feature might add significant lag in servers with many players,
  # not recommended to be used with more than 4 simultaneous players.
  ENABLE_FOLLOWER_SYNC = false
  # Enable Overworld Encounters support? Requires Voltseon's Overworld Encounters
  # WARNING: This feature might add significant lag depending on VOE's configs
  # WARNING²: This feature is currently unstable, and while it wont crash your game, it can and will:
  # Desync, Stop working at all, flicker, reset spawns (i do not take responsibility for any shinies lost)
  # Cool feature tho :P
  ENABLE_OVERWORLD_ENCOUNTER_SYNC = false
  # Enable Tournament Selection support for single/double PvP battles?
  # Requires the "Tournament Selection" plugin.
  ENABLE_TOURNAMENT_SELECTION = false

  # ===========
  # Methods
  # ===========
  # Mapping for integer-keyed serialization to reduce bandwidth
  PACKET_KEYS = {
    id: 1, heartbeat: 2, name: 3, map_id: 4, x: 5, y: 6, real_x: 7, real_y: 8,
    trainer_type: 9, direction: 10, pattern: 11, graphic: 12, party: 13,
    animation: 14, offset_x: 15, offset_y: 16, opacity: 17, stop_animation: 18,
    rf_event: 19, jump_offset: 20, jumping_on_spot: 21, surfing: 22, diving: 23,
    surf_base_coords: 24, state: 25, busy: 26, cluster_id: 27,
    online_variables: 28, game_name: 29, game_version: 30, follower: 31,
    encounters: 32, encounter_claim: 33
  }
  REVERSE_KEYS = PACKET_KEYS.invert

  # Usage: VMS.log("message", true) (logs a message to the console, with optional warning flag)
  def self.log(message="", warning=false)
    return unless LOG_TO_CONSOLE
    echoln Console.markup_style("VMS: " + message, text: warning ? :red : :blue)
  end
  # Usage: VMS.message("message", ["choice 1", "choice 2", "choice 3"], 0) (displays a message, with optional choices and default choice)
  def self.message(message="", choices=nil, default_choice=0)
    return if message.empty?
    return unless VMS::SHOW_PLAYER_MESSAGES
    if choices.is_a?(Array)
      max_choice_length = 30
      choices = choices.map do |c|
        (c.is_a?(String) && c.length > max_choice_length) ? (c[0, max_choice_length - 3] + "...") : c
      end
    end
    return pbMessage(message, choices, default_choice)
  end
end