require 'socket'
require 'zlib'

# Configuration
HOST = '127.0.0.1'
PORT = 25565
# Match client's "Create cluster" logic: rand(10000...99999)
CLUSTER_ID = rand(10000...99999)
PLAYER_ID = 999
PLAYER_NAME = "Cluster_Creator"

# Mapping for integer-keyed serialization
PACKET_KEYS = {
  id: 1, heartbeat: 2, name: 3, map_id: 4, x: 5, y: 6, real_x: 7, real_y: 8,
  trainer_type: 9, direction: 10, pattern: 11, graphic: 12, party: 13,
  animation: 14, offset_x: 15, offset_y: 16, opacity: 17, stop_animation: 18,
  rf_event: 19, jump_offset: 20, jumping_on_spot: 21, surfing: 22, diving: 23,
  surf_base_coords: 24, state: 25, busy: 26, cluster_id: 27,
  online_variables: 28, game_name: 29, game_version: 30
}

def send_packet(socket, data)
  payload = Zlib::Deflate.deflate(Marshal.dump(data), Zlib::BEST_SPEED)
  socket.send(payload, 0)
end

socket = UDPSocket.new
socket.connect(HOST, PORT)

puts "--- VMS Cluster Creator ---"
puts "Connecting to #{HOST}:#{PORT} as #{PLAYER_NAME} (ID: #{PLAYER_ID})"
puts "Target Cluster ID: #{CLUSTER_ID}"

# Connect Packet (This creates the cluster if it doesn't exist)
connect_data = {
  PACKET_KEYS[:id] => PLAYER_ID,
  PACKET_KEYS[:name] => PLAYER_NAME,
  PACKET_KEYS[:cluster_id] => CLUSTER_ID,
  PACKET_KEYS[:game_name] => "Pokemon Obsidian Demo",
  PACKET_KEYS[:game_version] => "1.0.0",
  PACKET_KEYS[:heartbeat] => Time.now
}
puts "\n[1] Sending Connect Packet..."
send_packet(socket, ["connect", connect_data])

# Heartbeat Loop to keep the cluster alive
puts "Cluster #{CLUSTER_ID} is now active. Sending heartbeats to keep it alive..."
puts "Press Ctrl+C to stop and allow the cluster to be deleted."

loop do
  begin
    sleep 2
    update_data = {
      PACKET_KEYS[:id] => PLAYER_ID,
      PACKET_KEYS[:cluster_id] => CLUSTER_ID,
      PACKET_KEYS[:heartbeat] => Time.now
    }
    send_packet(socket, ["update", update_data])
    print "H" # Heartbeat indicator
  rescue Errno::ECONNREFUSED
    puts "\n[Error] Connection refused! Is the server running on #{HOST}:#{PORT}?"
    break
  rescue => e
    puts "\n[Error] #{e}"
    break
  end
end
