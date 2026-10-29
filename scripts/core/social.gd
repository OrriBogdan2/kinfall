extends Node
## Everything players share: island snapshots others can visit, gifts, guilds and their projects,
## and the town's market and notice board. Backed by the page's shared store in the web version
## (see tools/shell.html); unavailable in desktop builds, where these features say so instead.
##
## Everything read from the store was written by other players, so it is untrusted: every read
## goes through the clean_* functions below before the game touches it, and nothing that adds
## gems or items to this save is taken on the store's word alone.

signal ready_changed(ok: bool)

var ok := false            # the store answered
var mode := ""             # "db" (shared with everyone the page is shared with) or "local" (this browser)
var me := ""
var is_owner := false      # the artifact's owner (admin tools are theirs)
var guild: Dictionary = {}         # my guild, cleaned, plus "id"
var guild_progress: Dictionary = {} # project -> gems put in
var _keep: Array = []
var _last_publish := -1e9
var _busy := {}                     # operations in flight, so a double click can't run one twice

const PROJECTS := {
	"hall": {"name": "Guild Hall", "goal": 600, "perk": "+10% gems from every expedition you make it out of."},
	"forge": {"name": "Forge", "goal": 500, "perk": "Start every expedition with one extra tonic."},
	"shrine": {"name": "Kin Shrine", "goal": 500, "perk": "Your partner gains 1 extra trust after every expedition."},
	"lighthouse": {"name": "Lighthouse", "goal": 800, "perk": "Glide 25% longer."},
}
const STRANDED_DAYS := 3.0          # a listing that vanished without a sale is handed back after this

func _ready() -> void:
	if not OS.has_feature("web") or JavaScriptBridge.get_interface("kinBridge") == null:
		return
	_call("storeInit", [], func(txt: String):
		var d = JSON.parse_string(txt)
		if typeof(d) == TYPE_DICTIONARY and txt_of(d.get("me")) != "":
			ok = true
			mode = txt_of(d.get("mode"))
			me = txt_of(d.get("me"))
			is_owner = d.get("owner", false) == true
			ready_changed.emit(true)
			refresh_guild())

func available() -> bool:
	return ok

func busy(op: String) -> bool:
	return _busy.has(op)

# ------------------------------------------------------------------ safe reading of untrusted values
static func txt_of(v, def := "", n := 64) -> String:
	if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
		return String(v).substr(0, n)
	return def

static func num_of(v, def := 0.0) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f := float(v)
		if is_finite(f):
			return clampf(f, -1e12, 1e12)
	return def

static func int_of(v, def := 0) -> int:
	return int(num_of(v, def))

