class_name KinBox
## The farm only has room for so many kin. The rest live in the Kin Burrow, a box of pages like a
## PC in the old monster games: 30 a page, each page named, and you move kin between the farm and
## the box whenever you like.
##
## Everything stays in Save.d["roster"]; a boxed kin just carries "boxed": true and "box_slot"
## (page * PAGE + cell). Boxed kin are asleep: no needs drift, no starving, no roaming, no feeders.
## Your partner and your starter always stay on the farm. A boxed kin you take on an expedition comes
## out first. New kin go to the farm if there's room, but a species you already have on the farm
## goes to the box, unless it shimmers or is mutated.

const PAGE := 30
const PAGES := 8
const FARM_CAPS := [6, 8, 10, 12]            # room on the farm, by Kin Cottage expansion
const EXPAND_COST := [0, 200, 400, 700]      # gems for each expansion
const DEFAULT_NAMES := ["Meadow", "Burrow", "Riverbank", "Hollow", "Thicket", "Dunes", "Grotto", "Starfall"]

## Fills in the box on any save and, the first time, moves the overflow off an old crowded farm.
## Returns how many kin it boxed (0 normally).
static func ensure() -> int:
	var d := Save.d
	if not d.has("box") or typeof(d["box"]) != TYPE_DICTIONARY:
		d["box"] = {}
	var bx: Dictionary = d["box"]
	if not bx.has("names") or (bx["names"] as Array).size() < PAGES:
		var names: Array = bx.get("names", [])
		while names.size() < PAGES:
			names.append("Box %d: %s" % [names.size() + 1, DEFAULT_NAMES[names.size() % DEFAULT_NAMES.size()]])
		bx["names"] = names
	if not d.has("farm_lvl"):
		d["farm_lvl"] = 0
	var moved := 0
	if not bool(d.get("box_v", false)):
		d["box_v"] = true
		moved = migrate()
	# anything odd (a boxed kin without a cell, two in one cell) gets a free cell
	var seen := {}
	for rec in d["roster"]:
		if not is_boxed(rec): continue
		var s := int(rec.get("box_slot", -1))
		if s < 0 or seen.has(s):
			s = free_slot(seen)
			rec["box_slot"] = s
		seen[s] = true
	return moved

## The first time an old save opens: if more kin are out than the farm holds, keep your partner,
## your starter and the most trusted, highest level ones out, and box the rest.
static func migrate() -> int:
	var d := Save.d
	var roster: Array = d["roster"]
	if roster.is_empty():
		return 0
	if not roster.any(func(r): return r.get("starter", false)):
		# the kin you hatched first: the earliest one that wasn't bred, caught, bought or brought back
		for r in roster:
			if not r.has("parents") and not r.has("lost_from") and not r.get("ghost", false) and not _was_caught(r):
				r["starter"] = true
				break
	var out: Array = roster.filter(func(r): return not is_boxed(r))
	if out.size() <= farm_cap():
		return 0
	out.sort_custom(func(a, b): return _keep_score(a) > _keep_score(b))
	var n := 0
	var used := {}
	for i in range(farm_cap(), out.size()):
		var rec: Dictionary = out[i]
		if pinned(rec) != "": continue
		var s := free_slot(used)
		used[s] = true
		_box(rec, s)
		n += 1
	d["box_notice"] = n
	return n

static func _was_caught(r: Dictionary) -> bool:
	for m in r.get("memory", []):
		if String(m.get("kind", "")) in ["caught", "taken", "bought"]: return true
	return false

static func _keep_score(r: Dictionary) -> float:
	var s := float(r.get("trust", 0.0)) + float(r.get("level", 1)) * 4.0
	if String(r.get("uid", "")) == str(Save.d.get("active", "")): s += 10000.0
	if r.get("starter", false): s += 5000.0
	if String(r.get("uid", "")) == str(Save.d.get("active2", "")): s += 500.0
	if r.get("farmhand", false): s += 200.0
	return s

