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
  end
end
