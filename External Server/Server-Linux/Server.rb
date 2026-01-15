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
      
      tick_interval = Config.tick_rate > 0 ? 1.0 / Config.tick_rate.to_f : 0.0
      last_tick = Time.now

      loop do
        # Calculate time to wait for next tick
        wait_time = nil
        if tick_interval > 0
          now = Time.now
          elapsed = now - last_tick
          wait_time = [tick_interval - elapsed, 0].max
        end

        # IO Multiplexing: Wait for data or next tick
        readable, = IO.select([@socket] + @clients.values, nil, nil, wait_time)

        if readable
          readable.each do |s|
            if s == @socket && Config.use_tcp
              # New TCP connection
              begin
                client = @socket.accept_nonblock
                @clients[client.addr] = client
                log("New client connected: #{client.addr}")
              rescue IO::WaitReadable, IO::WaitWritable
              end
            else
              # Existing client or UDP socket
              begin
                if Config.use_tcp
                  data = s.respond_to?(:recv_nonblock) ? s.recv_nonblock(65536) : s.recv(65536)
                  handle_packet(data, s.addr[3], s.addr[1], s)
                else
                  data, address = @socket.respond_to?(:recvfrom_nonblock) ? @socket.recvfrom_nonblock(65536) : @socket.recvfrom(65536)
                  handle_packet(data, address[3], address[1])
                end
              rescue EOFError
                log("Client disconnected: #{s.addr}")
                @clients.delete(s.addr)
                s.close
              rescue IO::WaitReadable, IO::WaitWritable
              rescue => e
                log("Error receiving data: #{e}", true)
              end
            end
          end
        end

        # Tick processing
        if tick_interval == 0 || (Time.now - last_tick) >= tick_interval
          @clusters.each_value(&:update_players)
          last_tick = Time.now
        end
      end
    end

    def handle_packet(data, address, port, socket = nil)
      return if data.nil? || data.empty?
      begin
        data = Marshal.load(Zlib::Inflate.inflate(data))
        return unless data.is_a?(Array)
        return unless data.length >= 2 || (data.length >= 1 && data[0] == "list_clusters")
        
        case data[0]
        when "connect"      then connect(address, port, sanitize_data(data[1]), socket)
        when "disconnect"   then disconnect(address, port, sanitize_data(data[1]), socket)
        when "update"       then update(address, port, sanitize_data(data[1]), socket)
        when "list_clusters" then list_clusters(address, port, socket)
        end
      rescue => e
        log("Packet error from #{address}:#{port} - #{e}", true)
      end
    end

    def sanitize_data(data)
      return {} unless data.is_a?(Hash)
      sanitized = {}
      # Define expected types for critical fields using integer keys
      expected = {
        PACKET_KEYS[:id] => Integer,
        PACKET_KEYS[:cluster_id] => Integer,
        PACKET_KEYS[:name] => String,
        PACKET_KEYS[:map_id] => Integer,
        PACKET_KEYS[:x] => Integer,
        PACKET_KEYS[:y] => Integer,
        PACKET_KEYS[:real_x] => Numeric,
        PACKET_KEYS[:real_y] => Numeric,
        PACKET_KEYS[:direction] => Integer,
        PACKET_KEYS[:pattern] => Integer,
        PACKET_KEYS[:graphic] => String,
        PACKET_KEYS[:heartbeat] => Time
      }
      
      data.each do |k, v|
        # Convert key to integer if it's a string/symbol that matches our mapping
        key = k
        if k.is_a?(String) || k.is_a?(Symbol)
          key = PACKET_KEYS[k.to_sym] || k
        end

        if expected.key?(key)
          # Only keep if type matches (or can be converted)
          if v.is_a?(expected[key])
            sanitized[key] = v
          elsif expected[key] == Integer && v.respond_to?(:to_i)
            sanitized[key] = v.to_i
          elsif expected[key] == Numeric && v.respond_to?(:to_f)
            sanitized[key] = v.to_f
          elsif expected[key] == String
            sanitized[key] = v.to_s
          end
        else
          # Pass through other fields (like party, state)
          sanitized[key] = v
        end
      end
      sanitized
    end

    def connect(address, port, data, socket = nil)
      # Removed check_game_and_version to match Integrated Server behavior
      
      player = Player.new(data[PACKET_KEYS[:id]], address, port)
      player.socket = socket
      
      cluster_id = data[PACKET_KEYS[:cluster_id]] || 0
      if cluster_exists(cluster_id)
        cluster = @clusters.values.find { |c| c.id == cluster_id }
        if cluster.player_count < Config.max_players
          cluster.add_player(player)
          player.update(data)
          log("#{get_player_name(data)} connected to cluster #{cluster_id}.")
        else
          log("#{get_player_name(data)} tried to connect to cluster #{cluster_id}, but it was full.")
          send(:disconnect_full, address, port, socket)
        end
      else
        cluster = Cluster.new(cluster_id, self)
        @clusters[cluster_id] = cluster
        cluster.add_player(player)
        player.update(data)
        log("#{get_player_name(data)} connected to newly created cluster #{cluster_id}.")
      end
    end

    def disconnect(address, port, data, socket = nil)
      cluster_id = data[PACKET_KEYS[:cluster_id]]
      if cluster_exists(cluster_id)
        cluster = @clusters.values.find { |c| c.id == cluster_id }
        if cluster.has_player(address, port)
          cluster.remove_player(data[PACKET_KEYS[:id]])
          log("#{get_player_name(data)} disconnected from cluster #{cluster_id}.")
        else
          log("#{get_player_name(data)} tried to disconnect from cluster #{cluster_id}, but they weren't connected.")
        end
      else
        log("#{get_player_name(data)} tried to disconnect from cluster #{cluster_id}, but it didn't exist.")
      end
      send(:disconnect, address, port, socket)
    end

    def update(address, port, data, socket = nil)
      cluster_id = data[PACKET_KEYS[:cluster_id]]
      if cluster_exists(cluster_id)
        cluster = @clusters.values.find { |c| c.id == cluster_id }
        if cluster.has_player(address, port)
          ov_key = PACKET_KEYS[:online_variables]
          if !data[ov_key].nil?
            data[ov_key].each do |key, value|
              next if cluster.online_variables[key] == value
              log("#{get_player_name(data)} updated online variable #{key} to #{value}.")
              cluster.online_variables[key] = value
              cluster.variables_dirty = true
            end
          end
          cluster.players[data[PACKET_KEYS[:id]]].update(data)
          cluster.players[data[PACKET_KEYS[:id]]].socket = socket if socket
        else
          log("#{get_player_name(data)} tried to update cluster #{cluster_id}, but they weren't connected.", true)
        end
      else
        log("#{get_player_name(data)} tried to update cluster #{cluster_id}, but it didn't exist.")
      end
    end

    def send(data, address, port, socket = nil)
      binary = Zlib::Deflate.deflate(Marshal.dump(data), Zlib::BEST_SPEED)
      send_binary(binary, address, port, socket)
    end

    def send_binary(binary, address, port, socket = nil)
      if Config.use_tcp
        target = socket || @clients.values.find { |c| c.addr[3] == address && c.addr[1] == port }
        if target
          begin
            # Add length prefix for TCP (4 bytes, network byte order)
            target.write([binary.bytesize].pack("N") + binary)
          rescue => e
            log("TCP Send Error to #{address}:#{port} - #{e}")
            @clients.delete(target.addr)
            # Force disconnect in all clusters to prevent zombies
            @clusters.each_value { |c| c.remove_player_by_address(address, port) }
          end
        end
      else
        begin
          @socket.send(binary, 0, address, port)
        rescue => e
          log("UDP Send Error to #{address}:#{port} - #{e}")
        end
      end
    end

    def log(message="", warning=false)
      puts "\e[34m[\e[36m#{Time.now.strftime("%d/%m/%Y - %H:%M:%S")}\e[34m] #{warning ? "\e[31mWARNING: " : "\e[1m\e[36m"}#{message}\e[0m" if Config.log
    end

    def get_player_name(data)
      return data[PACKET_KEYS[:name]] || "Unknown Player"
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

    def list_clusters(address, port, socket = nil)
      cluster_list = []
      @clusters.each_value do |cluster|
        cluster_list.push({
          id: cluster.id,
          player_count: cluster.player_count
        })
      end
      send([:cluster_list, cluster_list], address, port, socket)
      log("Sent cluster list to #{address}:#{port}")
    end
  end

  Server.new
end