# ------------------------------------------------------------------ who's where
static func is_boxed(rec: Dictionary) -> bool:
	return rec.get("boxed", false) == true

static func farm() -> Array:
	return (Save.d.get("roster", []) as Array).filter(func(r): return not is_boxed(r))

static func boxed() -> Array:
	return (Save.d.get("roster", []) as Array).filter(func(r): return is_boxed(r))

static func farm_lvl() -> int:
	return clampi(int(Save.d.get("farm_lvl", 0)), 0, FARM_CAPS.size() - 1)

static func farm_cap() -> int:
	return int(FARM_CAPS[farm_lvl()])

static func farm_room() -> int:
	return farm_cap() - farm().size()

static func pages() -> int:
	return PAGES

static func capacity() -> int:
	return PAGE * PAGES

## No room anywhere: the farm and every box page are full.
static func full() -> bool:
	return farm_room() <= 0 and boxed().size() >= capacity()

static func page_name(p: int) -> String:
	var names: Array = Save.d.get("box", {}).get("names", [])
	return String(names[p]) if p >= 0 and p < names.size() else "Box %d" % (p + 1)

static func rename(p: int, nm: String) -> void:
	ensure()
	nm = nm.strip_edges().substr(0, 22)
	if nm == "" or p < 0 or p >= PAGES: return
	Save.d["box"]["names"][p] = nm

static func page_of(rec: Dictionary) -> int:
	return int(rec.get("box_slot", 0)) / PAGE

## Which box cell a kin is in, or -1.
static func at(slot: int) -> Dictionary:
	for r in Save.d["roster"]:
		if is_boxed(r) and int(r.get("box_slot", -1)) == slot: return r
	return {}

static func page_kin(p: int) -> Array:
	return boxed().filter(func(r): return page_of(r) == p)

## The first empty cell (from page `from` on, wrapping round), or -1 if the box is full.
static func free_slot(also_taken := {}, from := 0) -> int:
	var taken := also_taken.duplicate()
	for r in Save.d["roster"]:
		if is_boxed(r): taken[int(r.get("box_slot", -1))] = true
	for i in capacity():
		var s := (from * PAGE + i) % capacity()
		if not taken.has(s): return s
	return -1

## Why this kin has to stay on the farm, or "".
static func pinned(rec: Dictionary) -> String:
	if String(rec.get("uid", "")) == str(Save.d.get("active", "")): return "%s is your partner: partners stay on the farm" % rec.get("name", "It")
	if rec.get("starter", false): return "%s was your first kin: it stays on the farm with you" % rec.get("name", "It")
	return ""

static func _box(rec: Dictionary, slot: int) -> void:
	rec["boxed"] = true
	rec["box_slot"] = slot
	rec.erase("farmhand")
	Care.ensure(rec)
	rec["needs_t"] = Time.get_unix_time_from_system()

static func _unbox(rec: Dictionary) -> void:
	rec.erase("boxed")
	rec.erase("box_slot")
	Care.ensure(rec)
	# it wakes up as it went to sleep: no time passed for it in the box
	rec["needs_t"] = Time.get_unix_time_from_system()

# ------------------------------------------------------------------ moving kin
## Into the box (a given cell, or the first free one). Returns "" or why not.
static func to_box(rec: Dictionary, slot := -1) -> String:
	ensure()
	var why := pinned(rec)
	if why != "": return why
	if slot >= 0:
		var there := at(slot)
		if not there.is_empty() and there != rec:
			if is_boxed(rec):
				var mine := int(rec["box_slot"])
				rec["box_slot"] = slot; there["box_slot"] = mine
				return ""
			# a farm kin dropped on a full cell: they trade places
			return swap(rec, there)
	if is_boxed(rec):
		if slot >= 0: rec["box_slot"] = slot
		return ""
	if slot < 0: slot = free_slot()
	if slot < 0: return "The Kin Burrow is full"
	_box(rec, slot)       # still your second, if it was: it comes out again when you set off
	return ""