static func dict_of(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func arr_of(v) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []

## A name or line someone else typed: one line, printable, no markup characters.
static func say_of(v, def := "Someone", n := 16) -> String:
	var t := txt_of(v, "", 400)
	var out := ""
	for ch in t:
		var c := ch.unicode_at(0)
		if c < 32 or c == 127 or "{}<>[]`\\\"".contains(ch):
			out += " " if c == 10 or c == 13 or c == 9 else ""
		else:
			out += ch
	out = out.strip_edges().substr(0, n)
	return out if out != "" else def

# ------------------------------------------------------------------ plumbing
func _call(method: String, args: Array, cb: Callable) -> void:
	var js = JavaScriptBridge.get_interface("kinBridge")
	if js == null:
		cb.call_deferred("")
		return
	var holder := []
	var f := JavaScriptBridge.create_callback(func(a):
		_keep.erase(holder[0])
		cb.call(str(a[0]) if a.size() > 0 else ""))
	holder.append(f)
	_keep.append(f)
	# named calls only: Object.call() on a JavaScriptObject would look for a JS method called "call"
	match method:
		"storeInit": js.storeInit(f)
		"dbGet": js.dbGet(args[0], f)
		"dbSet": js.dbSet(args[0], args[1], f)
		"dbDel": js.dbDel(args[0], f)
		"dbAdd": js.dbAdd(args[0], args[1], f)
		"dbQuery": js.dbQuery(args[0], args[1], f)
		"dbClaim": js.dbClaim(args[0], f)

func get_doc(path: String, cb: Callable) -> void:
	_call("dbGet", [path], func(t: String):
		var d = JSON.parse_string(t) if t != "" else null
		cb.call(d if typeof(d) == TYPE_DICTIONARY else {}))

func set_doc(path: String, data: Dictionary, cb := Callable()) -> void:
	_call("dbSet", [path, JSON.stringify(data)], func(t: String):
		if cb.is_valid(): cb.call(t == "ok"))

func del_doc(path: String, cb := Callable()) -> void:
	_call("dbDel", [path], func(t: String):
		if cb.is_valid(): cb.call(t == "ok"))

func add_doc(col: String, data: Dictionary, cb := Callable()) -> void:
	_call("dbAdd", [col, JSON.stringify(data)], func(t: String):
		if cb.is_valid(): cb.call(t))

## where: [[field, op, value], ...]. cb gets [{id: String, data: Dictionary}] (shapes checked, contents not).
func query(col: String, where: Array, order := "", dir := "asc", limit := 50, cb := Callable()) -> void:
	_call("dbQuery", [col, JSON.stringify({"where": where, "order": order, "dir": dir, "limit": limit})], func(t: String):
		var d = JSON.parse_string(t) if t != "" else []
		var rows: Array = []
		for r in arr_of(d):
			var id := txt_of(dict_of(r).get("id"))
			if id != "" and not id.contains("/"):
				rows.append({"id": id, "data": dict_of(dict_of(r).get("data"))})
		if cb.is_valid(): cb.call(rows))

func claim(path: String, cb: Callable) -> void:
	_call("dbClaim", [path], func(t: String):
		var d = JSON.parse_string(t) if t != "" and t != "0" else null
		cb.call(d if typeof(d) == TYPE_DICTIONARY else {}))

func now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0

## Runs step(item, next) for each item in turn, then done().
func _each(items: Array, step: Callable, done: Callable) -> void:
	if items.is_empty():
		done.call()
		return
	var rest := items.slice(1)
	step.call(items[0], func(): _each(rest, step, done))

func _save_dict(key: String) -> Dictionary:
	if typeof(Save.d.get(key)) != TYPE_DICTIONARY:
		Save.d[key] = {}
	return Save.d[key]

# ------------------------------------------------------------------ my island, for visitors
## Publishes a snapshot of your island so friends can visit. Throttled.
func publish_profile(force := false) -> void:
	if not ok or Save.d["roster"].is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	if not force and t - _last_publish < 20.0:
		return
	_last_publish = t
	set_doc("profiles/" + me, profile_doc())

## What other players see of your island when they visit.
static func profile_doc() -> Dictionary:
	var roster: Array = []
	for r in Save.d["roster"].slice(0, 12):
		Evo.ensure(r)
		roster.append({"uid": r["uid"], "species": r["species"], "name": r["name"], "level": int(r["level"]),
			"trust": int(r["trust"]), "forms": r["forms"], "muts": r["muts"]})
	var d := {
		"name": Save.d.get("name", "Hunter"), "hero": Save.d.get("hero", ""), "weapon": Save.d.get("weapon", ""),
		"active": Save.d.get("active", ""), "roster": roster,
		"buildings": Save.d.get("buildings", []), "bridges": Save.d.get("bridges", []),
		"plots": Save.d["plots"], "gh_plots": Save.d.get("gh_plots", []),
		"extracts": int(Save.d.get("extracts", 0)), "matches": int(Save.d.get("matches", 0)),
		"guild": String(Save.d.get("guild_id", "")), "updated": Time.get_unix_time_from_system() * 1000.0,
		"decor": Save.d.get("decor", {}).get("house", []),
	}
	return d

## cb gets [{id, d}] with d already cleaned (see clean_island).
func list_islands(cb: Callable) -> void:
	query("profiles", [], "updated", "desc", 40, func(rows: Array):
		var out: Array = []
		for r in rows:
			if r["id"] != me:
				out.append({"id": r["id"], "d": clean_island(r["data"])})
		cb.call(out))

# ------------------------------------------------------------------ gifts and visits
func send_gift(to: String, kind: String, key: String, cb := Callable()) -> void:
	add_doc("gifts", {"to": to, "from": me, "from_name": Save.d.get("name", "Hunter"), "kind": kind, "key": key, "n": 1, "t": now_ms()}, func(id: String):
		if cb.is_valid(): cb.call(id != ""))

## Collects gifts and visits left on your island while you were away. cb gets a list of lines.
## Every gift is one item, a sender counts for at most three per visit home, and a visitor can
## only make each kin happier once a day.
func collect_gifts(cb: Callable) -> void:
	if not ok or busy("gifts"):
		cb.call([])
		return
	_busy["gifts"] = true
	query("gifts", [["to", "==", me]], "", "asc", 40, func(rows: Array):
		var lines: Array = []
		var per_sender := {}
		var items := 0
		var pets := _save_dict("pets_seen")
		var today := int(Time.get_unix_time_from_system() / 86400.0)
		for r in rows:
			del_doc("gifts/" + r["id"])     # gone first, so a bad one can never get stuck in the inbox
			var g: Dictionary = r["data"]
			var from := txt_of(g.get("from"))
			var who := say_of(g.get("from_name"))
			var key := txt_of(g.get("key"))
			per_sender[from] = int(per_sender.get(from, 0)) + 1
			if from == "" or from == me or int(per_sender[from]) > 3:
				continue
			match txt_of(g.get("kind")):
				"seed", "crop":
					if not Data.CROPS.has(key) or items >= 10:
						continue
					items += 1
					if txt_of(g.get("kind")) == "seed":
						Save.add_seed(key, 1)
						lines.append("%s left you a %s seed." % [who, Data.CROPS[key]["name"]])
					else:
						Save.d["crops"][key] = int(Save.d["crops"].get(key, 0)) + 1
						lines.append("%s left you a %s." % [who, Data.CROPS[key]["name"]])
				"pet":
					var k := Save.kin(key)
					var pkey := from.substr(0, 40) + ":" + key
					if k.is_empty() or int(pets.get(pkey, -1)) == today:
						continue
					pets[pkey] = today
					Save.remember(k, "visited", "got a scratch from %s, who came to visit" % who, 1.0)
					lines.append("%s visited and petted %s." % [who, k["name"]])
		# forget old pet days so the save doesn't grow forever
		for pk in pets.keys():
			if today - int(pets[pk]) > 2: pets.erase(pk)
		if lines.size() > 0:
			Save.save_game()
		_busy.erase("gifts")
		cb.call(lines))

# ------------------------------------------------------------------ guilds
## Your guild lives in your own save; the store only has to describe it.
func my_guild_id() -> String:
	return String(Save.d.get("guild_id", ""))

func refresh_guild(cb := Callable()) -> void:
	if not ok:
		if cb.is_valid(): cb.call()
		return
	if not Save.d.has("guild_id"):
		# saves from before guilds were kept locally: take it from the published profile once
		get_doc("profiles/" + me, func(p: Dictionary):
			Save.d["guild_id"] = txt_of(p.get("guild"))
			refresh_guild(cb))
		return
	var gid := my_guild_id()
	if gid == "":
		guild = {}
		guild_progress = {}
		_store_perks()
		if cb.is_valid(): cb.call()
		return
	get_guild(gid, func(g: Dictionary):
		if g.is_empty():
			# missing or unreachable: stay in it under the name we last saw
			g = clean_guild({"name": Save.d.get("guild_name", "Your guild")})
		guild = g
		guild["id"] = gid
		Save.d["guild_name"] = g["name"]
		load_progress(gid, guild, func(prog: Dictionary):
			guild_progress = prog
			_store_perks()
			if cb.is_valid(): cb.call()))

func get_guild(gid: String, cb: Callable) -> void:
	get_doc("guilds/" + gid, func(g: Dictionary):
		cb.call(clean_guild(g) if not g.is_empty() else {}))

## How far along each project is. Only current members count, nobody counts for more than a
## project needs, and a project anyone has seen finished stays finished.
func load_progress(gid: String, gdoc: Dictionary, cb: Callable) -> void:
	query("profiles", [["guild", "==", gid]], "", "asc", 60, func(prows: Array):
		var members := {}
		for r in prows: members[r["id"]] = true
		query("contrib", [["guild", "==", gid]], "", "asc", 100, func(rows: Array):
			var prog := {}
			for k in PROJECTS: prog[k] = 0
			for r in rows:
				if not members.has(r["id"]):
					continue
				var am := dict_of(r["data"].get("amounts"))
				for k in PROJECTS:
					prog[k] += clampi(int_of(am.get(k)), 0, int(PROJECTS[k]["goal"]))
			var built: Array = arr_of(gdoc.get("built")).duplicate()
			var mine := gid == my_guild_id()
			if mine:
				for k in arr_of(_save_dict("guild_built").get(gid)):
					if PROJECTS.has(k) and not built.has(k): built.append(k)
			var newly := false
			for k in PROJECTS:
				if built.has(k):
					prog[k] = maxi(prog[k], int(PROJECTS[k]["goal"]))
				elif prog[k] >= int(PROJECTS[k]["goal"]):
					built.append(k)
					newly = true
			if mine:
				_save_dict("guild_built")[gid] = built
				if newly and not gdoc.is_empty():
					var g2 := gdoc.duplicate()
					g2.erase("id")
					g2["built"] = built
					set_doc("guilds/" + gid, g2)
			cb.call(prog)))

func project_done(k: String) -> bool:
	return not guild.is_empty() and int(guild_progress.get(k, 0)) >= int(PROJECTS[k]["goal"])

## Guild perks are kept in the save so expeditions use them even without a connection.
func _store_perks() -> void:
	var perks: Array = []
	for k in PROJECTS:
		if project_done(k): perks.append(k)
	Save.d["guild_perks"] = perks
	Save.save_game()

func create_guild(name_txt: String, motto: String, cb: Callable) -> void:
	if busy("guild"):
		return
	_busy["guild"] = true
	var gid := "g" + str(Time.get_ticks_usec() % 100000000) + str(randi() % 1000)
	set_doc("guilds/" + gid, {"name": say_of(name_txt, "Guild", 24), "motto": say_of(motto, "", 60), "founder": me, "created": now_ms(),
		"color": Color.from_hsv(randf(), 0.5, 0.9).to_html(false), "built": []}, func(okk: bool):
		_busy.erase("guild")
		if not okk:
			cb.call(false)
			return
		join_guild(gid, cb))

func join_guild(gid: String, cb: Callable) -> void:
	if busy("guild"):
		return
	_busy["guild"] = true
	Save.d["guild_id"] = gid
	guild = {"id": gid}
	_last_publish = -1e9
	publish_profile(true)
	get_doc("contrib/" + me, func(c: Dictionary):
		# your running total belongs to one guild at a time
		var after := func():
			refresh_guild(func():
				_busy.erase("guild")
				cb.call(true))
		if txt_of(c.get("guild")) != gid:
			set_doc("contrib/" + me, {"guild": gid, "amounts": {}, "updated": now_ms()}, func(_o): after.call())
		else:
			after.call())

## Leaving keeps what you put in with the guild you gave it to (it stops counting until you're back).
func leave_guild(cb: Callable) -> void:
	Save.d["guild_id"] = ""
	guild = {}
	guild_progress = {}
	_store_perks()
	_last_publish = -1e9
	publish_profile(true)
	cb.call_deferred()

## cb gets [{id, g}] with g cleaned.
func list_guilds(cb: Callable) -> void:
	query("guilds", [], "created", "desc", 30, func(rows: Array):
		cb.call(rows.map(func(r): return {"id": r["id"], "g": clean_guild(r["data"])})))

## cb gets [{id, d}] with d cleaned.
func guild_members(gid: String, cb: Callable) -> void:
	query("profiles", [["guild", "==", gid]], "", "asc", 24, func(rows: Array):
		cb.call(rows.map(func(r): return {"id": r["id"], "d": clean_island(r["data"])})))

## Puts gems into a guild project. Each member keeps their own running total, so nobody overwrites anybody.
func contribute(project: String, gems: int, cb: Callable) -> void:
	if guild.is_empty() or not PROJECTS.has(project) or gems <= 0 or int(Save.d["gems"]) < gems or busy("contrib"):
		cb.call(false)
		return
	_busy["contrib"] = true
	Save.d["gems"] = int(Save.d["gems"]) - gems          # held now, handed back if the write fails
	var gid: String = guild["id"]
	get_doc("contrib/" + me, func(c: Dictionary):
		var am := {}
		if txt_of(c.get("guild")) == gid:
			var old := dict_of(c.get("amounts"))
			for k in PROJECTS: am[k] = maxi(0, int_of(old.get(k)))
		am[project] = int(am.get(project, 0)) + gems
		set_doc("contrib/" + me, {"guild": gid, "amounts": am, "updated": now_ms()}, func(okk: bool):
			_busy.erase("contrib")
			if okk:
				guild_progress[project] = int(guild_progress.get(project, 0)) + gems
				if int(guild_progress[project]) >= int(PROJECTS[project]["goal"]):
					refresh_guild()          # records the finished project for everyone
				_store_perks()
			else:
				Save.d["gems"] = int(Save.d["gems"]) + gems
				Save.save_game()
			cb.call(okk)))

# ------------------------------------------------------------------ market and notices
## Fair prices for one item: listings outside this range are ignored by every player.
static func price_range(kind: String, key: String) -> Vector2i:
	var base := int(Data.CROPS[key]["price"]) * (2 if kind == "crop" else 1)
	return Vector2i(maxi(1, base / 2), base * 3)

## A kin's asking price range, by level: listings outside it are ignored by everyone.
static func kin_price_range(level: int) -> Vector2i:
	var base := 40 + clampi(level, 1, 30) * 20
	return Vector2i(base / 2, base * 3)

static func kin_price(level: int) -> int:
	return 40 + clampi(level, 1, 30) * 20

## Only the parts of a kin that are safe to pass between players: species, name, level, how it's
## grown, its personality. Anything else is rebuilt fresh for the new owner.
static func clean_kin(v) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	var sp := txt_of(d.get("species"))
	if not Data.KIN.has(sp):
		return {}
	var out := {"species": sp, "name": say_of(d.get("name"), "Kin", 16), "level": clampi(int_of(d.get("level"), 1), 1, 30),
		"shimmer": d.get("shimmer", false) == true, "traits": {}, "forms": [], "aff": {}}
	var tr = d.get("traits", {})
	if typeof(tr) == TYPE_DICTIONARY:
		for k in Data.KIN[sp]["traits"]:
			out["traits"][k] = clampf(num_of(tr.get(k), 0.5), 0.05, 0.95)
	var fm = d.get("forms", [])
	if typeof(fm) == TYPE_ARRAY:
		for f in fm.slice(0, 3):
			if typeof(f) == TYPE_STRING and Evo.AFF.has(f): out["forms"].append(f)
	var af = d.get("aff", {})
	if typeof(af) == TYPE_DICTIONARY:
		for a in Evo.AFF:
			out["aff"][a] = clampf(num_of(af.get(a), 0.0), 0.0, 400.0)
	var acc := txt_of(d.get("acc"))
	if acc != "" and Data.ACCS.has(acc): out["acc"] = acc
	return out

## A full kin record for its new owner, built from a cleaned one.
static func kin_for_buyer(c: Dictionary, seller_name: String) -> Dictionary:
	var rec := Save.new_kin(c["species"], c["name"])
	rec["level"] = int(c["level"])
	rec["shimmer"] = c["shimmer"]
	for k in c["traits"]: rec["traits"][k] = c["traits"][k]
	Evo.ensure(rec)
	rec["forms"] = (c["forms"] as Array).duplicate()
	for a in c["aff"]: rec["aff"][a] = c["aff"][a]
	if c.has("acc"): rec["acc"] = c["acc"]
	rec["trust"] = 25.0           # it doesn't know you yet
	Save.remember(rec, "market", "was bought from %s at the market" % seller_name, 0.0)
	return rec

static func clean_listing(d: Dictionary) -> Dictionary:
	var kind := txt_of(d.get("kind"))
	if kind == "kin":
		var ck := clean_kin(d.get("kin"))
		var sel := txt_of(d.get("seller"))
		if ck.is_empty() or sel == "" or ck["species"] != txt_of(d.get("key")):
			return {}
		var kp := int_of(d.get("price"))
		var kr := kin_price_range(int(ck["level"]))
		if kp < kr.x or kp > kr.y:
			return {}
		return {"kind": "kin", "key": ck["species"], "n": 1, "price": kp, "seller": sel, "seller_name": say_of(d.get("seller_name")), "t": num_of(d.get("t")), "kin": ck}
	var key := txt_of(d.get("key"))
	var seller := txt_of(d.get("seller"))
	if not (kind == "seed" or kind == "crop") or not Data.CROPS.has(key) or seller == "" or int_of(d.get("n")) != 1:
		return {}
	var price := int_of(d.get("price"))
	var pr := price_range(kind, key)
	if price < pr.x or price > pr.y:
		return {}
	return {"kind": kind, "key": key, "n": 1, "price": price, "seller": seller, "seller_name": say_of(d.get("seller_name")), "t": num_of(d.get("t"))}

## cb gets [{id, l}] with l cleaned; anything malformed is left out.
func list_market(cb: Callable) -> void:
	query("market", [], "t", "desc", 40, func(rows: Array):
		var out: Array = []
		for r in rows:
			var l := clean_listing(r["data"])
			if not l.is_empty(): out.append({"id": r["id"], "l": l})
		cb.call(out))

func sell(kind: String, key: String, price: int, cb: Callable) -> void:
	if not Data.CROPS.has(key) or not (kind == "seed" or kind == "crop") or busy("market"):
		cb.call(false)
		return
	var store: Dictionary = Save.d["seeds"] if kind == "seed" else Save.d["crops"]
	var pr := price_range(kind, key)
	if int(store.get(key, 0)) < 1 or price < pr.x or price > pr.y:
		cb.call(false)
		return
	_busy["market"] = true
	store[key] = int(store[key]) - 1          # held while it's listed
	add_doc("market", {"seller": me, "seller_name": Save.d.get("name", "Hunter"), "kind": kind, "key": key, "n": 1, "price": price, "t": now_ms()}, func(id: String):
		_busy.erase("market")
		if id == "":
			store[key] = int(store.get(key, 0)) + 1
			Save.save_game()
			cb.call(false)
			return
		# remembered here: only real sales of things this save listed ever pay out
		_save_dict("listings")[id] = {"price": price, "kind": kind, "key": key, "t": now_ms()}
		Save.save_game()
		cb.call(true))

## Puts one of your kin up for sale. It leaves your farm while it's listed (it waits at the
## market) and comes back if you take the listing down.
func sell_kin(uid: String, price: int, cb: Callable) -> void:
	var rec := Save.kin(uid)
	if rec.is_empty() or busy("market") or Save.d["roster"].size() <= 1:
		cb.call(false)
		return
	var ck := clean_kin(rec)
	var pr := kin_price_range(int(ck["level"]))
	if price < pr.x or price > pr.y:
		cb.call(false)
		return
	_busy["market"] = true
	Save.d["roster"].erase(rec)
	if String(Save.d.get("active", "")) == uid: Save.d["active"] = ""
	if String(Save.d.get("active2", "")) == uid: Save.d["active2"] = ""
	add_doc("market", {"seller": me, "seller_name": Save.d.get("name", "Hunter"), "kind": "kin", "key": ck["species"], "n": 1, "price": price, "kin": ck, "t": now_ms()}, func(id: String):
		_busy.erase("market")
		if id == "":
			Save.d["roster"].append(rec)
			Save.save_game()
			cb.call(false)
			return
		# the full record waits in your save, so taking it back returns exactly your kin
		_save_dict("listings")[id] = {"price": price, "kind": "kin", "key": ck["species"], "rec": rec, "t": now_ms()}
		Save.save_game()
		cb.call(true))

func buy(listing_id: String, cb: Callable) -> void:
	if busy("market"):
		cb.call("")
		return
	_busy["market"] = true
	claim("market/" + listing_id, func(raw: Dictionary):
		var l := clean_listing(raw)
		if l.is_empty() or l["seller"] == me or int(Save.d["gems"]) < int(l["price"]) or (l["kind"] == "kin" and Save.d["roster"].size() >= 12):
			_busy.erase("market")
			cb.call("")
			return
		var price: int = l["price"]
		Save.d["gems"] = int(Save.d["gems"]) - price          # held until the listing is gone
		var what := ""
		if l["kind"] == "kin": what = "%s the %s" % [l["kin"]["name"], Data.KIN[l["key"]]["name"]]
		else: what = ("%s seed" if l["kind"] == "seed" else "%s") % Data.CROPS[l["key"]]["name"]
		# the payout goes first: the seller only honours it once the listing has disappeared
		add_doc("payouts", {"to": l["seller"], "lid": listing_id, "gems": price, "t": now_ms()}, func(pid: String):
			if pid == "":
				_busy.erase("market")
				Save.d["gems"] = int(Save.d["gems"]) + price
				cb.call("")
				return
			del_doc("market/" + listing_id, func(okk: bool):
				_busy.erase("market")
				if okk:
					if l["kind"] == "kin":
						var nk := kin_for_buyer(l["kin"], String(l["seller_name"]))
						Save.d["roster"].append(nk)
						Care.dex_mark(nk["species"], "caught")
					elif l["kind"] == "seed": Save.add_seed(l["key"], 1)
					else: Save.d["crops"][l["key"]] = int(Save.d["crops"].get(l["key"], 0)) + 1
				else:
					Save.d["gems"] = int(Save.d["gems"]) + price
				Save.save_game()
				cb.call(what if okk else ""))))

## Takes back something you listed and nobody bought yet. What comes back is what your save
## remembers putting up, never what the store says.
func unlist(listing_id: String, cb: Callable) -> void:
	var mine: Dictionary = _save_dict("listings").get(listing_id, {})
	if mine.is_empty() or busy("market"):
		cb.call(false)
		return
	_busy["market"] = true
	claim("market/" + listing_id, func(l: Dictionary):
		if l.is_empty():
			_busy.erase("market")
			cb.call(false)        # already sold (the payout will come) or gone
			return
		del_doc("market/" + listing_id, func(okk: bool):
			_busy.erase("market")
			if okk:
				_refund(listing_id)
			cb.call(okk)))

func _refund(listing_id: String) -> void:
	var listings := _save_dict("listings")
	var m: Dictionary = listings.get(listing_id, {})
	listings.erase(listing_id)
	var key := String(m.get("key", ""))
	if m.get("kind", "") == "kin":
		var rec = m.get("rec", {})
		if typeof(rec) == TYPE_DICTIONARY and not rec.is_empty():
			Save.d["roster"].append(rec)
	elif Data.CROPS.has(key):
		if m.get("kind", "") == "seed": Save.add_seed(key, 1)
		else: Save.d["crops"][key] = int(Save.d["crops"].get(key, 0)) + 1
	Save.save_game()

## Pays you for things that sold. A payout only counts for a listing this save made, at the price
## it set, and only once that listing is really gone. Listings that vanished without a sale come
## back after a few days.
func collect_payouts(cb: Callable) -> void:
	if not ok or busy("payouts"):
		cb.call(0)
		return
	_busy["payouts"] = true
	var listings := _save_dict("listings")
	var total := [0]
	query("payouts", [["to", "==", me]], "", "asc", 40, func(rows: Array):
		var paid := {}
		_each(rows, func(r: Dictionary, next: Callable):
			var lid := txt_of(r["data"].get("lid"))
			if not listings.has(lid) or paid.has(lid):
				del_doc("payouts/" + r["id"])
				next.call()
				return
			get_doc("market/" + lid, func(still: Dictionary):
				if still.is_empty():
					total[0] += maxi(0, int(listings[lid].get("price", 0)))
					listings.erase(lid)
					paid[lid] = true
					del_doc("payouts/" + r["id"])
				next.call()),
		func():
			var old: Array = []
			for lid in listings.keys():
				if now_ms() - float(listings[lid].get("t", now_ms())) > STRANDED_DAYS * 86400000.0:
					old.append(lid)
			_each(old.slice(0, 10), func(lid: String, next: Callable):
				get_doc("market/" + lid, func(still: Dictionary):
					if still.is_empty(): _refund(lid)
					next.call()),
			func():
				if total[0] > 0:
					Save.d["gems"] = int(Save.d["gems"]) + total[0]
				Save.save_game()
				_busy.erase("payouts")
				cb.call(total[0]))))

static func clean_notice(d: Dictionary) -> Dictionary:
	var text := say_of(d.get("text"), "", 140)
	if text == "":
		return {}
	return {"name": say_of(d.get("name")), "text": text, "by": txt_of(d.get("by")), "t": num_of(d.get("t"))}

## cb gets [{id, n}] with n cleaned.
func list_notices(cb: Callable) -> void:
	query("notices", [], "t", "desc", 20, func(rows: Array):
		var out: Array = []
		for r in rows:
			var n := clean_notice(r["data"])
			if not n.is_empty(): out.append({"id": r["id"], "n": n})
		cb.call(out))

func post_notice(text: String, cb: Callable) -> void:
	var t := say_of(text, "", 140)
	if t == "" or busy("notice"):
		cb.call(false)
		return
	_busy["notice"] = true
	add_doc("notices", {"by": me, "name": Save.d.get("name", "Hunter"), "text": t, "t": now_ms()}, func(id: String):
		_busy.erase("notice")
		cb.call(id != "")
		# keep the board short: drop my own notes past the newest 40
		query("notices", [], "t", "desc", 60, func(rows: Array):
			for i in range(40, rows.size()):
				if txt_of(rows[i]["data"].get("by")) == me: del_doc("notices/" + rows[i]["id"])))

# ------------------------------------------------------------------ cleaning
static func clean_guild(d: Dictionary) -> Dictionary:
	var col := txt_of(d.get("color"), "", 8)
	var built: Array = []
	for k in arr_of(d.get("built")):
		if PROJECTS.has(k) and not built.has(k): built.append(String(k))
	return {"name": say_of(d.get("name"), "Guild", 24), "motto": say_of(d.get("motto"), "", 60),
		"color": col if col.is_valid_html_color() else "f2a24a", "founder": txt_of(d.get("founder")),
		"created": num_of(d.get("created")), "built": built}

## Another player's island snapshot is untrusted data: keep only what drawing it needs, in safe shapes.
static func clean_island(d: Dictionary) -> Dictionary:
	var roster: Array = []
	for rv in arr_of(d.get("roster")):
		var r := dict_of(rv)
		var sp := txt_of(r.get("species"))
		if not Data.KIN.has(sp):
			continue
		var forms: Array = []
		for f in arr_of(r.get("forms")):
			if Evo.AFF.has(f): forms.append(String(f))
		var muts: Array = []
		for mv in arr_of(r.get("muts")):
			var m := dict_of(mv)
			var mid := txt_of(m.get("id")); var aff := txt_of(m.get("aff"))
			if Evo.PART_NAMES.has(mid) and Evo.AFF.has(aff):
				muts.append({"id": mid, "lv": clampi(int_of(m.get("lv"), 1), 1, 5), "aff": aff})
		roster.append({"uid": txt_of(r.get("uid"), "", 24), "species": sp, "name": say_of(r.get("name"), "Kin", 14),
			"level": clampi(int_of(r.get("level"), 1), 1, 999), "trust": clampf(num_of(r.get("trust"), 50.0), 0.0, 100.0),
			"forms": forms.slice(0, 50), "muts": muts.slice(0, 40), "traits": Data.KIN[sp]["traits"].duplicate(), "memory": []})
		if roster.size() >= 12:
			break
	var plots := func(src) -> Array:
		var out: Array = []
		for pv in arr_of(src):
			if out.size() >= 8: break
			var p := dict_of(pv)
			var c := txt_of(p.get("crop"))
			out.append({"crop": c if Data.CROPS.has(c) else "", "stage": clampi(int_of(p.get("stage")), 0, 9)})
		return out
	var pick := func(src, table: Dictionary) -> Array:
		var out: Array = []
		for x in arr_of(src):
			var k := txt_of(x)
			if table.has(k) and not out.has(k): out.append(k)
		return out
	var hero := txt_of(d.get("hero"))
	var gh: Array = plots.call(d.get("gh_plots"))
	return {"name": say_of(d.get("name"), "Hunter", 16), "active": txt_of(d.get("active"), "", 24), "roster": roster,
		"hero": hero if Data.HEROES.has(hero) else "sage", "buildings": pick.call(d.get("buildings"), Data.BUILDINGS),
		"bridges": pick.call(d.get("bridges"), Data.ISLES), "plots": plots.call(d.get("plots")), "gh_plots": gh.slice(0, 4),
		"guild": txt_of(d.get("guild"), "", 40), "decor": _clean_decor(d.get("decor"))}

static func _clean_decor(src) -> Array:
	var out: Array = []
	for ev in arr_of(src):
		var e := dict_of(ev)
		var id := txt_of(e.get("id"))
		if not Data.FURN.has(id) or out.size() >= 60:
			continue
		out.append({"id": id, "x": clampi(int_of(e.get("x")), 0, 12), "z": clampi(int_of(e.get("z")), 0, 12), "r": clampi(int_of(e.get("r")), 0, 3)})
	return out
