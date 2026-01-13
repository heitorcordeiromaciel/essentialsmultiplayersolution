module VMS
  require 'socket'
  require "zlib"
  require_relative 'Config'
  require_relative 'Cluster'
  require_relative 'Player'

  class Server
    attr_reader :socket
    attr_accessor :clusters

    def initialize
      if Config.use_tcp
        @socket = TCPServer.new(Config.host, Config.port)
      else
        @socket = UDPSocket.new
        @socket.bind(Config.host, Config.port)
      end
      @clients = {}
      @clusters = {}
      begin
        run
      rescue Interrupt
        log("Server has been stopped by the user.")
      rescue => e
        log("Server stopped with error: #{e}", true)
      end
    end

    def run
      log("Server started on #{Config.host}:#{Config.port}.")
      # Tick rate
      current_time = Time.now
      elapsed_time = 1.0
      last_tick = current_time
      tick_interval = Config.tick_rate > 0 ? 1.0 / Config.tick_rate.to_f : 0.0
      loop do
        # Skip to next tick if needed
        if Config.tick_rate > 0 && elapsed_time < tick_interval
          current_time = Time.now
          elapsed_time = current_time - last_tick
          last_tick = current_time
        end
        # Update clusters
        threads = []
        if elapsed_time >= tick_interval
          @clusters.each_value do |cluster|
            if Config.threading
              threads << Thread.new { cluster.update_players }
            else
              cluster.update_players
            end
          end
        end
        begin
          # Receive data from clients
          if Config.use_tcp
            @clients.each_value do |client|
              data = client.recv_nonblock(65536, exception: false)
              next if data == :wait_readable || data == :wait_writable || data.nil?
              data = Marshal.load(Zlib::Inflate.inflate(data))
              # Handle data
              case data[0]
              when "connect"
                connect(client.addr[3], client.addr[1], data[1])
              when "disconnect"
                disconnect(client.addr[3], client.addr[1], data[1])
              when "update"
                update(client.addr[3], client.addr[1], data[1])
              end
            end
            # Accept new clients
            client = @socket.accept_nonblock(exception: false)
            next if client == :wait_readable || client == :wait_writable || client.nil?
            @clients[client.addr] = client
          else
            data, address, port = @socket.recvfrom_nonblock(65536, exception: false)
            next if data == :wait_readable || data == :wait_writable || data.nil? || address.nil?
            port = address[1]
            address = address[3]
            data = Marshal.load(Zlib::Inflate.inflate(data))
            # Handle data
            case data[0]
            when "connect"
              connect(address, port, data[1])
            when "disconnect"
              disconnect(address, port, data[1])
            when "update"
              update(address, port, data[1])
            when "list_clusters"
              list_clusters(address, port)
            end
          end
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        rescue => e
          log("#{e}", true)
        end
        threads.each(&:join) if Config.threading
      end
    end

    def connect(address, port, data)
      if Config.check_game_and_version
        if data[:game_name] != Config.game_name && data[:game_name] != "" && !data[:game_name].nil?
          log("#{get_player_name(data)} tried to connect to cluster #{data[:cluster_id]}, but they were using the wrong game (#{data[:game_name]}).")
          send(:disconnect_wrong_game, address, port)
          return
        elsif data[:game_version] != Config.game_version && data[:game_version] != "" && !data[:game_version].nil?
          log("#{get_player_name(data)} tried to connect to cluster #{data[:cluster_id]}, but they were using the wrong version (#{data[:game_version]}).")
          send(:disconnect_wrong_version, address, port)
          return
        end
      end
      if cluster_exists(data[:cluster_id])
        if @clusters[data[:cluster_id]].player_count < Config.max_players
          @clusters[data[:cluster_id]].add_player(Player.new(data[:id], address, port))
          update(address, port, data)
          log("#{get_player_name(data)} connected to cluster #{data[:cluster_id]}.")
        else
          log("#{get_player_name(data)} tried to connect to cluster #{data[:cluster_id]}, but it was full.")
          send(:disconnect_full, address, port)
        end
      else
        @clusters[data[:cluster_id]] = Cluster.new(data[:cluster_id] || @clusters.length, self)
        @clusters[data[:cluster_id]].add_player(Player.new(data[:id], address, port))
        update(address, port, data)
        log("#{get_player_name(data)} connected to newly created cluster #{data[:cluster_id]}.")
      end
    end

    def disconnect(address, port, data)
      if cluster_exists(data[:cluster_id])
        if @clusters[data[:cluster_id]].has_player(address, port)
          @clusters[data[:cluster_id]].remove_player(data[:id])
          log("#{get_player_name(data)} disconnected from cluster #{data[:cluster_id]}.")
        else
          log("#{get_player_name(data)} tried to disconnect from cluster #{data[:cluster_id]}, but they weren't connected.")
        end
      else
        log("#{get_player_name(data)} tried to disconnect from cluster #{data[:cluster_id]}, but it didn't exist.")
      end
      send(:disconnect, address, port)
    end

    def update(address, port, data)
      if cluster_exists(data[:cluster_id])
        cluster = @clusters[data[:cluster_id]]
        if cluster.has_player(address, port)
          if !data[:online_variables].nil?
            data[:online_variables].each do |key, value|
              next if cluster.online_variables[key] == value
              log("#{get_player_name(data)} updated online variable #{key} to #{value}.")
              cluster.online_variables[key] = value
            end
          end
          cluster.players[data[:id]].update(data)
        else
          log("#{get_player_name(data)} tried to update cluster #{data[:cluster_id]}, but they weren't connected.", true)
          connect(address, port, data)
        end
      else
        log("#{get_player_name(data)} tried to update cluster #{data[:cluster_id]}, but it didn't exist.")
        connect(address, port, data)
      end
    end

    def send(data, address, port)
      if Config.use_tcp
        @clients.each_value do |client|
          begin
            client.send(Zlib::Deflate.deflate(Marshal.dump(data), Zlib::BEST_SPEED), 0)
          rescue
            log("Client #{client.addr} disconnected.")
            @clients.delete(client.addr)
          end
        end
      else
        @socket.send(Zlib::Deflate.deflate(Marshal.dump(data), Zlib::BEST_SPEED), 0, address, port)
      end
    end

    def log(message="", warning=false)
      puts "\e[34m[\e[36m#{Time.now.strftime("%d/%m/%Y - %H:%M:%S")}\e[34m] #{warning ? "\e[31mWARNING: " : "\e[1m\e[36m"}#{message}\e[0m" if Config.log
    end

    def get_player_name(data)
      return "Player #{data[:name]} (#{data[:id]})"
    end

    def cluster_exists(id)
      @clusters.each_value do |cluster|
        if cluster.id == id
          return true
        end
      end
      return false
    end

    def remove_cluster(id)
      @clusters.delete(id)
    end

    def list_clusters(address, port)
      cluster_list = []
      @clusters.each_value do |cluster|
        cluster_list.push({
          id: cluster.id,
          player_count: cluster.player_count
        })
      end
      send([:cluster_list, cluster_list], address, port)
      log("Sent cluster list to #{address}:#{port}")
    end
  end

  Server.new
end