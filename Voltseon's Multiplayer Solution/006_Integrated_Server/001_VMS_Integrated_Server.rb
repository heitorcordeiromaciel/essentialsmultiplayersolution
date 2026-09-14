module VMS
  module IntegratedServer
    class << self
      attr_accessor :running
      attr_accessor :thread
    end

    begin
      require "openssl"
      OpenSSL::Cipher.new("aes-256-gcm")
      GTS_HAS_OPENSSL = true
    rescue LoadError, StandardError
      GTS_HAS_OPENSSL = false
    end
    begin
      require "digest"
      Digest::SHA256.digest("")
      GTS_HAS_DIGEST = true
    rescue LoadError, StandardError
      GTS_HAS_DIGEST = false
    end

    class GTS
      FILE_PATH = File.directory?(System.data_directory) ? File.join(System.data_directory, "gts_listings.dat") : "./gts_listings.dat"
      CHECKSUM_LENGTH = 32

      attr_reader :load_error

      def initialize
        @mutex      = Mutex.new
        @available  = true
        @next_id    = 1
        @records    = []
        load_from_disk
      end

      def available?
        @available
      end

      def list_active
        @mutex.synchronize do
          @records.select { |r| r[:status] == :active }.map do |r|
            { id: r[:id], seller_id: r[:seller_id], seller_name: r[:seller_name], kind: r[:kind], summary: r[:summary], price: r[:price], preview: r[:preview] }
          end
        end
      end

      def my_listings(player_id)
        @mutex.synchronize { @records.select { |r| r[:seller_id] == player_id }.map(&:dup) }
      end

      def peek(listing_id)
        return [false, "GTS is currently unavailable.", nil] unless @available
        @mutex.synchronize do
          record = @records.find { |r| r[:id] == listing_id }
          next [false, "That listing no longer exists.", nil] if record.nil?
          next [true, record[:payload], record[:kind]]
        end
      end

      def create(kind, summary, payload, price, seller_id, seller_name, preview = nil)
        return [false, "GTS is currently unavailable."] unless @available
        return [false, "Invalid listing kind."] unless [:pokemon, :item].include?(kind)
        return [false, "Invalid price."] unless price.is_a?(Integer) && price > 0
        return [false, "Invalid summary."] unless summary.is_a?(String) && !summary.strip.empty?
        @mutex.synchronize do
          per_player = @records.count { |r| r[:seller_id] == seller_id && r[:status] == :active }
          if VMS::GTS_MAX_LISTINGS_PER_PLAYER > 0 && per_player >= VMS::GTS_MAX_LISTINGS_PER_PLAYER
            next [false, "You have reached the maximum number of active GTS listings."]
          end
          total_active = @records.count { |r| r[:status] == :active }
          if VMS::GTS_MAX_LISTINGS_TOTAL > 0 && total_active >= VMS::GTS_MAX_LISTINGS_TOTAL
            next [false, "The GTS is currently full."]
          end
          id = @next_id
          @next_id += 1
          @records.push({
            id: id, seller_id: seller_id, seller_name: seller_name.to_s,
            kind: kind, summary: summary.to_s, payload: payload, price: price,
            preview: preview, status: :active, buyer_id: nil, listed_at: Time.now, sold_at: nil
          })
          if save_to_disk
            next [true, id]
          else
            @records.pop
            @next_id -= 1
            next [false, "Failed to save the GTS listing."]
          end
        end
      end

      def claim(listing_id, buyer_id)
        return [false, "GTS is currently unavailable.", nil] unless @available
        @mutex.synchronize do
          record = @records.find { |r| r[:id] == listing_id }
          next [false, "That listing no longer exists.", nil] if record.nil?
          next [false, "That listing is no longer available.", nil] unless record[:status] == :active
          next [false, "You cannot claim your own listing.", nil] if record[:seller_id] == buyer_id
          previous_status = record[:status]
          record[:status]   = :sold
          record[:buyer_id] = buyer_id
          record[:sold_at]  = Time.now
          if save_to_disk
            next [true, record[:payload], record[:kind]]
          else
            record[:status]   = previous_status
            record[:buyer_id] = nil
            record[:sold_at]  = nil
            next [false, "Failed to save the GTS claim.", nil]
          end
        end
      end

      def collect(listing_id, seller_id)
        return [false, "GTS is currently unavailable."] unless @available
        @mutex.synchronize do
          record = @records.find { |r| r[:id] == listing_id }
          next [false, "That listing no longer exists."] if record.nil?
          next [false, "That listing does not belong to you."] unless record[:seller_id] == seller_id
          next [false, "That listing has not been sold yet."] unless record[:status] == :sold
          price = record[:price]
          @records.delete(record)
          if save_to_disk
            next [true, price]
          else
            @records.push(record)
            next [false, "Failed to save the GTS collection."]
          end
        end
      end

      def cancel(listing_id, seller_id)
        return [false, "GTS is currently unavailable.", nil] unless @available
        @mutex.synchronize do
          record = @records.find { |r| r[:id] == listing_id }
          next [false, "That listing no longer exists.", nil] if record.nil?
          next [false, "That listing does not belong to you.", nil] unless record[:seller_id] == seller_id
          next [false, "That listing is no longer active.", nil] unless record[:status] == :active
          @records.delete(record)
          if save_to_disk
            next [true, record[:payload], record[:kind]]
          else
            @records.push(record)
            next [false, "Failed to save the GTS cancellation.", nil]
          end
        end
      end

      private

      def load_from_disk
        return unless File.exist?(FILE_PATH)
        blob = File.binread(FILE_PATH)
        return if blob.nil? || blob.empty?
        @records = decrypt(blob)
        @next_id = (@records.map { |r| r[:id] }.max || 0) + 1
      rescue StandardError => e
        @available  = false
        @records    = []
        @load_error = e.message
      end

      def save_to_disk
        File.binwrite(FILE_PATH, encrypt(@records))
        true
      rescue StandardError => e
        @load_error = e.message
        false
      end

      def key_bytes
        VMS::GTS_ENCRYPTION_KEY.to_s
      end

      def encrypt(records)
        plaintext = Marshal.dump(records)
        return xor_with_checksum(plaintext) unless GTS_HAS_OPENSSL
        key = OpenSSL::Digest::SHA256.digest(key_bytes)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = key
        iv = cipher.random_iv
        cipher.auth_data = ""
        ciphertext = cipher.update(plaintext) + cipher.final
        iv + cipher.auth_tag + ciphertext
      end

      def decrypt(blob)
        return Marshal.load(xor_verify_and_decrypt(blob)) unless GTS_HAS_OPENSSL
        key        = OpenSSL::Digest::SHA256.digest(key_bytes)
        iv         = blob[0, 12]
        tag        = blob[12, 16]
        ciphertext = blob[28..-1] || ""
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        cipher.iv  = iv
        cipher.auth_tag  = tag
        cipher.auth_data = ""
        Marshal.load(cipher.update(ciphertext) + cipher.final)
      end

      def xor_with_checksum(plaintext)
        keyed_checksum(plaintext) + xor_bytes(plaintext)
      end

      def xor_verify_and_decrypt(blob)
        sum        = blob[0, CHECKSUM_LENGTH]
        ciphertext = blob[CHECKSUM_LENGTH..-1] || ""
        plaintext  = xor_bytes(ciphertext)
        raise "GTS file failed checksum verification (tampered or corrupted)" if sum != keyed_checksum(plaintext)
        plaintext
      end

      def xor_bytes(data)
        stream = Random.new(VMS.string_to_integer(key_bytes)).bytes(data.bytesize)
        data.bytes.each_with_index.map { |b, i| b ^ stream.getbyte(i) }.pack("C*")
      end

      def keyed_checksum(plaintext)
        if GTS_HAS_DIGEST
          Digest::SHA256.digest(key_bytes + plaintext)
        else
          hash = VMS.string_to_integer(key_bytes)
          (key_bytes + plaintext).each_byte { |b| hash = ((hash * 33) ^ b) & 0xFFFFFFFF }
          ([hash].pack("N") * (CHECKSUM_LENGTH / 4))
        end
      end
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
      VMS.log("Integrated Server started on port #{PORT}")
    end

    def self.stop
      @running = false
      @thread&.kill
      @thread = nil
      VMS.log("Integrated Server stopped")
    end

    class Server
      def initialize
        @port = PORT
        @host = '0.0.0.0'
        @clusters = {}
        @clients = {}
        @tick_rate = TICK_RATE
        @heartbeat_timeout = HEARTBEAT_TIMEOUT
        @use_tcp = USE_TCP

        if @use_tcp
          @socket = TCPServer.new(@host, @port)
        else
          @socket = UDPSocket.new
          @socket.bind(@host, @port)
        end
        @gts = GTS.new
        VMS.log("GTS store failed to load and has been disabled: #{@gts.load_error}", true) unless @gts.available?
      end

      def start
        last_tick = Time.now
        tick_interval = 1.0 / @tick_rate

        while VMS::IntegratedServer.running
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
                    data = s.respond_to?(:recv_nonblock) ? s.recv_nonblock(65536) : s.recv(65536)
                    handle_packet(data, s.addr[3], s.addr[1], s)
                  else
                    data, address = @socket.respond_to?(:recvfrom_nonblock) ? @socket.recvfrom_nonblock(65536) : @socket.recvfrom(65536)
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

          if (Time.now - last_tick) >= tick_interval
            @clusters.each_value do |cluster|
              begin
                cluster.update_players
              rescue => e
                VMS.log("Error updating cluster #{cluster.id}: #{e.message}", true)
              end
            end
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
          return unless data.is_a?(Array)
          return unless data.length >= 2 || (data.length >= 1 && ["list_clusters", "gts_list"].include?(data[0]))

          case data[0]
          when "connect"      then connect(address, port, sanitize_data(data[1]), socket)
          when "disconnect"   then disconnect(address, port, sanitize_data(data[1]), socket)
          when "update"       then update(address, port, sanitize_data(data[1]), socket)
          when "list_clusters" then list_clusters(address, port)
          when "chat"         then chat(address, port, sanitize_data(data[1]), socket)
          when "gts_list"         then gts_list(address, port, socket)
          when "gts_create"       then gts_create(address, port, data[1], socket)
          when "gts_claim"        then gts_claim(address, port, data[1], socket)
          when "gts_my_listings"  then gts_my_listings(address, port, data[1], socket)
          when "gts_collect"      then gts_collect(address, port, data[1], socket)
          when "gts_cancel"       then gts_cancel(address, port, data[1], socket)
          when "gts_peek"         then gts_peek(address, port, data[1], socket)
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
        if VMS::CHECK_GAME_AND_VERSION
          if data[VMS::PACKET_KEYS[:game_name]] != System.game_title
            send(:disconnect_wrong_game, address, port, socket)
            return
          end
          if data[VMS::PACKET_KEYS[:game_version]] != Settings::GAME_VERSION
            send(:disconnect_wrong_version, address, port, socket)
            return
          end
        end
        cluster_id = 0
        cluster = @clusters[cluster_id]

        if cluster.nil?
          cluster = Cluster.new(cluster_id, self)
          @clusters[cluster_id] = cluster
        end

        max_players = VMS::MAX_PLAYERS rescue 4
        if cluster.player_count < max_players
          player = Player.new(data[VMS::PACKET_KEYS[:id]], address, port)
          player.socket = socket
          cluster.add_player(player)
          player.update(data)
        else
          VMS.log("Connection rejected: Cluster 0 is full", true)
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

      def gts_list(address, port, socket = nil)
        send([:gts_list_result, @gts.list_active], address, port, socket)
      end

      def gts_create(address, port, data, socket = nil)
        return unless data.is_a?(Array) && data.length >= 6
        kind, summary, payload, price, seller_id, seller_name, preview = data
        success, id_or_reason = @gts.create(kind, summary, payload, price, seller_id, seller_name, preview)
        send([:gts_create_result, success, id_or_reason], address, port, socket)
      end

      def gts_claim(address, port, data, socket = nil)
        return unless data.is_a?(Array) && data.length >= 2
        listing_id, buyer_id = data
        success, payload_or_reason, kind = @gts.claim(listing_id, buyer_id)
        send([:gts_claim_result, success, payload_or_reason, kind], address, port, socket)
      end

      def gts_my_listings(address, port, data, socket = nil)
        player_id = data.is_a?(Array) ? data[0] : data
        send([:gts_my_listings_result, @gts.my_listings(player_id)], address, port, socket)
      end

      def gts_collect(address, port, data, socket = nil)
        return unless data.is_a?(Array) && data.length >= 2
        listing_id, seller_id = data
        success, price_or_reason = @gts.collect(listing_id, seller_id)
        send([:gts_collect_result, success, price_or_reason], address, port, socket)
      end

      def gts_cancel(address, port, data, socket = nil)
        return unless data.is_a?(Array) && data.length >= 2
        listing_id, seller_id = data
        success, payload_or_reason, kind = @gts.cancel(listing_id, seller_id)
        send([:gts_cancel_result, success, payload_or_reason, kind], address, port, socket)
      end

      def gts_peek(address, port, data, socket = nil)
        return unless data.is_a?(Array) && data.length >= 1
        listing_id = data[0]
        success, payload_or_reason, kind = @gts.peek(listing_id)
        send([:gts_peek_result, success, payload_or_reason, kind], address, port, socket)
      end

      MAX_CHAT_MESSAGE_LENGTH = 500

      def chat(address, port, data, socket = nil)
        cluster_id = data[VMS::PACKET_KEYS[:cluster_id]]
        cluster = @clusters[cluster_id]
        return unless cluster && cluster.has_player(address, port)
        sender = cluster.players[data[VMS::PACKET_KEYS[:id]]]
        return if sender.nil?
        text = data[:text].to_s.strip
        return if text.empty?
        text = text[0, MAX_CHAT_MESSAGE_LENGTH]
        cluster.players.each_value do |p|
          next if p.id == sender.id
          send([:chat, sender.id, sender.name, text], p.address, p.port, p.socket)
        end
      end

      def send(data, address, port, socket = nil)
        binary = Zlib::Deflate.deflate(Marshal.dump(data), VMS::TICK_COMPRESSION_LEVEL)
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
        send_snapshot_to(player)
      end

      def send_snapshot_to(player)
        data = [[:online_variables, @online_variables]]
        @players.each_value { |p| data.push(p.full_hash) }
        binary = Zlib::Deflate.deflate(Marshal.dump(data), VMS::TICK_COMPRESSION_LEVEL)
        @server.send_binary(binary, player.address, player.port, player.socket)
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

        binary = Zlib::Deflate.deflate(Marshal.dump(data), VMS::TICK_COMPRESSION_LEVEL)
        @players.each_value { |p| @server.send_binary(binary, p.address, p.port, p.socket) }

        @players.each_value { |p| p.dirty = false }
        @variables_dirty = false
      end
    end

    class Player
      attr_reader :id, :address, :port, :heartbeat, :dirty
      attr_accessor :socket, :name

      def initialize(id, address, port)
        @id = id
        @address = address
        @port = port
        @heartbeat = Time.now
        @dirty = true
        @data = {}
        @dirty_fields = {}
      end

      def update(data)
        hb_key = VMS::PACKET_KEYS[:heartbeat]
        if data[hb_key]
          return if data[hb_key] < @heartbeat
          @heartbeat = data[hb_key]
        end

        data.each do |k, v|
          next if k == hb_key
          next if @data.key?(k) && @data[k] == v
          @data[k] = v
          @dirty_fields[k] = true
        end
        @name = data[VMS::PACKET_KEYS[:name]] if data[VMS::PACKET_KEYS[:name]]
        @dirty = true unless @dirty_fields.empty?
      end

      def dirty=(value)
        @dirty = value
        @dirty_fields.clear unless value
      end

      def to_hash(full = true)
        hash = { VMS::PACKET_KEYS[:id] => @id, VMS::PACKET_KEYS[:heartbeat] => @heartbeat }
        return hash unless full
        @dirty_fields.each_key { |k| hash[k] = @data[k] }
        hash
      end

      def full_hash
        hash = { VMS::PACKET_KEYS[:id] => @id, VMS::PACKET_KEYS[:heartbeat] => @heartbeat }
        hash.merge!(@data)
        hash
      end
    end
  end
end
