module VMS
  module IntegratedServer
    class << self
      attr_accessor :running
      attr_accessor :thread
    end

    def self.start
      return if @running
      @running = true
      @thread = Thread.new do
        begin
          server = Server.new
          server.start
        rescue => e
          VMS.log("Integrated Server Error: #{e.message}", true)
          @running = false
        end
      end
      VMS.log("Integrated Server started on port 25565")
    end

    def self.stop
      @running = false
      @thread&.kill
      @thread = nil
      VMS.log("Integrated Server stopped")
    end

    class Server
      def initialize
        @port = 25565
        @host = '0.0.0.0'
        @clusters = {}
        @clients = {}
        @tick_rate = 30
        @heartbeat_timeout = 30
        @use_tcp = false # Defaulting to UDP for co-op speed
        
        if @use_tcp
          @socket = TCPServer.new(@host, @port)
        else
          @socket = UDPSocket.new
          @socket.bind(@host, @port)
        end
      end

      def start
        last_tick = Time.now
        tick_interval = 1.0 / @tick_rate

        while VMS::IntegratedServer.running
          # IO Selection
          sockets = [@socket] + @clients.values
          ready = IO.select(sockets, nil, nil, 0.1)

          if ready
            ready[0].each do |s|
              if s == @socket && @use_tcp
                begin
                  client = @socket.accept_nonblock
                  @clients[client.addr] = client
                rescue IO::WaitReadable, IO::WaitWritable
                end
              else
                begin
                  if @use_tcp
                    data = s.recv_nonblock(65536)
                    handle_packet(data, s.addr[3], s.addr[1], s)
                  else
                    data, address = @socket.recvfrom_nonblock(65536)
                    handle_packet(data, address[3], address[1])
                  end
                rescue EOFError
                  @clients.delete(s.addr)
                  s.close
                rescue IO::WaitReadable, IO::WaitWritable
                rescue => e
                  VMS.log("Server Receive Error: #{e.message}", true)
                end
              end
            end
          end

          # Tick processing
          if (Time.now - last_tick) >= tick_interval
            @clusters.each_value(&:update_players)
            last_tick = Time.now
          end
        end
      ensure
        @socket.close if @socket
      end

      def handle_packet(data, address, port, socket = nil)
        return if data.nil? || data.empty?
        begin
          data = Marshal.load(Zlib::Inflate.inflate(data))
          return unless data.is_a?(Array) && data.length >= 2
          
          case data[0]
          when "connect"      then connect(address, port, sanitize_data(data[1]), socket)
          when "disconnect"   then disconnect(address, port, sanitize_data(data[1]), socket)
          when "update"       then update(address, port, sanitize_data(data[1]), socket)
          when "list_clusters" then list_clusters(address, port)
          end
        rescue => e
          VMS.log("Server Packet Error: #{e.message}", true)
        end
      end

      def sanitize_data(data)
        return {} unless data.is_a?(Hash)
        sanitized = {}
        expected = {
          VMS::PACKET_KEYS[:id] => Integer,
          VMS::PACKET_KEYS[:cluster_id] => Integer,
          VMS::PACKET_KEYS[:name] => String,
          VMS::PACKET_KEYS[:map_id] => Integer,
          VMS::PACKET_KEYS[:x] => Integer,
          VMS::PACKET_KEYS[:y] => Integer,
          VMS::PACKET_KEYS[:real_x] => Numeric,
          VMS::PACKET_KEYS[:real_y] => Numeric,
          VMS::PACKET_KEYS[:direction] => Integer,
          VMS::PACKET_KEYS[:pattern] => Integer,
          VMS::PACKET_KEYS[:graphic] => String,
          VMS::PACKET_KEYS[:heartbeat] => Time
        }
        
        data.each do |k, v|
          key = k
          if expected.key?(key)
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
            sanitized[key] = v
          end
        end
        sanitized
      end

      def connect(address, port, data, socket = nil)
        # Hardlock to Cluster 0
        cluster_id = 0
        cluster = @clusters[cluster_id]
        
        if cluster.nil?
          cluster = Cluster.new(cluster_id, self)
          @clusters[cluster_id] = cluster
        end
        
        # Check player limit
        max_players = VMS::Config.max_players rescue 4
        if cluster.player_count < max_players
          cluster.add_player(player = Player.new(data[VMS::PACKET_KEYS[:id]], address, port))
          player.socket = socket
          player.update(data)
        else
          VMS.log("Connection rejected: Cluster 0 is full", true)
          # Optionally send a 'full' packet if you have one defined
        end
      end

      def disconnect(address, port, data, socket = nil)
        cluster_id = data[VMS::PACKET_KEYS[:cluster_id]]
        cluster = @clusters[cluster_id]
        if cluster && cluster.has_player(address, port)
          cluster.remove_player(data[VMS::PACKET_KEYS[:id]])
        end
        send(:disconnect, address, port, socket)
      end

      def update(address, port, data, socket = nil)
        cluster_id = data[VMS::PACKET_KEYS[:cluster_id]]
        cluster = @clusters[cluster_id]
        if cluster && cluster.has_player(address, port)
          ov_key = VMS::PACKET_KEYS[:online_variables]
          if data[ov_key]
            data[ov_key].each do |key, value|
              next if cluster.online_variables[key] == value
              cluster.online_variables[key] = value
              cluster.variables_dirty = true
            end
          end
          cluster.players[data[VMS::PACKET_KEYS[:id]]].update(data)
          cluster.players[data[VMS::PACKET_KEYS[:id]]].socket = socket if socket
        end
      end

      def list_clusters(address, port)
        list = @clusters.values.map { |c| { id: c.id, player_count: c.player_count } }
        send([:cluster_list, list], address, port)
      end

      def send(data, address, port, socket = nil)
        binary = Zlib::Deflate.deflate(Marshal.dump(data), Zlib::BEST_SPEED)
        send_binary(binary, address, port, socket)
      end

      def send_binary(binary, address, port, socket = nil)
        if @use_tcp && socket
          begin
            socket.write([binary.bytesize].pack("N") + binary)
          rescue
            @clients.delete(socket.addr)
            @clusters.each_value { |c| c.remove_player_by_address(address, port) }
          end
        else
          begin
            @socket.send(binary, 0, address, port)
          rescue
          end
        end
      end

      def remove_cluster(id)
        @clusters.delete(id)
      end
    end

    class Cluster
      attr_reader :id, :players, :online_variables
      attr_accessor :variables_dirty

      def initialize(id, server)
        @id = id
        @server = server
        @players = {}
        @online_variables = {}
        @variables_dirty = true
      end

      def add_player(player)
        @players[player.id] = player
        @players.each_value { |p| p.dirty = true }
        @variables_dirty = true
      end

      def remove_player(id)
        @players.delete(id)
        @players.each_value do |p|
          @server.send([:disconnect_player, id], p.address, p.port, p.socket)
        end
        @server.remove_cluster(@id) if @players.empty?
      end

      def player_count; @players.length; end

      def has_player(address, port)
        @players.each_value.any? { |p| p.address == address && p.port == port }
      end

      def remove_player_by_address(address, port)
        player = @players.values.find { |p| p.address == address && p.port == port }
        remove_player(player.id) if player
      end

      def update_players
        @players.each_value do |player|
          if Time.now - player.heartbeat > 30
            remove_player(player.id)
          end
        end
        return if @players.empty?

        data = []
        data.push([:online_variables, @online_variables]) if @variables_dirty
        @players.each_value { |p| data.push(p.to_hash(p.dirty)) }
        
        binary = Zlib::Deflate.deflate(Marshal.dump(data), Zlib::BEST_COMPRESSION)
        @players.each_value { |p| @server.send_binary(binary, p.address, p.port, p.socket) }
        
        @players.each_value { |p| p.dirty = false }
        @variables_dirty = false
      end
    end

    class Player
      attr_reader :id, :address, :port, :heartbeat
      attr_accessor :socket, :dirty, :name

      def initialize(id, address, port)
        @id = id
        @address = address
        @port = port
        @heartbeat = Time.now
        @dirty = true
        @data = {}
      end

      def update(data)
        hb_key = VMS::PACKET_KEYS[:heartbeat]
        if data[hb_key]
          return if data[hb_key] < @heartbeat
          @heartbeat = data[hb_key]
        end
        
        data.each do |k, v|
          next if k == hb_key
          @data[k] = v
        end
        @name = data[VMS::PACKET_KEYS[:name]] if data[VMS::PACKET_KEYS[:name]]
        @dirty = true
      end

      def to_hash(full = true)
        hash = { VMS::PACKET_KEYS[:id] => @id, VMS::PACKET_KEYS[:heartbeat] => @heartbeat }
        return hash unless full
        hash.merge!(@data)
        hash
      end
    end
  end
end
