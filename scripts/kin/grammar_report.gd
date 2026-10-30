class_name GrammarReport
extends RefCounted
## Collects structural errors while kin grammar files are parsed (docs/KIN_GRAMMAR.md), plus the
## small typed-read helpers every spec class uses. Messages read "file: field.path: what's wrong".

var errors: Array[String] = []
var warnings: Array[String] = []
var file := ""

func err(path: String, msg: String) -> void:
	var line := "%s: %s%s" % [file, (path + ": ") if path != "" else "", msg]
	if not errors.has(line):
		errors.append(line)

func warn(path: String, msg: String) -> void:
	warnings.append("%s: %s%s" % [file, (path + ": ") if path != "" else "", msg])

func ok() -> bool:
	return errors.is_empty()

static func join(path: String, key: Variant) -> String:
	if typeof(key) == TYPE_INT:
		return "%s[%d]" % [path, key]
	return (path + "." + String(key)) if path != "" else String(key)

## v must be a JSON object; returns it, or {} after an error.
func obj(v: Variant, path: String) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		err(path, "must be an object {...}, got %s" % KinParts._show(v))
		return {}
	return v

## v must be a JSON array; returns it, or [] after an error.
func arr(v: Variant, path: String) -> Array:
	if typeof(v) != TYPE_ARRAY:
		err(path, "must be a list [...], got %s" % KinParts._show(v))
		return []
	return v

## Reports keys of d that aren't in `allowed`, and keys in `required` that are missing.
func keys(d: Dictionary, path: String, allowed: Array, required: Array = []) -> void:
	for k in d:
		if not allowed.has(k):
			err(join(path, k), "unknown field (allowed: %s)" % ", ".join(allowed))
	for k in required:
		if not d.has(k):
			err(join(path, k), "missing (required)")

## A string field. `nonempty` reports an empty string.
func text(d: Dictionary, key: String, path: String, dflt := "", nonempty := false) -> String:
	if not d.has(key):
		return dflt
	if typeof(d[key]) != TYPE_STRING:
		err(join(path, key), "must be text, got %s" % KinParts._show(d[key]))
		return dflt
	if nonempty and String(d[key]).strip_edges() == "":
		err(join(path, key), "can't be empty")
	return d[key]

## A value checked against a KinParts parameter definition [type, min, max, default, unit, doc].
## Returns the value, or the default when it's missing or bad.
func param(d: Dictionary, key: String, pd: Array, path: String) -> Variant:
	if not d.has(key):
		if pd[3] == null:
			err(join(path, key), "missing (required)")
		return pd[3]
	var msg := KinParts.value_error(pd, d[key])
	if msg != "":
		err(join(path, key), msg)
		return pd[3]
	return int(d[key]) if String(pd[0]) == "int" else (float(d[key]) if String(pd[0]) == "float" else d[key])

## One of `values` as text ("" when it's missing or wrong, after an error). Required unless dflt is given.
func choice(d: Dictionary, key: String, values: Array, path: String, dflt: Variant = null) -> String:
	var v = param(d, key, ["enum", values, null, dflt, "", ""], path)
	return String(v) if v != null else ""

## A plain bounded number (no param definition).
func number(d: Dictionary, key: String, path: String, lo: float, hi: float, dflt: Variant, whole := false) -> float:
	var pd := ["int" if whole else "float", lo, hi, dflt, "", ""]
	var v = param(d, key, pd, path)
	return float(v) if v != null else 0.0

## An id: lowercase letters, digits and underscores only, so it can never be a path.
func ident(d: Dictionary, key: String, path: String, required := true) -> String:
	if not d.has(key):
		if required: err(join(path, key), "missing (required)")
		return ""
	var s := text(d, key, path)
	if s != "" and not is_ident(s):
		err(join(path, key), "'%s' must be lowercase letters, digits and _ only" % s)
	return s

static func is_ident(s: String) -> bool:
	if s.is_empty() or s.length() > 48:
		return false
	for c in s:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true

func color(d: Dictionary, key: String, path: String, required := false) -> String:
	if not d.has(key):
		if required: err(join(path, key), "missing (required)")
		return ""
	var s := text(d, key, path)
	if s != "" and not (s.begins_with("#") and Color.html_is_valid(s)):
		err(join(path, key), "'%s' must be a hex colour like #a6ff3a" % s)
	return s

## Kin data must never point at a file or script. Walks every key and string value and reports
## anything that looks like one. (Nothing here is ever loaded; this is a second line of defence
## so a community file that tries is rejected with a clear reason.)
const _REF_MARKS := ["res://", "user://", "file://", "http://", "https://", ".gd", ".gdc", ".tscn", ".scn", ".tres", ".res", ".dll", ".so", ".exe"]
const _REF_KEYS := ["script", "class", "extends", "source", "path", "resource", "load", "preload", "call", "method", "eval", "expression"]

func scan_refs(v: Variant, path: String) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				var ks := String(k)
				if _REF_KEYS.has(ks.to_lower()):
					err(join(path, ks), "field name '%s' isn't allowed: kin data can't reference script or files" % ks)
				scan_refs(v[k], join(path, ks))
		TYPE_ARRAY:
			for i in (v as Array).size():
				scan_refs(v[i], join(path, i))
		TYPE_STRING:
			if looks_like_ref(String(v)):
				err(path, "'%s' looks like a file or script reference; kin data can't reference files" % String(v))

## True for "res://x", "user://x", "http://x" anywhere, or a word ending in a script/scene/resource
## extension ("foo.gd", "a/b.tres"). Prose like "it bursts. so" or "e.g." is fine.
static func looks_like_ref(s0: String) -> bool:
	var s := s0.to_lower()
	for m: String in _REF_MARKS:
		var from := 0
		while true:
			var at := s.find(m, from)
			if at < 0:
				break
			from = at + 1
			if m.ends_with("//"):
				return true
			var end := at + m.length()
			var attached := at > 0 and (_word(s[at - 1]) or s[at - 1] == "/")
			var ends := end >= s.length() or not _word(s[end])
			if attached and ends:
				return true
	return false

static func _word(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
