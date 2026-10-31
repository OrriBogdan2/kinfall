class_name Ransom
## Lost kin. When you go down on an expedition, the kin you brought are left behind, dazed, where
## you fell. Someone may collect them:
##   nobody      -> they end up at the Ransom House on your farm, where Old Pell sells them back
##   a rival     -> that rival keeps it; you can make them an offer, or find them on an expedition
##                  (your bond lets you sense it) and take it back
##   your squad  -> a squadmate carries it home for you
## Prices and haggling live here; the Ransom House screen is in home.gd. Everything is paid in gems
## earned in play: nothing here can be bought with money.

const BROKER := "Old Pell"
const SELL_AFTER := 6          # expeditions the house waits before selling an unclaimed kin to a rival
const VOICE_ACCEPT := ["Done. It's been fretting for you.", "Pleasure doing business. Mind you keep hold of it this time.", "Agreed. I'll fetch it from the back."]
const VOICE_COUNTER := ["Mm. I could do %d.", "Not quite. Make it %d and it's yours.", "You'll have to come up. %d."]
const VOICE_INSULT := ["Insulting. The price just went up.", "Is that a joke? Try again, properly.", "I feed it every day, you know."]
const VOICE_DONE := ["I'm done haggling today. The price is the price.", "No more offers this time. Pay or come back after your next expedition."]
const RIVAL_ACCEPT := ["Fine, take it. It kept looking for you anyway.", "Deal. It never really liked me.", "Gems are gems. It's yours."]
const RIVAL_COUNTER := ["%d. Not a gem less.", "I'd part with it for %d.", "Make it %d and we're square."]
const RIVAL_REFUSE := ["Not for that. Not even close.", "You'll have to do better than that.", "Ha. No."]
const RIVAL_DONE := ["I'm not talking about this anymore.", "Find me out there if you want it so badly."]

## What a kin is worth to the people who trade them.
static func value(rec: Dictionary) -> int:
	var v := 40.0 + float(rec.get("level", 1)) * 18.0
	v += (rec.get("forms", []) as Array).size() * 30.0 + (rec.get("muts", []) as Array).size() * 15.0
	if rec.get("shimmer", false): v += 120.0
	v += 60.0 * Mutations.of(rec).size()
	v += float(rec.get("trust", 35.0)) * 0.4
	return int(round(v))

## A rival's personality, made up the first time you deal with them and kept.
static func rival(name: String) -> Dictionary:
	var rv: Dictionary = Save.d.get("rivals", {})
	if not rv.has(name):
		var h := absi(hash(name))
		rv[name] = {"greed": 0.3 + float(h % 60) / 100.0, "grudge": 0.0, "deals": 0}
		Save.d["rivals"] = rv
	return rv[name]

## Sets a fresh asking price, floor and patience on a lost-kin record.
static func price(L: Dictionary) -> void:
	var v := float(value(L["rec"]))
	var tier_k := 0.5 if int(L.get("tier", 1)) == 0 else 1.0
	if String(L.get("where", "")) == "rival":
		var rv := rival(String(L["holder"]))
		var g := float(rv["greed"]) + float(rv["grudge"])
		L["ask"] = int(round(v * (1.0 + g * 0.8)))
		L["floor"] = int(round(v * (0.65 + g * 0.55)))
	else:
		var wait := float(L.get("waited", 0))
		L["ask"] = int(round(v * tier_k * (1.0 + 0.12 * wait)))
		L["floor"] = int(round(float(L["ask"]) * 0.7))
	L["patience"] = 3

static func find(uid: String) -> Dictionary:
	for L in Save.d.get("lost_kin", []):
		if String(L["rec"].get("uid", "")) == uid:
			return L
	return {}

static func note_log(text: String) -> void:
	var lg: Array = Save.d.get("ransom_log", [])
	lg.append({"m": int(Save.d.get("matches", 0)), "text": text})
	while lg.size() > 30:
		lg.pop_front()
	Save.d["ransom_log"] = lg

## A kin left behind: off the roster and into the lost list.
static func lose(k: Dictionary, fate: String, holder: String, tier: int) -> void:
	Save.d["roster"].erase(k)
	var L := {"rec": k, "where": "rival" if fate == "rival" else "ransom", "holder": holder if fate == "rival" else BROKER,
		"since": int(Save.d.get("matches", 0)), "waited": 0, "tier": tier}
	price(L)
	(Save.d["lost_kin"] as Array).append(L)
	if fate == "rival":
		note_log("%s was collected by %s." % [k.get("name", "Your kin"), holder])
	else:
		note_log("Nobody collected %s. It's waiting at the Ransom House." % k.get("name", "Your kin"))

## Back on your roster, remembering what happened.
static func restore(L: Dictionary, how: String) -> Dictionary:
	(Save.d["lost_kin"] as Array).erase(L)
	var k: Dictionary = L["rec"]
	var held := int(Save.d.get("matches", 0)) - int(L.get("since", 0))
	var where := ("held by %s" % L["holder"]) if String(L["where"]) == "rival" else "at the Ransom House"
	Save.remember(k, "rescued", "was %s for %d expedition%s until you %s" % [where, held, "" if held == 1 else "s", how], 6.0)
	Save.d["roster"].append(k)
	if Save.d.get("active", "") == "" or Save.kin(str(Save.d.get("active", ""))).is_empty():
		Save.d["active"] = k["uid"]
	KinBox.route_back(k)
	note_log("%s came home (%s)." % [k.get("name", "Your kin"), how])
	return k