## Out onto the farm. Returns "" or why not.
static func to_farm(rec: Dictionary) -> String:
	ensure()
	if not is_boxed(rec): return ""
	if farm_room() <= 0:
		return "The farm is full (%d/%d). Box someone first%s" % [farm().size(), farm_cap(), " or expand the cottages" if farm_lvl() < FARM_CAPS.size() - 1 else ""]
	_unbox(rec)
	return ""

## A farm kin and a boxed kin trade places. Returns "" or why not.
static func swap(farm_rec: Dictionary, box_rec: Dictionary) -> String:
	if is_boxed(farm_rec) and not is_boxed(box_rec):
		var t := farm_rec; farm_rec = box_rec; box_rec = t
	if is_boxed(farm_rec) or not is_boxed(box_rec): return "Pick one kin on the farm and one in the box"
	var why := pinned(farm_rec)
	if why != "": return why
	var s := int(box_rec["box_slot"])
	_unbox(box_rec)
	_box(farm_rec, s)
	return ""

## Somewhere on the farm for a kin you're taking out (on an expedition): out if there's room,
## otherwise it swaps with the least attached farm kin that isn't needed. Returns who went in, or {}.
static func bring_out(rec: Dictionary) -> Dictionary:
	if rec.is_empty() or not is_boxed(rec): return {}
	if to_farm(rec) == "": return {}
	var keep := [str(Save.d.get("active", "")), str(Save.d.get("active2", "")), String(rec["uid"])]
	var cands: Array = farm().filter(func(r): return pinned(r) == "" and not keep.has(String(r["uid"])))
	if cands.is_empty():
		_unbox(rec)      # nobody can make room: it squeezes onto the farm anyway
		return {}
	cands.sort_custom(func(a, b): return _keep_score(a) < _keep_score(b))
	var out: Dictionary = cands[0]
	swap(out, rec)
	return out

## Lets a kin go for good (with your blessing). Returns "" or why not.
static func release(rec: Dictionary) -> String:
	var why := pinned(rec)
	if why != "": return why
	if (Save.d["roster"] as Array).size() <= 1: return "It's your only kin"
	var egg: Dictionary = Save.d.get("egg", {})
	if not egg.is_empty() and (String(egg.get("a", "")) == String(rec["uid"]) or String(egg.get("b", "")) == String(rec["uid"])):
		return "Its egg is still in the Nesting Nook: wait for it to hatch"
	Save.d["roster"].erase(rec)
	if str(Save.d.get("active2", "")) == String(rec.get("uid", "")): Save.d["active2"] = ""
	if not Save.d.has("released"): Save.d["released"] = []
	Save.d["released"].append({"name": String(rec.get("name", "")), "species": String(rec.get("species", "")), "m": int(Save.d.get("matches", 0))})
	while (Save.d["released"] as Array).size() > 40: (Save.d["released"] as Array).pop_front()
	return ""

## Buys the next Kin Cottage expansion (+2 room on the farm). Returns "" or why not.
static func expand() -> String:
	var lv := farm_lvl()
	if lv >= FARM_CAPS.size() - 1: return "The farm is as big as it gets"
	var cost := int(EXPAND_COST[lv + 1])
	if int(Save.d["gems"]) < cost and not Game.modding(): return "Needs %d gems" % cost
	if not Game.modding(): Save.d["gems"] = int(Save.d["gems"]) - cost
	Save.d["farm_lvl"] = lv + 1
	return ""

static func expand_cost() -> int:
	var lv := farm_lvl()
	return int(EXPAND_COST[lv + 1]) if lv < FARM_CAPS.size() - 1 else -1

# ------------------------------------------------------------------ new kin
## A species already out on the farm (not counting this kin).
static func dup_on_farm(rec: Dictionary) -> bool:
	for r in farm():
		if r != rec and String(r["species"]) == String(rec["species"]): return true
	return false

