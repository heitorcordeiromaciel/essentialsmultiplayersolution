module VMS
  class Config
    CONFIG_PATH = File.join(__dir__, "config.ini")

    def self.host
      get_line("host").chomp
    end

    def self.port
      get_line("port").chomp.to_i
    end

    def self.check_game_and_version
      get_line("check_game_and_version").chomp == "true"
    end

    def self.game_name
      get_line("game_name").chomp
    end

    def self.game_version
      get_line("game_version").chomp
    end

    def self.max_players
      get_line("max_players").chomp.to_i
    end

    def self.log
      get_line("log").chomp == "true"
    end

    def self.heartbeat_timeout
      get_line("heartbeat_timeout").chomp.to_i
    end

    def self.use_tcp
      get_line("use_tcp").chomp == "true"
    end

    def self.threading
      get_line("threading").chomp == "true"
    end

    def self.tick_rate
      get_line("tick_rate").chomp.to_i
    end
    
    def self.get_line(line)
      File.open(CONFIG_PATH, "r") do |file|
        file.each_line do |l|
          if l.split(" = ")[0] == line
            return l.split(" = ")[1]
          end
        end
      end
    end
  end
end
