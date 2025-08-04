class_name DVClient
extends Node

signal start_server(port: int) # Matches complete - time to start MultiplayerPeer server
signal start_client(ip: String, port: int, local_port: int) # Matches complete - time to start MultiplayerPeer client
signal start_session(key: String) # Host registered and session ID assigned
signal new_name(name: String) # A new peer is matched and ready
signal bad_session(key: String) # The session ID does not exist
signal bad_server(key: String) # The matchmaking server is unresponsive
signal start_random() # A random pair has been matched

enum state {IDLE, HOST, JOIN, RANDOM, REGISTERED, PINGING, CLOSE}
var is_host = false
var is_random = false
var current_state: state = state.IDLE
var session_id: String = ""
var remote_key: String = ""
var local_key: String = ""
var local_ip: String = ""
var local_port: int = 30000+randi_range(0,3698)
var server_key: String = ""
var peers: Array = []
var peer_names: Array = []
var client = PacketPeerUDP.new()
var bigrams: Array = ['cy','ah','jc','du','mw','wh','rv','yq','yy','sr','ss','tg','cv','gx','ia','ba','wa','bx','sm','co','ms','ea','to','rb','xr','vx','ua','fw','ri','ds','ji','bk','bb','sp','cc','gc','bu','ow','de','io','gm','hs','kq','as','fa','dx','wf','hy','pg','ug','db','jv','wq','ir','lm','lt','hm','on','iz','is','fx','my','ph','fd','vl','zw','sv','si','dp','jp','oa','cm','ws','jm','do','ot','gd','lr','ko','se','qn','rz','xh','mz','sn','af','wo','rf','je','nj','yn','tq','zu','xp','xv','nk','wr','tk','dq','ga','tz','bl','or','ui','dt','eo','ld','hr','uv','sw','gg','hd','bs','nx','jz','au','oj','tu','br','rc','vz','tw','nb','ay','dv','tb','kc','qu','qm','mi','it','va','sa','di','be','wy','gh','ki','sl','pq','ed','iv','er','yi','iq','ls','ur','kv','ln','hh','vj','en','im','vm','hi','bm','we','fz','xb','ne','ag','hc','ma','gt','yx','pl','cr','oh','gj','wx','gq','ti','fi','hf','xm','km','ul','lv','nh','kr','ef','ly','us','ge','ju','fs','qz','fn','np','cj','vn','ft','wz','jr','tf','ww','ab','za','og','lq','mm','xw','uk','so','mb','rp','zt','xc','ad','hg','gw','pu','kx','cf','yb','gs','gr','kb','oq','xq','dn','tv','rl','vo','xz','jk','yg','qy','fr','nl','ii','yc','dz','wu','od','ng','pd','fg','fj','fh','in','na','rt','hz','es','wt','he','gi','oo','bc','cw','yv','ky','pz','wm','wi']
var steps: Dictionary = {"HR": _host_registered, "JR": _join_registered, "BK": _bad_key, "NJ": _new_joiner, "RD": _peer_ready, "JH": _join_host, "JD": _join_done}
var timer: Timer = Timer.new()
var refresh_timer = 1

### API

# HS # Ask the matching server to host a session.
func host_session(serv_key: String, alias: String) -> void:
	_add_names(alias)
	server_key = serv_key
	is_host = true
	client.close()
	var err = client.bind(local_port)
	if err != OK: push_error("host_session failed to bind to local_port "+str(local_port)+" : "+str(err))
	else: err = _send_packet(server_key, "HS:"+local_key)
	if err == OK: current_state = state.HOST
	else: bad_server.emit(server_key)

# JS # Ask the matching server to join a session based on session id.
func join_session(id: String, alias: String) -> void:
	_add_names(alias)
	session_id = id
	server_key = id.left(-4)
	client.close()
	var err = client.bind(local_port)
	if err == OK: _send_packet(server_key, "JS:"+local_key+":"+session_id)
	else: push_error("join_session failed to bind to local_port "+str(local_port)+" : "+str(err))
	current_state = state.JOIN

# RS # Ask the matching server to join or host a random session.
func random_session(serv_key: String, alias: String) -> void:
	_add_names(alias)
	server_key = serv_key
	is_random = true
	client.close()
	var err = client.bind(local_port)
	if err == OK: _send_packet(server_key, "RS:"+local_key)
	else: push_error("random_session failed to bind to local_port "+str(local_port)+" : "+str(err))
	current_state = state.RANDOM

# CS # Complete a session you are hosting with the currently connected peers.
func close_session() -> void:
	_send_packet(server_key, "CS:"+session_id)
	for peer in peers: 
		if peer.ready == "local": _send_packet(peer.local_key, "JH:"+local_key)
		else: _send_packet(peer.remote_key, "JH:"+remote_key)
	current_state = state.CLOSE

# Get host details so clients can reconnect.
func get_host() -> Array:
	var addr = _key_to_addr(peers[0].remote_key)
	if peers[0].ready == "local": addr = _key_to_addr(peers[0].local_key)
	return addr

### Comms

func _ready() -> void:
	for ip in IP.get_local_addresses(): if ip.is_valid_ip_address() and ip.find(".") != -1 and not ip.begins_with("127.") and not ip.begins_with("169.254."): local_ip = ip
	local_key = _addr_to_key(local_ip, local_port)
	add_child(timer)
	timer.start(refresh_timer)
	timer.timeout.connect(_resend)

