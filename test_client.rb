require 'socket'
require 'zlib'

# Configuration
HOST = '127.0.0.1'
PORT = 25565
PLAYER_ID = rand(1000..9999)
PLAYER_NAME = "Tester_#{PLAYER_ID}"

def send_packet(socket, data)
  payload = Zlib::Deflate.deflate(Marshal.dump(data), Zlib::BEST_SPEED)
  socket.send(payload, 0)
end

socket = UDPSocket.new
socket.connect(HOST, PORT)

puts "--- VMS Test Client ---"
puts "Connecting to #{HOST}:#{PORT} as #{PLAYER_NAME} (ID: #{PLAYER_ID})"

# 1. Request Cluster List
puts "\n[1] Requesting Cluster List..."
send_packet(socket, ["list_clusters", {}])

# Wait for response (loop until we get the list)
cluster_list = []
begin
  timeout = 5
  start_time = Time.now
  loop do
    if Time.now - start_time > timeout
      puts "Timed out waiting for cluster list."
      break
    end
    
    data, _ = socket.recvfrom_nonblock(65536) rescue [nil, nil]
    next if data.nil?
    
    decoded = Marshal.load(Zlib::Inflate.inflate(data))
    if decoded.is_a?(Array) && decoded[0] == :cluster_list
      cluster_list = decoded[1]
      puts "Available Clusters: #{cluster_list.inspect}"
      break
    else
      puts "Received other packet while waiting for list: #{decoded[0]}"
    end
  end
rescue => e
  puts "Error receiving cluster list: #{e}"
end

# 2. Connect to a Cluster
if cluster_list && !cluster_list.empty?
  # Sort by player count to join the most populated one, or just the first one
  target = cluster_list.max_by { |c| c[:player_count] }
  CLUSTER_ID = target[:id]
  puts "\n[2] Joining existing Cluster #{CLUSTER_ID} (#{target[:player_count]} players)..."
else
  # Match client's "Create cluster" logic if none exist
  CLUSTER_ID = rand(10000...99999)
  puts "\n[2] No clusters found. Creating new Cluster #{CLUSTER_ID}..."
end

connect_data = {
  id: PLAYER_ID,
  name: PLAYER_NAME,
  cluster_id: CLUSTER_ID,
  game_name: "Pokemon Obsidian Demo",
  game_version: "1.0.0",
  heartbeat: Time.now
}
send_packet(socket, ["connect", connect_data])

# Listener Thread
Thread.new do
  loop do
    begin
      data, _ = socket.recvfrom(65536)
      decoded = Marshal.load(Zlib::Inflate.inflate(data))
      puts "\n[Server Broadcast] #{decoded.inspect}"
    rescue => e
      # Silent rescue for clean output
    end
  end
end

# 3. Heartbeat Loop
puts "\n[3] Sending heartbeats every 2 seconds. Press Ctrl+C to stop."
loop do
  sleep 2
  update_data = {
    id: PLAYER_ID,
    cluster_id: CLUSTER_ID,
    heartbeat: Time.now,
    x: rand(1..20),
    y: rand(1..20)
  }
  send_packet(socket, ["update", update_data])
  print "." # Visual indicator
end