## Buying back at the asking price.
static func pay(L: Dictionary) -> bool:
	var cost := int(L["ask"])
	if int(Save.d["gems"]) < cost:
		return false
	Save.d["gems"] = int(Save.d["gems"]) - cost
	if String(L["where"]) == "rival":
		var rv := rival(String(L["holder"]))
		rv["deals"] = int(rv["deals"]) + 1
	restore(L, "paid %d gems for it" % cost)
	Save.save_game()
	return true

## Haggling. Returns {result: accept|counter|refuse|done, line, ask}.
static func offer(L: Dictionary, gems: int) -> Dictionary:
	var rival_side := String(L["where"]) == "rival"
	if int(L.get("patience", 0)) <= 0:
		return {"result": "done", "line": (RIVAL_DONE if rival_side else VOICE_DONE).pick_random(), "ask": int(L["ask"])}
	if gems > int(Save.d["gems"]):
		return {"result": "refuse", "line": "You don't have that many gems.", "ask": int(L["ask"])}
	var ask := int(L["ask"])
	var flr := int(L["floor"])
	if gems >= ask or gems >= flr:
		Save.d["gems"] = int(Save.d["gems"]) - gems
		if rival_side:
			var rv := rival(String(L["holder"]))
			rv["deals"] = int(rv["deals"]) + 1
		restore(L, "talked %s down to %d gems" % [L["holder"] if rival_side else BROKER, gems])
		Save.save_game()
		return {"result": "accept", "line": (RIVAL_ACCEPT if rival_side else VOICE_ACCEPT).pick_random(), "ask": gems}
	L["patience"] = int(L["patience"]) - 1
	if gems < int(flr * 0.6):
		# a lowball offer annoys them
		L["patience"] = int(L["patience"]) - 1
		L["ask"] = int(round(ask * 1.05))
		if rival_side:
			rival(String(L["holder"]))["grudge"] = minf(0.4, float(rival(String(L["holder"]))["grudge"]) + 0.05)
		Save.save_game()
		return {"result": "refuse", "line": (RIVAL_REFUSE if rival_side else VOICE_INSULT).pick_random(), "ask": int(L["ask"])}
	var nask := maxi(flr, int(round(ask - (ask - gems) * 0.4)))
	L["ask"] = nask
	Save.save_game()
	var lines: Array = RIVAL_COUNTER if rival_side else VOICE_COUNTER
	return {"result": "counter", "line": String(lines.pick_random()) % nask, "ask": nask}

## Called once per expedition: prices drift, the house sells kin nobody claims, rivals get bored
## of kin they hold, and rivals whose kin you took ask to buy them back.
static func tick(rivals_seen: Array) -> Array:
	var news: Array = []
	for L in (Save.d.get("lost_kin", []) as Array).duplicate():
		L["waited"] = int(L.get("waited", 0)) + 1
		var nm := String(L["rec"].get("name", "Your kin"))
		if String(L["where"]) == "ransom":
			if int(L["waited"]) > SELL_AFTER:
				var buyer: String = rivals_seen.pick_random() if not rivals_seen.is_empty() else Data.BOT_NAMES.pick_random()
				L["where"] = "rival"; L["holder"] = buyer; L["waited"] = 0
				price(L)
				news.append("%s sold %s to %s. Nobody came for it in time." % [BROKER, nm, buyer])
				note_log(news[-1])
			else:
				var keep_p := int(L.get("patience", 3))
				price(L)
				L["patience"] = maxi(keep_p, 3)
				if int(L["waited"]) == SELL_AFTER:
					news.append("%s: \"%s goes to the highest bidder after your next expedition.\"" % [BROKER, nm])
		else:
			if randf() < 0.12:
				var was_h := String(L["holder"])
				L["where"] = "ransom"; L["holder"] = BROKER; L["waited"] = 0
				price(L)
				news.append("%s got tired of %s and left it at the Ransom House." % [was_h, nm])
				note_log(news[-1])
			else:
				price(L)
	# rivals want their kin back
	var offers: Array = Save.d.get("offers", [])
	for k in Save.d["roster"]:
		var from := String(k.get("lost_from", ""))
		if from == "" or from == "you":
			continue
		if offers.any(func(o): return String(o["uid"]) == String(k["uid"])):
			continue
		if randf() < 0.4:
			var rv := rival(from)
			var g := int(round(value(k) * (0.6 + (1.0 - float(rv["greed"])) * 0.5)))
			offers.append({"uid": k["uid"], "from": from, "gems": g, "m": int(Save.d.get("matches", 0))})
			news.append("%s wants %s back and is offering %d gems. See the Ransom House." % [from, k.get("name", "a kin"), g])
	Save.d["offers"] = offers
	return news

## You accept a rival's offer for a kin you took from them.
static func sell_back(o: Dictionary) -> void:
	var k := Save.kin(String(o["uid"]))
	(Save.d["offers"] as Array).erase(o)
	if k.is_empty():
		return
	Save.d["roster"].erase(k)
	Save.d["gems"] = int(Save.d["gems"]) + int(o["gems"])
	if Save.d.get("active", "") == k["uid"] and Save.d["roster"].size() > 0:
		Save.d["active"] = Save.d["roster"][0]["uid"]
	if Save.d.get("active2", "") == k["uid"]:
		Save.d["active2"] = ""
	rival(String(o["from"]))["grudge"] = maxf(0.0, float(rival(String(o["from"]))["grudge"]) - 0.1)
	note_log("You sold %s back to %s for %d gems." % [k.get("name", "a kin"), o["from"], o["gems"]])
	Save.save_game()

static func decline(o: Dictionary) -> void:
	(Save.d["offers"] as Array).erase(o)
	var rv := rival(String(o["from"]))
	rv["grudge"] = minf(0.4, float(rv["grudge"]) + 0.05)
	Save.save_game()
