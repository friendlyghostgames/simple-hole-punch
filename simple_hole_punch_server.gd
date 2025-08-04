class_name DVServer
extends Node

enum state {REGISTERED, HOSTING, JOINED}
var hosts: Dictionary = {}
var server_ip: String = ""
var server_port: int = 0
var server_key: String = ""
var server: PacketPeerUDP = PacketPeerUDP.new()
var bigrams: Array = ['cy','ah','jc','du','mw','wh','rv','yq','yy','sr','ss','tg','cv','gx','ia','ba','wa','bx','sm','co','ms','ea','to','rb','xr','vx','ua','fw','ri','ds','ji','bk','bb','sp','cc','gc','bu','ow','de','io','gm','hs','kq','as','fa','dx','wf','hy','pg','ug','db','jv','wq','ir','lm','lt','hm','on','iz','is','fx','my','ph','fd','vl','zw','sv','si','dp','jp','oa','cm','ws','jm','do','ot','gd','lr','ko','se','qn','rz','xh','mz','sn','af','wo','rf','je','nj','yn','tq','zu','xp','xv','nk','wr','tk','dq','ga','tz','bl','or','ui','dt','eo','ld','hr','uv','sw','gg','hd','bs','nx','jz','au','oj','tu','br','rc','vz','tw','nb','ay','dv','tb','kc','qu','qm','mi','it','va','sa','di','be','wy','gh','ki','sl','pq','ed','iv','er','yi','iq','ls','ur','kv','ln','hh','vj','en','im','vm','hi','bm','we','fz','xb','ne','ag','hc','ma','gt','yx','pl','cr','oh','gj','wx','gq','ti','fi','hf','xm','km','ul','lv','nh','kr','ef','ly','us','ge','ju','fs','qz','fn','np','cj','vn','ft','wz','jr','tf','ww','ab','za','og','lq','mm','xw','uk','so','mb','rp','zt','xc','ad','hg','gw','pu','kx','cf','yb','gs','gr','kb','oq','xq','dn','tv','rl','vo','xz','jk','yg','qy','fr','nl','ii','yc','dz','wu','od','ng','pd','fg','fj','fh','in','na','rt','hz','es','wt','he','gi','oo','bc','cw','yv','ky','pz','wm','wi']
var packet_handlers: Dictionary = {"HS": _host_session, "JS": _join_session, "RS": _random_session, "CS": _close_session, "KA": _keep_alive}
var timer: Timer = Timer.new()
var flush_timer = 60
var flush_period = 1200000

### Comms

func _ready() -> void:
	server_ip = OS.get_cmdline_user_args()[0]
	server_port = int(OS.get_cmdline_user_args()[1])
	if not server_ip.is_valid_ip_address(): get_tree().quit()
	else: server_key = _addr_to_key(server_ip, server_port)
	_push_log("SERVER KEY", server_key)
	var err = server.bind(server_port) #server.bind(server_port, public_ip)
	if err != OK: push_error("_ready failed to bind port server_port "+str(server_port)+" : "+str(err))
	add_child(timer)
	timer.start(flush_timer)
	timer.timeout.connect(_flush_hosts)

# Listen for incoming packets and call the associated packet handler.
func _process(_delta: float) -> void:
	if server.get_available_packet_count() == 0: return
	var packet_string = server.get_packet().get_string_from_ascii()
	var packet_key = _addr_to_key(server.get_packet_ip(), server.get_packet_port())
	if packet_string.left(2) in packet_handlers: packet_handlers[packet_string.left(2)].call(packet_key, packet_string.right(-3))

# Push a packet to a registered user.
func _send_packet(packet_key: String, packet_string: String):
	server.set_dest_address.callv(_key_to_addr(packet_key))
	var buffer = PackedByteArray()
	buffer.append_array(packet_string.to_utf8_buffer())
	server.put_packet(buffer)

### Packet Handlers

# Become a registered host and recieve remote key and host key.
func _host_session(packet_key: String, packet_string: String) -> void:
	var host_id = _session_id()
	for host in hosts: if packet_key == hosts[host].remote_key: host_id = host
	if not host_id in hosts: _push_log("STARTED", host_id)
	hosts[host_id] = {"remote_key": packet_key, "local_key": packet_string, "added": Time.get_ticks_msec()}
	_send_packet(packet_key, "HR:"+packet_key+":"+host_id)

# Join a registered host and recieve their remote key and local key.
func _join_session(packet_key: String, packet_string: String) -> void:
	var packet_parts = packet_string.split(":")
	var local_key = packet_parts[0]
	var session_id = packet_parts[1]
	if session_id in hosts: 
		_send_packet(hosts[session_id].remote_key, "NJ:"+packet_key+":"+local_key)
		_send_packet(packet_key, "JR:"+packet_key+":"+hosts[session_id].remote_key+":"+hosts[session_id].local_key)
	else: _send_packet(packet_key, "BK:"+session_id)

# Join a random session. If a random host is waiting, join them. Otherwise become a random host.
func _random_session(packet_key: String, packet_string: String) -> void:
	for host in hosts: if packet_key in [hosts[host].remote_key, hosts[host].random]: return
	for host in hosts: if hosts[host].random == "random": 
		hosts[host].random = packet_key
		_join_session(packet_key, packet_string+":"+host)
		return
	_host_session(packet_key, packet_string)
	for host in hosts: if hosts[host].remote_key == packet_key: hosts[host].random = "random"

# Complete a session once everyone has joined.
func _close_session(packet_key: String, packet_string: String) -> void:
	if packet_string in hosts and packet_key == hosts[packet_string].remote_key: 
		hosts.erase(packet_string)
		_push_log("COMPLETE", packet_string)

# Keepalive message to keep return path open.
func _keep_alive(_packet_key, _packet_string: String) -> void: pass

### Helpers

# Convert network address to key.
func _addr_to_key(ip: String, port: int) -> String:
	var key: String = ""
	for num in ip.split("."):  key += bigrams[int(num)]
	@warning_ignore("integer_division")
	key += bigrams[floor(port / 256)]
	key += bigrams[port % 256]
	return key

# Convert key to network address.
func _key_to_addr(key: String) -> Array:
	var ip: String = ""
	for i in 4: ip += str(bigrams.find(key.substr(i*2, 2)))+"."
	ip = ip.left(-1)
	var port = 256 * bigrams.find(key.substr(8,2))
	port += bigrams.find(key.substr(10,2))
	return [ip, port]

# Generate new session id.
func _session_id() -> String:
	var key = server_key
	key += bigrams[randi_range(0,255)] + bigrams[randi_range(0,255)]
	return key

# Flush unused hosts after flush period exceeded.
func _flush_hosts() -> void: 
	var current_ticks = Time.get_ticks_msec()
	var timed_out = []
	for host in hosts: if current_ticks - hosts[host].added > flush_period: timed_out.append(host)
	for to in timed_out: 
		hosts.erase(to)
		_push_log("CANCELLED", to)

# Output log messages.
func _push_log(flag: String, id: String) -> void: print(flag+" | "+id+" | "+Time.get_datetime_string_from_system())
