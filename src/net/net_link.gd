class_name NetLink
extends Node
## LAN transport for two-player network races (M5.1): Godot's ENet, one host
## and at most one client. Messages are Arrays ([type, ...]) sent as bytes
## (var_to_bytes, no objects), so no node paths have to match between the two
## computers. Reliable messages carry session flow and combat events; the
## frequent snapshots and inputs are unreliable-ordered (newest wins).
## Owns its own SceneMultiplayer, so a host and a client can also live in one
## process (tests). Optional simulated latency / loss for testing.

signal connected                       ## client: connected to the host
signal connection_failed               ## client: could not connect
signal peer_joined(peer_id: int)       ## host: a client connected
signal peer_left(peer_id: int)         ## host: the client disconnected
signal server_closed                   ## client: the host went away
signal message(peer_id: int, msg: Array)

const DEFAULT_PORT := 24680
## ENet peer timeouts (ms): generous enough for internet jitter, short enough
## that an unreachable host or a dead peer is reported within ~10 seconds.
const TIMEOUT_MIN_MS := 5000
const TIMEOUT_MAX_MS := 10000
const CHANNEL_RELIABLE := 0
const CHANNEL_FAST := 1

var mp := SceneMultiplayer.new()
var is_host := false
## Test aids: delay (ms) for every outgoing message, drop chance for unreliable ones.
var sim_latency_ms := 0
var sim_loss := 0.0
## Test aid: random extra delay 0..sim_jitter_ms per message (reliable messages
## keep their order, unreliable ones may arrive out of order, as on the internet).
var sim_jitter_ms := 0
var _last_reliable_due := 0
var _rng := RandomNumberGenerator.new()
var _delayed: Array = []
var _open := false


func _init() -> void:
	mp.peer_connected.connect(func(id: int) -> void:
		_on_peer_timeouts(id)
		if is_host:
			peer_joined.emit(id))
	mp.peer_disconnected.connect(func(id: int) -> void:
		if is_host:
			peer_left.emit(id))
	mp.connected_to_server.connect(func() -> void: connected.emit())
	mp.connection_failed.connect(func() -> void:
		_open = false
		connection_failed.emit())
	mp.server_disconnected.connect(func() -> void:
		_open = false
		server_closed.emit())
	mp.peer_packet.connect(_on_packet)
	_rng.seed = 5150


func _enter_tree() -> void:
	mp.root_path = get_path()


## Starts hosting on `port`; returns OK or an error code.
func host(port: int = DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1, 2)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	mp.multiplayer_peer = peer
	is_host = true
	_open = true
	return OK


## Connects to a host by IP address; `connected` or `connection_failed` follows.
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, 2)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	var server := peer.get_peer(1)
	if server != null:
		server.set_timeout(32, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)  # an unreachable host fails within ~10 s
	mp.multiplayer_peer = peer
	is_host = false
	_open = true
	return OK


func is_open() -> bool:
	return _open


## Parses "1.2.3.4" or "1.2.3.4:24680" (IPv4: localhost, LAN or a public
## address). Returns {ok, ip, port, error}.
static func parse_address(text: String, default_port: int = DEFAULT_PORT) -> Dictionary:
	var t := text.strip_edges()
	var ip := t
	var port := default_port
	if t.count(":") == 1:
		ip = t.get_slice(":", 0)
		var p := t.get_slice(":", 1)
		if not p.is_valid_int() or int(p) < 1 or int(p) > 65535:
			return {"ok": false, "error": "The port after ':' must be a number from 1 to 65535."}
		port = int(p)
	if ip == "localhost":
		ip = "127.0.0.1"
	if not ip.is_valid_ip_address() or ":" in ip:
		return {"ok": false, "error": "Please type the host's IPv4 address, e.g. 192.168.1.20 or 203.0.113.7 (optionally :port)."}
	return {"ok": true, "ip": ip, "port": port, "error": ""}


## Round-trip time to the other computer (ms), or -1 when not connected.
func ping_ms() -> int:
	var p := _remote_enet_peer()
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p != null else -1


## Packet loss towards the other computer (0..1), or 0 when unknown.
func packet_loss() -> float:
	var p := _remote_enet_peer()
	return p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE) if p != null else 0.0


func _remote_enet_peer() -> ENetPacketPeer:
	var enet := mp.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or not _open:
		return null
	var ids := mp.get_peers()
	return enet.get_peer(ids[0]) if ids.size() > 0 else null


## Remote peer ids (the host sees its client; the client sees the host, 1).
func peers() -> PackedInt32Array:
	return mp.get_peers() if _open else PackedInt32Array()


## Sends a message to one peer (0 = everyone connected).
func send(msg: Array, reliable: bool, peer_id: int = 0) -> void:
	if not _open or mp.multiplayer_peer == null:
		return
	if not reliable and sim_loss > 0.0 and _rng.randf() < sim_loss:
		return
	var bytes := var_to_bytes(msg)
	if sim_latency_ms > 0 or sim_jitter_ms > 0:
		var due := Time.get_ticks_msec() + sim_latency_ms + (_rng.randi_range(0, sim_jitter_ms) if sim_jitter_ms > 0 else 0)
		if reliable:
			due = maxi(due, _last_reliable_due)
			_last_reliable_due = due
		# stable insert: after every message due at the same time or earlier
		var i := _delayed.size()
		while i > 0 and _delayed[i - 1][0] > due:
			i -= 1
		_delayed.insert(i, [due, bytes, reliable, peer_id])
		return
	_send_now(bytes, reliable, peer_id)


## Peers that stop answering are dropped within a few seconds (both sides).
func _on_peer_timeouts(id: int) -> void:
	var enet := mp.multiplayer_peer as ENetMultiplayerPeer
	if enet != null:
		var p := enet.get_peer(id)
		if p != null:
			p.set_timeout(32, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


## Drops the remote side (host: kicks the client).
func disconnect_peer(peer_id: int) -> void:
	if _open and is_host and mp.multiplayer_peer != null:
		mp.multiplayer_peer.disconnect_peer(peer_id)


func close() -> void:
	if mp.multiplayer_peer != null:
		mp.multiplayer_peer.close()
	mp.multiplayer_peer = null
	_open = false
	_delayed.clear()


func _process(_delta: float) -> void:
	poll()


func _physics_process(_delta: float) -> void:
	poll()


func poll() -> void:
	if _delayed.size() > 0:
		var now := Time.get_ticks_msec()
		while _delayed.size() > 0 and _delayed[0][0] <= now:
			var d: Array = _delayed.pop_front()
			_send_now(d[1], d[2], d[3])
	if mp.multiplayer_peer != null:
		mp.poll()


func _send_now(bytes: PackedByteArray, reliable: bool, peer_id: int) -> void:
	if mp.multiplayer_peer == null or mp.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED \
			or mp.get_peers().is_empty():
		return
	mp.send_bytes(bytes, peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, CHANNEL_RELIABLE if reliable else CHANNEL_FAST)


func _on_packet(peer_id: int, bytes: PackedByteArray) -> void:
	if bytes.size() < 8 or (bytes.decode_u32(0) & 0xFF) != TYPE_ARRAY:
		return
	var v: Variant = bytes_to_var(bytes)
	if v is Array and not v.is_empty():
		message.emit(peer_id, v)


func _exit_tree() -> void:
	close()
