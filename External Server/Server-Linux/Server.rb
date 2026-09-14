class Pokemon
  class Move; end
  class Owner; end
end

module VMS
  require 'socket'
  require "zlib"
  require "openssl"
  require_relative 'Config'
  require_relative 'Cluster'
  require_relative 'Player'

  class GTS
    FILE_PATH = File.join(__dir__, "gts_listings.dat")

    attr_reader :load_error

    def initialize
      @mutex = Mutex.new
      @key = OpenSSL::Digest::SHA256.digest(Config.gts_encryption_key.to_s)
      @available = true
      @next_id = 1
      @records = []
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

    def peek(listing_id)
      return [false, "GTS is currently unavailable.", nil] unless @available
      @mutex.synchronize do
        record = @records.find { |r| r[:id] == listing_id }
        next [false, "That listing no longer exists.", nil] if record.nil?
        next [true, record[:payload], record[:kind]]
      end
    end

    def my_listings(player_id)
      @mutex.synchronize { @records.select { |r| r[:seller_id] == player_id }.map(&:dup) }
    end

    def create(kind, summary, payload, price, seller_id, seller_name, preview = nil)
      return [false, "GTS is currently unavailable."] unless @available
      return [false, "Invalid listing kind."] unless [:pokemon, :item].include?(kind)
      return [false, "Invalid price."] unless price.is_a?(Integer) && price > 0
      return [false, "Invalid summary."] unless summary.is_a?(String) && !summary.strip.empty?
      @mutex.synchronize do
        per_player = @records.count { |r| r[:seller_id] == seller_id && r[:status] == :active }
        if Config.gts_max_listings_per_player > 0 && per_player >= Config.gts_max_listings_per_player
          next [false, "You have reached the maximum number of active GTS listings."]
        end
        total_active = @records.count { |r| r[:status] == :active }
        if Config.gts_max_listings_total > 0 && total_active >= Config.gts_max_listings_total
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
      @available   = false
      @records     = []
      @load_error  = e.message
    end

    def save_to_disk
      File.binwrite(FILE_PATH, encrypt(@records))
      true
    rescue StandardError => e
      @load_error = e.message
      false
    end

    def encrypt(records)
      cipher = OpenSSL::Cipher.new("aes-256-gcm")
      cipher.encrypt
      cipher.key = @key
      iv = cipher.random_iv
      cipher.auth_data = ""
      ciphertext = cipher.update(Marshal.dump(records)) + cipher.final
      iv + cipher.auth_tag + ciphertext
    end

    def decrypt(blob)
      iv         = blob[0, 12]
      tag        = blob[12, 16]
      ciphertext = blob[28..-1] || ""
      cipher = OpenSSL::Cipher.new("aes-256-gcm")
      cipher.decrypt
      cipher.key = @key
      cipher.iv  = iv
      cipher.auth_tag  = tag
      cipher.auth_data = ""
      Marshal.load(cipher.update(ciphertext) + cipher.final)
    end
  end

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
      @gts = GTS.new
      log("GTS store failed to load and has been disabled: #{@gts.load_error}", true) unless @gts.available?
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
        wait_time = nil
        if tick_interval > 0
          now = Time.now
          elapsed = now - last_tick
          wait_time = [tick_interval - elapsed, 0].max
        end

        readable, = IO.select([@socket] + @clients.values, nil, nil, wait_time)

        if readable
          readable.each do |s|
            if s == @socket && Config.use_tcp
              begin
                client = @socket.accept_nonblock
                @clients[client.addr] = client
                log("New client connected: #{client.addr}")
              rescue IO::WaitReadable, IO::WaitWritable
              end
            else
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

        if tick_interval == 0 || (Time.now - last_tick) >= tick_interval
          @clusters.each_value do |cluster|
            begin
              cluster.update_players
            rescue => e
              log("Error updating cluster #{cluster.id}: #{e}", true)
            end
          end
          last_tick = Time.now
        end
      end
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
        when "list_clusters" then list_clusters(address, port, socket)
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
        log("Packet error from #{address}:#{port} - #{e}", true)
      end
    end

    def sanitize_data(data)
      return {} unless data.is_a?(Hash)
      sanitized = {}
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
        key = k
        if k.is_a?(String) || k.is_a?(Symbol)
          key = PACKET_KEYS[k.to_sym] || k
        end

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
      if Config.check_game_and_version
        if data[PACKET_KEYS[:game_name]] != Config.game_name
          send(:disconnect_wrong_game, address, port, socket)
          return
        end
        if data[PACKET_KEYS[:game_version]] != Config.game_version
          send(:disconnect_wrong_version, address, port, socket)
          return
        end
      end
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
      elsif Config.max_clusters > 0 && @clusters.length >= Config.max_clusters
        log("#{get_player_name(data)} tried to create cluster #{cluster_id}, but the server has reached its maximum of #{Config.max_clusters} clusters.", true)
        send(:disconnect_full, address, port, socket)
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

    MAX_CHAT_MESSAGE_LENGTH = 500

    def chat(address, port, data, socket = nil)
      cluster_id = data[PACKET_KEYS[:cluster_id]]
      return unless cluster_exists(cluster_id)
      cluster = @clusters.values.find { |c| c.id == cluster_id }
      return unless cluster.has_player(address, port)
      sender = cluster.players[data[PACKET_KEYS[:id]]]
      return if sender.nil?
      text = data[:text].to_s.strip
      return if text.empty?
      text = text[0, MAX_CHAT_MESSAGE_LENGTH]
      log("#{sender.name} (#{sender.id}) chat: #{text}")
      cluster.players.each_value do |p|
        next if p.id == sender.id
        send([:chat, sender.id, sender.name, text], p.address, p.port, p.socket)
      end
    end

    def send(data, address, port, socket = nil)
      binary = Zlib::Deflate.deflate(Marshal.dump(data), Config.compression_level)
      send_binary(binary, address, port, socket)
    end

    def send_binary(binary, address, port, socket = nil)
      if Config.use_tcp
        target = socket || @clients.values.find { |c| c.addr[3] == address && c.addr[1] == port }
        if target
          begin
            target.write([binary.bytesize].pack("N") + binary)
          rescue => e
            log("TCP Send Error to #{address}:#{port} - #{e}")
            @clients.delete(target.addr)
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

    def gts_list(address, port, socket = nil)
      send([:gts_list_result, @gts.list_active], address, port, socket)
    end

    def gts_create(address, port, data, socket = nil)
      return unless data.is_a?(Array) && data.length >= 6
      kind, summary, payload, price, seller_id, seller_name, preview = data
      success, id_or_reason = @gts.create(kind, summary, payload, price, seller_id, seller_name, preview)
      send([:gts_create_result, success, id_or_reason], address, port, socket)
      log("#{seller_name} listed \"#{summary}\" on the GTS for #{price}.") if success
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
  end

  Server.new
end