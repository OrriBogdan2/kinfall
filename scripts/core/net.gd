extends Node
## Online play over the artifact's room (or a BroadcastChannel between browser tabs when testing).
## Each player's game owns its own hunter and kin; the host's game owns monsters, bots and loot.
## Owners send compact snapshots; anyone who hits something they don't own sends the hit to its owner.

signal peers_changed
signal message(topic: String, data, from: String)

var mode := ""                # "" offline, "room" or "tabs"
var me := ""
var peers := {}               # peer id -> presence dict
var my_presence := {}
var in_match := false
var host := ""
var match_name := ""
var m: Node = null            # the Match while online
var out_hits: Array = []
var out_events: Array = []
var send_t := 0.0
var host_send_t := 0.0
var seen := {}                # nid -> last time we heard about it
var _msg_cb = null
var _peers_cb = null
var started := false

func online() -> bool:
	return in_match and mode != ""

func start() -> void:
	if started or not Bridge.net_available():
		return
	started = true
	_msg_cb = Bridge.make_callback(_on_js_msg)
	_peers_cb = Bridge.make_callback(_on_js_peers)
	var p = Bridge.js.netStart(_msg_cb, _peers_cb)
	# netStart is async on the page; ask who we are a moment later
	await get_tree().create_timer(1.5).timeout
	mode = "room" if Bridge.js.hasRoom() else "tabs"
	me = str(Bridge.js.whoami())

func set_presence(d: Dictionary) -> void:
	my_presence = d
	if Bridge.js:
		Bridge.js.presence(JSON.stringify(d))

func lobby_emit(topic: String, d) -> void:
	if Bridge.js:
		Bridge.js.emit(topic, JSON.stringify(d))

func _on_js_peers(args) -> void:
	var parsed = JSON.parse_string(str(args[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	me = str(parsed.get("me", me))
	peers.clear()
	for p in parsed.get("peers", []):
		peers[str(p["id"])] = p["p"]
	peers_changed.emit()

func _on_js_msg(args) -> void:
	var parsed = JSON.parse_string(str(args[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var topic: String = parsed.get("t", "")
	var from: String = str(parsed.get("f", ""))
	var data = parsed.get("d", null)
	if topic in ["st", "hit", "ev"]:
		if m and is_instance_valid(m) and in_match:
			m.net_receive(topic, data, from)
		return
	message.emit(topic, data, from)

# ------------------------------------------------------------------ match
func begin_match(name: String, host_peer: String, match_node: Node) -> void:
	match_name = name
	host = host_peer
	m = match_node
	in_match = true
	out_hits.clear(); out_events.clear(); seen.clear()
	if Bridge.js:
		Bridge.js.joinMatch(name)

func end_match() -> void:
	flush()
	in_match = false
	m = null
	if Bridge.js:
		Bridge.js.leaveMatch()

func is_host() -> bool:
	return me == host

func owner_of(nid: String) -> String:
	# player-owned ids look like "P<peer>" and "P<peer>k"; everything else belongs to the host
	if nid.begins_with("P"):
		return nid.substr(1).trim_suffix("k")
	return host

func owns(nid: String) -> bool:
	return owner_of(nid) == me

func hit(target_nid: String, d: Array) -> void:
	out_hits.append([target_nid] + d)

func event(e: Array) -> void:
	out_events.append(e)

func _emit(topic: String, d) -> void:
	if Bridge.js:
		Bridge.js.matchEmit(topic, JSON.stringify(d))

func flush() -> void:
	if out_hits.size() > 0:
		_chunks("hit", out_hits)
		out_hits = []
	if out_events.size() > 0:
		_chunks("ev", out_events)
		out_events = []

## Splits a list into messages under the 4KB limit. A header, if given, starts every message.
func _chunks(topic: String, items: Array, header = null) -> void:
	var cur: Array = [] if header == null else [header]
	var size := 40
	for it in items:
		var s := JSON.stringify(it).length() + 1
		if size + s > 3600 and cur.size() > (0 if header == null else 1):
			_emit(topic, cur)
			cur = [] if header == null else [header]
			size = 40
		cur.append(it); size += s
	if cur.size() > (0 if header == null else 1):
		_emit(topic, cur)

func tick(dt: float) -> void:
	if not online() or m == null:
		return
	send_t -= dt
	host_send_t -= dt
	if send_t <= 0.0:
		send_t = 0.1
		var mine: Array = m.net_snapshot(true)
		if mine.size() > 0:
			_chunks("st", mine, {"t": m.time})
		flush()
	if is_host() and host_send_t <= 0.0:
		host_send_t = 0.15
		var world_ents: Array = m.net_snapshot(false)
		if world_ents.size() > 0:
			_chunks("st", world_ents, {"t": m.time})