## Where a new kin goes (caught, hatched, bought): call it once the kin is on the roster.
## The farm if there's room, but a repeat of a species already on the farm goes to the box unless
## it shimmers or is mutated. Returns "farm" or "box".
static func route_new(rec: Dictionary) -> String:
	ensure()
	rec["got_t"] = Time.get_unix_time_from_system()
	if is_boxed(rec): _unbox(rec)
	if (Save.d["roster"] as Array).size() <= 1 or pinned(rec) != "":
		rec["went"] = "farm"
		return "farm"
	var dup := dup_on_farm(rec) and not Mutations.special(rec)
	if not dup and farm().size() <= farm_cap():
		rec["went"] = "farm"
		return "farm"
	if to_box(rec) == "":
		rec["went"] = "box"
		return "box"
	rec["went"] = "farm"
	return "farm"

## A kin coming back to you (from the Ransom House or the Soul Shrine): the farm if there's room.
static func route_back(rec: Dictionary) -> String:
	ensure()
	if is_boxed(rec): _unbox(rec)
	if farm().size() > farm_cap() and pinned(rec) == "" and to_box(rec) == "":
		rec["went"] = "box"
		return "box"
	rec["went"] = "farm"
	return "farm"

## Where it went, for the results / hatch screens.
static func went_text(rec: Dictionary) -> String:
	if is_boxed(rec):
		return "Sent to the Kin Burrow (%s)" % page_name(page_of(rec))
	return "On the farm"

# ------------------------------------------------------------------ sorting
const SORTS := [["slot", "Box order"], ["species", "Species"], ["level", "Level"], ["rarity", "Rarity"], ["got", "Date caught"], ["name", "Name"], ["trust", "Trust"]]

static func sort_key(r: Dictionary, key: String):
	match key:
		"species": return String(Data.KIN.get(String(r["species"]), {}).get("name", r["species"])) + "%04d" % (999 - int(r.get("level", 1)))
		"level": return -int(r.get("level", 1))
		"rarity": return -Mutations.rarity_score(r)
		"got": return float(r.get("got_t", 0.0))
		"name": return String(r.get("name", "")).to_lower()
		"trust": return -float(r.get("trust", 0.0))
	return int(r.get("box_slot", 0))

static func sorted(list: Array, key: String) -> Array:
	var roster: Array = Save.d["roster"]
	var out := list.duplicate()
	out.sort_custom(func(a, b):
		var ka = sort_key(a, key); var kb = sort_key(b, key)
		if ka == kb: return roster.find(a) < roster.find(b)
		return ka < kb)
	return out

## Lays every boxed kin out again in this order, from the first cell of the first page.
static func sort_all(key: String) -> void:
	var list := sorted(boxed(), key)
	for i in list.size():
		list[i]["box_slot"] = i

## Lays out just one page's kin in this order.
static func sort_page(p: int, key: String) -> void:
	var list := sorted(page_kin(p), key)
	for i in list.size():
		list[i]["box_slot"] = p * PAGE + i

## Search and filter: does this kin match?
## filter: "all", "shimmer", "mutated", "special", "el:<work element>", a species id, or a mutation id.
static func matches(r: Dictionary, query: String, filter: String) -> bool:
	if query.strip_edges() != "" and not String(r.get("name", "")).to_lower().contains(query.strip_edges().to_lower()) \
			and not String(Data.KIN.get(String(r["species"]), {}).get("name", "")).to_lower().contains(query.strip_edges().to_lower()):
		return false
	match filter:
		"", "all": return true
		"shimmer": return r.get("shimmer", false)
		"mutated": return not Mutations.of(r).is_empty()
		"special": return Mutations.special(r)
	if filter.begins_with("el:"): return Work.level(r, filter.substr(3)) > 0     # kin that can do a kind of work
	if Data.KIN.has(filter): return String(r["species"]) == filter
	return Mutations.has(r, filter)