# Listen for incoming packets and call the associated packet handler.
func _process(_delta: float) -> void:
	if client.get_available_packet_count() <= 0: return
	var packet_string = client.get_packet().get_string_from_ascii()
	var packet_key = _addr_to_key(client.get_packet_ip(), client.get_packet_port())
	if packet_string.left(2) in steps: steps[packet_string.left(2)].call(packet_key, packet_string.right(-3))

# Push a packet to a specific key.
func _send_packet(packet_key: String, packet_string: String):
	client.set_dest_address.callv(_key_to_addr(packet_key))
	var buffer = PackedByteArray()
	buffer.append_array(packet_string.to_utf8_buffer())
	return client.put_packet(buffer)

# Resend unacknowledged packets.
func _resend() -> void:
	match current_state: 
		state.HOST: _send_packet(server_key, "HS:"+local_key)
		state.JOIN: _send_packet(server_key, "JS:"+local_key+":"+session_id)
		state.RANDOM: _send_packet(server_key, "RS:"+local_key)
		state.REGISTERED: _send_packet(server_key, "KA:"+session_id)
		state.PINGING: _ping_peers()
		state.CLOSE:  close_session()

# Send keepalive to server and ready signal to peers.
func _ping_peers() -> void:
	if is_host: _send_packet(server_key, "KA:"+session_id)
	for peer in peers:
		if peer.ready in ["", "local"]: _send_packet(peer.local_key, "RD:"+":".join(peer_names))
		if peer.ready in ["", "remote"]: _send_packet(peer.remote_key, "RD:"+":".join(peer_names))

### Packet Handlers

# HR # Registered as host with the matching server: recieve own remote key and session id.
func _host_registered(packet_key: String, packet_string: String) -> void:
	if is_random: is_host = true
	var packet_parts = packet_string.split(":")
	server_key = packet_key
	remote_key = packet_parts[0]
	session_id = packet_parts[1]
	start_session.emit(session_id)
	current_state = state.REGISTERED

# JR # Registered as client with the matching server: recieve remote key and local key for host.
func _join_registered(packet_key: String, packet_string: String) -> void:
	var packet_parts = packet_string.split(":")
	server_key = packet_key
	remote_key = packet_parts[0]
	for peer in peers: if peer.remote_key == packet_parts[1]: return
	peers.append({"remote_key": packet_parts[1], "local_key": packet_parts[2], "ready": "", "done": false})
	_ping_peers()
	current_state = state.PINGING

# BK # Matching server did not recognize the session id.
func _bad_key(packet_key: String, packet_string: String) -> void: 
	current_state = state.IDLE
	bad_session.emit(packet_string)

# NJ # New peer registered with the matching server for this session: recieve remote key and local key for client.
func _new_joiner(_packet_key: String, packet_string: String) -> void:
	var packet_parts = packet_string.split(":")
	for peer in peers: if peer.remote_key == packet_parts[0]: return
	peers.append({"remote_key": packet_parts[0], "local_key": packet_parts[1], "ready": "", "done": false})
	_ping_peers()
	current_state = state.PINGING

# RD # A peer is ready to start (UDP port open): recieve packet key that shows if the peer is local or remote.
func _peer_ready(packet_key: String, packet_string: String) -> void:
	_add_names(packet_string)
	for peer in peers: 
		if peer.local_key == packet_key: peer.ready = "local"
		elif peer.remote_key == packet_key: peer.ready = "remote"
	if is_host and is_random: 
		close_session()
		start_random.emit()

# JH # The host is ready to start (UDP hole punched). End session and signal to start normal MultiplayerPeer as client.
func _join_host(packet_key: String, _packet_string: String) -> void:
	if current_state == state.IDLE: return
	_send_packet(packet_key, "JD:DONE")
	client.close()
	timer.stop()
	var packet_addr = _key_to_addr(packet_key)
	start_client.emit(packet_addr[0], packet_addr[1], local_port)
	current_state = state.IDLE

# JD # The peers are all ready to start (UDP holes punched). End session and signal to start normal MultiplayerPeer as host.
func _join_done(packet_key: String, packet_string: String):
	if current_state == state.IDLE: return
	for peer in peers: if packet_key in [peer.local_key, peer.remote_key]: peer.done = true
	for peer in peers: if not peer.done: return
	client.close()
	timer.stop()
	start_server.emit(local_port)
	current_state = state.IDLE

### Helpers

# Convert key to network address.
func _key_to_addr(key: String) -> Array:
	var ip: String = ""
	for i in 4: ip += str(bigrams.find(key.substr(i*2, 2)))+"."
	ip = ip.left(-1)
	var port = 256 * bigrams.find(key.substr(8,2))
	port += bigrams.find(key.substr(10,2))
	return [ip, port]

# Convert network address to key.
func _addr_to_key(ip: String, port: int) -> String:
	var key: String = ""
	for num in ip.split("."):  key += bigrams[int(num)]
	@warning_ignore("integer_division")
	key += bigrams[port / 256]
	key += bigrams[port % 256]
	return key

# Add a new name to the peer names list. Useful for displaying a lobby elsewhere.
func _add_names(names: String) -> void:
	var list = names.split(":")
	for peer_name in list: if not peer_name in peer_names:
		peer_names.append(peer_name)
		new_name.emit(peer_name)
