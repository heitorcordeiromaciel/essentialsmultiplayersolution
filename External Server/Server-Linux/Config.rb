require "zlib"

module VMS
  class Config
    CONFIG_PATH = File.join(__dir__, "config.ini")
    @cache = {}

    def self.load
      return unless @cache.empty?
      File.open(CONFIG_PATH, "r") do |file|
        file.each_line do |l|
          next if l.start_with?("#") || l.strip.empty?
          parts = l.split(" = ")
          next if parts.length < 2
          @cache[parts[0].strip] = parts[1].strip
        end
      end
    end

    def self.host
      load
      @cache["host"]
    end

    def self.port
      load
      @cache["port"].to_i
    end

    def self.check_game_and_version
      load
      @cache["check_game_and_version"] == "true"
    end

    def self.game_name
      load
      @cache["game_name"]
    end

    def self.game_version
      load
      @cache["game_version"]
    end

    def self.max_players
      load
      @cache["max_players"].to_i
    end

    def self.max_clusters
      load
      (@cache["max_clusters"] || 0).to_i
    end

    def self.log
      load
      @cache["log"] == "true"
    end

    def self.heartbeat_timeout
      load
      @cache["heartbeat_timeout"].to_i
    end

    def self.use_tcp
      load
      @cache["use_tcp"] == "true"
    end

    def self.threading
      load
      @cache["threading"] == "true"
    end

    def self.tick_rate
      load
      @cache["tick_rate"].to_i
    end

    def self.compression_level
      load
      case (@cache["compression_level"] || "speed").downcase
      when "best" then Zlib::BEST_COMPRESSION
      when "default" then Zlib::DEFAULT_COMPRESSION
      when "none" then Zlib::NO_COMPRESSION
      else Zlib::BEST_SPEED
      end
    end

    def self.gts_max_listings_per_player
      load
      (@cache["gts_max_listings_per_player"] || 5).to_i
    end

    def self.gts_max_listings_total
      load
      (@cache["gts_max_listings_total"] || 200).to_i
    end

    def self.gts_encryption_key
      load
      key = @cache["gts_encryption_key"]
      if key.nil? || key.strip.empty?
        unless @generated_gts_key
          require "securerandom"
          @generated_gts_key = SecureRandom.hex(32)
          puts "\e[31mWARNING: gts_encryption_key is not set in config.ini -- generated a random key for this session. GTS listings will become unreadable after a server restart until you set gts_encryption_key explicitly.\e[0m"
        end
        @generated_gts_key
      else
        key
      end
    end
  end
end
