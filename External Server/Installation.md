
## Enabling the external server on the config

Set the option `USE_EXTERNAL_SERVER` to `true` in the `001_VMS_Config.rb` file, if this option is set to false, the Client will only be able to use the Integrated Server.
Set `EXTERNALHOST` and `EXTERNALPORT` to your servers ipv4 address and port respectively.

## Server Setup

Pre-packaged server builds are included for both **Windows** and **Linux**, and include a standalone Ruby installation

## Folder Structure
```
Server/
├── ruby/ # standalone ruby installation for the server to run on
├── Server.rb
├── Config.rb
├── Player.rb
├── Cluster.rb
├── config.ini
├── start.bat # For Windows
└── start.sh # For Linux
```
## Configuration
The server reads settings from `config.ini`.  
You can edit it with any text editor:

1. `host`: This is the hostname or IP address of your server that is used for people
to connect to the server.
2. `port`: This is the port of the server. It is an identifier for your machine to let it
know that all incoming and outbound data through that port is for and from the
server. It is important that the port is open for public networks as otherwise you
wouldn’t be able to join from outside the server’s network.
3. `check_game_and_version`: Whether the server should check for players’ game
and version. This is useful to ensure players from different games or versions of
your game don’t try to connect to the server and crash other players.
4. `game_name`: The name of your game, the server will only accept players who
are trying to connect to the server from a game with this name. The name of
your game can be seen and changed in RPG Maker XP by clicking on ‘Game’ on
the top bar and clicking on ‘Change Title…’.
5. `game_version`: The version of your game, the server will only accept players
who are trying to connect to the server from a game with this version. You can
change the version of your game by going into your game’s scripts and changing
the `GAME_VERSION` configuration under ‘001_Settings.rb’.
6. `max_players`: This is how many players are allowed onto one cluster. This does
not mean a total of allowed players connected to the server. If too many players
are connected to each other in the same cluster, it could cause lag for all players.
Setting it to 4, or anything below 8 is recommended.
7. `log`: Whether the server should log to the console. Setting this to ‘true’ means
you will receive logs about server events. Set this to ‘false’ to not receive any
logs.
8. `heartbeat_timeout`: How many seconds a player can be idle for before being
kicked. Idle means not receiving any data from this player. By default, this is set
to 5 seconds, but it is not recommended to set this too low or too high.
9. `use_tcp`: Whether the server uses TCP or UDP. These are protocols used to
transfer data. TCP is reliable but slow, while UDP is generally faster but less
reliable. By default, this is set to ‘false’ but for some games TCP would be
beneficial. Make sure when you change this to also change the plugin
configuration to use the same protocol
10. `threading`: Whether the server should use threading for each cluster. This will
make all clusters run asynchronously but will cost more memory. By default, this
is set to ‘true’.
11. `tick_rate`: This is how many times per second the server will send data. This
should be between 20-80. The higher the number, the more frequent the
updates are sent. Anything higher than 80 would be too much data/ overkill.
While anything under 20 is usually not enough data (depending on your type of
game). By default, this is set to 60 ticks per second.

When changing the configuration of the server make sure to restart your server.
Making changes to the config file can either crash the server or leave it on an
outdated version (depending on your sever hosting solution).

---

## Usage

Open the game, open the Menu, select Link Play, then select Online Play, either Create a Cluster or Browse and join existing Clusters.