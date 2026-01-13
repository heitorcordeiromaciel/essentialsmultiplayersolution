require 'socket'
require 'zlib'

# Configuration
HOST = '127.0.0.1'
PORT = 25565
# Match client's "Create cluster" logic: rand(10000...99999)
CLUSTER_ID = rand(10000...99999)
PLAYER_ID = 999
PLAYER_NAME = "Cluster_Creator"

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
  id: PLAYER_ID,
  name: PLAYER_NAME,
  cluster_id: CLUSTER_ID,
  game_name: "Pokemon Obsidian Demo",
  game_version: "1.0.0",
  heartbeat: Time.now
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
      id: PLAYER_ID,
      cluster_id: CLUSTER_ID,
      heartbeat: Time.now
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
