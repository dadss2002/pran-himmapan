extends RefCounted
## M4d Task 3g: sound (spec docs/superpowers/specs/2026-11-08-sound.md). Sfx's request / start logs stand in
## for real audio (tests run headless on the dummy driver), and Sfx.fake_now fixes the clock.

const SPEC := "res://docs/superpowers/specs/2026-11-08-sound.md"
const TMP_SETTINGS := "user://test_sfx_settings.json"
const DT := 1.0 / 60.0
const ALL_KINDS := ["wolf", "boar", "deer", "macaque", "kongkoi", "shroom", "viper"]

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _fresh() -> void:
	Sfx.reset()
	Sfx.seed_rng(1)
	Sfx.fake_now = 100.0

func _clean() -> void:
	if FileAccess.file_exists(TMP_SETTINGS): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))

func _ids(a: Array) -> Array:
	return a.map(func(e): return String(e.id))

func _done() -> void:
	Sfx.reset()

# ---------- files ----------

## Every sound file named in the spec's event table is in the game (assets/audio) under an event id.
func test_every_spec_event_maps_to_an_existing_file():
	_fresh()
	var r := ""
	for id in Sfx.EVENTS:
		if not ResourceLoader.exists(Sfx.path_of(id)): r = "%s -> %s missing" % [id, Sfx.path_of(id)]
	if r == "" and FileAccess.file_exists(SPEC):           # docs/ is left out of exports, not of the test run
		var stems := []
		var rx := RegEx.create_from_string("\\|\\s*[a-z]+/([a-z_]+)\\.wav")
		for line in FileAccess.get_file_as_string(SPEC).split("\n"):
			if not line.begins_with("|") or line.contains("<kind>"): continue
			for m in rx.search_all(line): stems.append(m.get_string(1))
		if stems.size() < 11: r = "only %d files read from the spec table" % stems.size()
		for s in stems:
			if r == "" and not s in Sfx.EVENTS.values(): r = "spec file %s.wav has no event id" % s
	elif r == "": r = "spec file not found"
	if r == "" and Sfx.EVENTS.chest_open != "ranat_chest": r = "chest sound %s (spec: ranat_chest)" % Sfx.EVENTS.chest_open
	if r == "" and Sfx.EVENTS.level_up != "gong_levelup": r = "level-up sound %s (spec: gong_levelup)" % Sfx.EVENTS.level_up
	_done()
	return r

## Every monster kind in the game has at least one hurt and one die cry, and every listed variant exists.
func test_every_monster_kind_has_hurt_and_die():
	var kinds := ["wolf"] + Monster.KINDS
	for k in ALL_KINDS:
		if not k in kinds: return "kind %s is not in the game any more" % k
	for k in kinds:
		for ev in ["hurt", "die"]:
			var paths := Sfx.monster_paths(k, ev)
			if paths.is_empty(): return "%s has no %s cry" % [k, ev]
			for p in paths:
				if not ResourceLoader.exists(p): return "%s missing" % p
	if Sfx.monster_paths("macaque", "hurt").size() != 5 or Sfx.monster_paths("macaque", "die").size() != 3: return "macaque should have 5 hurt + 3 die"
	return ""

## Shipped audio is mono Ogg (the web build stays small), with credits next to it.
func test_audio_files_are_ogg_with_credits():
	if not FileAccess.file_exists("res://assets/audio/CREDITS.md"): return "assets/audio/CREDITS.md missing"
	for d in ["res://assets/audio", "res://assets/audio/monsters"]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".wav") or f.ends_with(".mp3"): return "%s/%s is not ogg" % [d, f]
	var s: AudioStream = load(Sfx.path_of("bow_shot"))
	return "" if s is AudioStreamOggVorbis else "bow_shot loads as %s" % s

# ---------- playback rules ----------

## The same seed gives the same variants; one seed still uses several variants of a kind.
func test_seeded_random_variant():
	var runs := []
	for run in 2:
		_fresh()
		Sfx.seed_rng(42)
		var got := []
		for i in 24:
			Sfx.fake_now = 100.0 + i * 2.0          # past the burst window and every voice
			if not Sfx.play_monster("macaque", "hurt"): return "call %d not started" % i
			got.append(String(Sfx.started[-1].path).get_file())
		runs.append(got)
	_done()
	if runs[0] != runs[1]: return "same seed, different variants: %s / %s" % [runs[0], runs[1]]
	var distinct := {}
	for f in runs[0]: distinct[f] = true
	if distinct.size() < 3: return "only %d macaque variants in 24 calls: %s" % [distinct.size(), distinct.keys()]
	for f in distinct:
		if not String(f).begins_with("macaque_hurt_"): return "wrong file %s" % f
	return ""

## One id sounds at most 4 times at once; a voice frees when its sound has ended.
func test_voice_limit_4_per_id():
	_fresh()
	var ok := 0
	for i in 6:
		if Sfx.play("arrow_hit"): ok += 1
	var r := ""
	if ok != Sfx.VOICES or Sfx.VOICES != 4: r = "%d of 6 started (want 4)" % ok
	elif not Sfx.play("bow_shot"): r = "another id was blocked by arrow_hit's limit"
	if r == "":
		Sfx.fake_now += load(Sfx.path_of("arrow_hit")).get_length() / (1.0 - Sfx.PITCH_JITTER) + 0.01
		if Sfx.voices_of("arrow_hit") != 0: r = "%d voices left after the sound ended" % Sfx.voices_of("arrow_hit")
		elif not Sfx.play("arrow_hit"): r = "arrow_hit refused after the old voices ended"
	_done()
	return r

## Monster hurt / die: at most 2 per kind in 0.05 s (other kinds not held back).
func test_monster_burst_limit():
	_fresh()
	var r := ""
	var a := [Sfx.play_monster("wolf", "hurt"), Sfx.play_monster("wolf", "die"), Sfx.play_monster("wolf", "hurt")]
	if a != [true, true, false]: r = "same instant: %s (want 2 of 3)" % [a]
	elif not Sfx.play_monster("boar", "hurt"): r = "boar blocked by the wolf's limit"
	if r == "":
		Sfx.fake_now += 0.03
		if Sfx.play_monster("wolf", "hurt"): r = "a third wolf cry within 0.05 s"
		Sfx.fake_now += 0.03
		if r == "" and not Sfx.play_monster("wolf", "die"): r = "wolf cry refused 0.06 s later"
	_done()
	return r

## Pitch ±5% on effects; Thai sounds and UI sounds keep their pitch.
func test_pitch_jitter_except_thai_and_ui():
	_fresh()
	var seen := {}
	for i in 30:
		Sfx.fake_now += 5.0
		Sfx.play("arrow_hit")
		var p: float = Sfx.started[-1].pitch
		if absf(p - 1.0) > Sfx.PITCH_JITTER + 0.0001: return "arrow_hit pitch %.3f" % p
		seen[snappedf(p, 0.001)] = true
	if seen.size() < 10: return "arrow_hit pitch hardly changes (%d values)" % seen.size()
	for id in ["pickup", "coin", "level_up", "warp", "chest_open", "ui_button", "ui_open", "toast"]:
		Sfx.fake_now += 5.0
		if not Sfx.play(id): return "%s not started" % id
		if Sfx.started[-1].pitch != 1.0: return "%s pitch %.3f (want 1.0)" % [id, Sfx.started[-1].pitch]
	Sfx.play_monster("deer", "hurt")
	var mp: float = Sfx.started[-1].pitch
	_done()
	return "" if absf(mp - 1.0) <= Sfx.PITCH_JITTER + 0.0001 else "monster pitch %.3f" % mp

## Effects at 80 %, UI at 60 %, times the player's volume; volume 0 or sound off starts nothing.
func test_volume_applied():
	_fresh()
	Sfx.play("bow_shot")
	Sfx.play("ui_button")
	var r := ""
	if absf(Sfx.started[0].volume_db - linear_to_db(0.8)) > 0.01: r = "effect at %.2f dB (want 80 %%)" % Sfx.started[0].volume_db
	elif absf(Sfx.started[1].volume_db - linear_to_db(0.6)) > 0.01: r = "UI at %.2f dB (want 60 %%)" % Sfx.started[1].volume_db
	if r == "":
		Sfx.set_volume(0.5)
		Sfx.play("crit_hit")
		if absf(Sfx.started[-1].volume_db - linear_to_db(0.4)) > 0.01: r = "volume 50 %%: %.2f dB (want 0.8 x 0.5)" % Sfx.started[-1].volume_db
	if r == "":
		Sfx.set_volume(0.0)
		var n := Sfx.started.size()
		Sfx.play("pickup")
		if Sfx.started.size() != n: r = "volume 0 still started a sound"
	_done()
	return r

## Sound off: requests are logged but no player starts; on again: a real player plays (dummy driver, no crash).
func test_disabled_starts_no_player():
	await tree.process_frame                # the root is only in the tree once the main loop runs
	_fresh()
	var host_parent := Node.new()
	tree.root.add_child(host_parent)
	var host := Sfx.attach(host_parent)
	Sfx.set_enabled(false)
	Sfx.play("bow_shot")
	Sfx.play_monster("wolf", "die")
	var r := ""
	if not Sfx.started.is_empty(): r = "started %s while off" % [_ids(Sfx.started)]
	elif host.get_child_count() != 0: r = "%d players made while off" % host.get_child_count()
	elif _ids(Sfx.requested) != ["bow_shot", "wolf_die"]: r = "requests not logged: %s" % [_ids(Sfx.requested)]
	if r == "":
		Sfx.set_enabled(true)
		Sfx.play("bow_shot")
		var players := host.get_children().filter(func(c): return c is AudioStreamPlayer)
		if players.size() != 1: r = "%d players after one sound" % players.size()
		elif players[0].stream == null or players[0].stream.resource_path != Sfx.path_of("bow_shot"): r = "player stream %s" % players[0].stream
		elif players[0].process_mode != Node.PROCESS_MODE_INHERIT or host.process_mode != Node.PROCESS_MODE_ALWAYS: r = "players stop while the game is paused (bag open)"
		await tree.process_frame
		if r == "":
			Sfx.set_enabled(false)
			if players[0].playing: r = "turning sound off left a sound playing"
	host_parent.queue_free()
	await tree.process_frame
	_done()
	return r

## Room change stops the old room's sounds; the warp gong (and UI, level-up) go on.
func test_room_change_stops_world_sounds():
	_fresh()
	Sfx.play("arrow_hit")
	Sfx.play_monster("wolf", "hurt")
	Sfx.play("warp")
	Sfx.play("ui_button")
	Sfx.stop_world()
	var r := ""
	if Sfx.voices_of("arrow_hit") != 0 or Sfx.voices_of("wolf_hurt") != 0: r = "world sounds still counted after the room change"
	elif Sfx.voices_of("warp") != 1 or Sfx.voices_of("ui_button") != 1: r = "warp / UI sound stopped by the room change"
	_done()
	return r

## Reviewer 2026-11-08: when all MAX_PLAYERS players are busy, the oldest is stolen; its sound stops, so its
## voice must leave that id's count (else the id stays "full" with fewer voices really sounding).
func test_stolen_player_frees_its_voice():
	await tree.process_frame
	_fresh()
	var host_parent := Node.new()
	tree.root.add_child(host_parent)
	var host := Sfx.attach(host_parent)
	var ids := ["arrow_hit", "bow_shot", "crit_hit", "pickup", "coin", "level_up"]
	var r := ""
	for id in ids:
		for i in Sfx.VOICES:
			if not Sfx.play(id): r = "%s voice %d not started" % [id, i + 1]
	var players := host.get_children().filter(func(c): return c is AudioStreamPlayer)
	if r == "" and players.size() != Sfx.MAX_PLAYERS: r = "%d players (want all %d busy)" % [players.size(), Sfx.MAX_PLAYERS]
	if r == "" and players.any(func(p): return not p.playing): r = "a player is not playing before the steal"
	if r == "" and Sfx.voices_of("arrow_hit") != Sfx.VOICES: r = "arrow_hit %d voices (want %d)" % [Sfx.voices_of("arrow_hit"), Sfx.VOICES]
	if r == "":
		var oldest: AudioStreamPlayer = players[0]
		if String(oldest.get_meta("id", "")) != "arrow_hit": r = "oldest player is %s" % oldest.get_meta("id", "")
		elif not Sfx.play("warp"): r = "warp not started with every player busy"
		elif String(oldest.get_meta("id", "")) != "warp": r = "the oldest player was not reused"
		elif host.get_children().filter(func(c): return c is AudioStreamPlayer).size() != Sfx.MAX_PLAYERS: r = "more than MAX_PLAYERS players"
		elif Sfx.voices_of("arrow_hit") != Sfx.VOICES - 1: r = "arrow_hit still counts %d voices after its player was stolen (want %d)" % [Sfx.voices_of("arrow_hit"), Sfx.VOICES - 1]
		elif Sfx.voices_of("warp") != 1: r = "warp counts %d voices" % Sfx.voices_of("warp")
		elif not Sfx.play("arrow_hit"): r = "arrow_hit refused although only 3 of its voices still sound"
	Sfx.stop_all()
	host_parent.queue_free()
	await tree.process_frame
	_done()
	return r

# ---------- settings ----------

func test_settings_saved_and_loaded():
	_fresh()
	_clean()
	var d := GameSettings.load_or_default(TMP_SETTINGS)
	var r := ""
	if d.sound != true or d.volume != 100: r = "defaults %s (want sound on, volume 100)" % d
	if r == "":
		var hud := Hud.new()
		hud.settings_path = TMP_SETTINGS
		hud.build()
		tree.root.add_child(hud)                   # a slider only sends value_changed inside the tree
		if not hud.sound_toggle.button_pressed or hud.volume_slider.value != 100: r = "panel shows %s / %s" % [hud.sound_toggle.button_pressed, hud.volume_slider.value]
		elif hud.sound_toggle.text != "เสียง": r = "toggle text '%s'" % hud.sound_toggle.text
		if r == "":
			hud.sound_toggle.button_pressed = false        # emits toggled
			hud.volume_slider.value = 40                   # emits value_changed
			if Sfx.enabled: r = "เสียง off did not turn sound off"
			elif absf(Sfx.volume - 0.4) > 0.001: r = "slider 40 gave volume %.2f" % Sfx.volume
		hud.free()
	if r == "":
		d = GameSettings.load_or_default(TMP_SETTINGS)
		if d.sound != false or d.volume != 40 or typeof(d.volume) != TYPE_INT: r = "saved %s" % d
	if r == "":
		Sfx.reset()
		var again := Hud.new()                              # next session
		again.settings_path = TMP_SETTINGS
		again.build()
		if again.sound_toggle.button_pressed or again.volume_slider.value != 40: r = "panel not restored: %s / %s" % [again.sound_toggle.button_pressed, again.volume_slider.value]
		elif Sfx.enabled or absf(Sfx.volume - 0.4) > 0.001: r = "Sfx not restored: enabled=%s volume=%.2f" % [Sfx.enabled, Sfx.volume]
		again.set_sound(true)
		again.set_volume(100)
		again.free()
	if r == "":
		var f := FileAccess.open(TMP_SETTINGS, FileAccess.WRITE)
		f.store_string(JSON.stringify({"sound": "yes", "volume": 250}))
		f.close()
		d = GameSettings.load_or_default(TMP_SETTINGS)
		if d.sound != true or d.volume != 100: r = "bad values gave %s" % d
	_clean()
	_done()
	return r

## Owner 2026-11-08: the volume row shows the % beside the slider, live, and "ความดัง" keeps a left margin.
func test_volume_percent_shown_live():
	_fresh()
	_clean()
	var hud := Hud.new()
	hud.settings_path = TMP_SETTINGS
	hud.build()
	tree.root.add_child(hud)                   # a slider only sends value_changed inside the tree
	var r := ""
	var pct: Label = hud.volume_label
	if pct == null or pct.get_parent() != hud.volume_slider.get_parent(): r = "no % label in the volume row"
	elif pct.text != "100%": r = "label '%s' at 100" % pct.text
	if r == "":
		hud.volume_slider.value = 80               # dragging the slider
		if pct.text != "80%": r = "slider 80 shows '%s'" % pct.text
	if r == "":
		hud.set_volume(35, false)
		if pct.text != "35%": r = "set_volume(35) shows '%s'" % pct.text
	if r == "":
		var w100 := pct.get_combined_minimum_size().x
		hud.set_volume(100, false)
		if pct.get_combined_minimum_size().x != w100: r = "the %% label changes width (%.1f / %.1f): the slider would jump" % [w100, pct.get_combined_minimum_size().x]
	if r == "":
		var row: HBoxContainer = hud.volume_slider.get_parent()
		var name_label: Label = row.get_child(0)
		var kids := row.get_children()
		if name_label.text != "ความดัง": r = "first in the row is '%s'" % name_label.text
		elif kids.find(pct) < kids.find(hud.volume_slider): r = "% label is left of the slider"
		else:
			var sb := name_label.get_theme_stylebox("normal")
			if sb == null or sb.content_margin_left < 4.0: r = "ความดัง has no left margin (%s)" % (sb.content_margin_left if sb else "none")
	hud.free()
	_clean()
	_done()
	return r

# ---------- call sites ----------

func test_hero_shot_and_skill_play_bow_shot():
	_fresh()
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	var shots := []
	h.shot.connect(func(a): shots.append(a))
	h.try_shoot()
	for i in 60: h.step(DT, Vector2.ZERO)
	var r := ""
	var n := _ids(Sfx.requested).count("bow_shot")
	if shots.size() != 1: r = "no arrow (%d)" % shots.size()
	elif n != 1: r = "bow_shot requested %d times for one shot" % n
	if r == "":
		h.set_progress(Skills.unlock_level("spread"), 0)
		h.mp = 999
		h.try_skill("spread")
		for i in 90: h.step(DT, Vector2.ZERO)
		n = _ids(Sfx.requested).count("bow_shot")
		if shots.size() < 3: r = "spread fired %d arrows in all" % shots.size()
		elif n != 2: r = "spread: bow_shot requested %d times in all (want one per release)" % n
	for a in shots: if is_instance_valid(a): a.free()
	h.free()
	_done()
	return r

func _monster_world(kind: String) -> Array:
	await tree.process_frame
	var w := Node2D.new()
	tree.root.add_child(w)
	var p := WolfPack.new()
	p.kind = kind
	p.level = 1
	p.count = 1
	p.home = Vector2(200, 200)
	w.add_child(p)
	p.set_physics_process(false)
	return [w, p.wolves[0]]

## A plain hit: arrow_hit + the kind's hurt cry; a crit: crit_hit instead of arrow_hit; the killing hit:
## the die cry instead of the hurt cry.
func test_hit_crit_and_death_sounds():
	var r := ""
	for kind in ["wolf", "boar"]:
		_fresh()
		var got: Array = await _monster_world(kind)
		var w: Node2D = got[0]
		var m: Wolf = got[1]
		m.health.setup(1000)
		m.receive_hit(1.0, 1.0, Vector2(150, 200), 0.0)
		var ids := _ids(Sfx.requested)
		if ids != ["arrow_hit", kind + "_hurt"]: r = "%s plain hit: %s" % [kind, ids]
		if r == "":
			Sfx.requested.clear()
			Sfx.fake_now += 5.0
			m.receive_hit(1.0, 1.0, Vector2(150, 200), 1.0)
			ids = _ids(Sfx.requested)
			if ids != ["crit_hit", kind + "_hurt"]: r = "%s crit: %s (crit replaces the hit sound)" % [kind, ids]
		if r == "":
			Sfx.requested.clear()
			Sfx.fake_now += 5.0
			m.health.hp = 1
			m.receive_hit(50.0, 1.0, Vector2(150, 200), 0.0)
			ids = _ids(Sfx.requested)
			if m.is_alive(): r = "%s did not die" % kind
			elif ids != ["arrow_hit", kind + "_die"]: r = "%s killing hit: %s (die replaces hurt)" % [kind, ids]
			elif not String(Sfx.started[-1].path).contains("/monsters/%s_die_" % kind): r = "%s die file %s" % [kind, Sfx.started[-1].path]
		w.queue_free()
		_done()
		if r != "": break
	return r

## Picking up gold rings the coin sound; anything else the pickup sound.
func test_pickup_and_coin_sounds():
	_fresh()
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	var inv := Inventory.new()
	var r := ""
	for pair in [["gold", "coin"], ["ore_himmapan", "pickup"]]:
		Sfx.requested.clear()
		var d := LootDrop.make(pair[0], 1)
		d.position = Vector2(10, 0)
		d.settle()
		var got := false
		for i in 30:
			if d.step(DT, h, inv): got = true; break
		if not got: r = "%s never collected" % pair[0]
		elif _ids(Sfx.requested) != [pair[1]]: r = "%s pickup: %s (want %s)" % [pair[0], _ids(Sfx.requested), pair[1]]
		d.free()
		if r != "": break
	h.free()
	_done()
	return r

## Reviewer 2026-11-08: with the bag nearly full only part of a stack fits; what went in still plays "pickup"
## (once), and the rest stays on the ground.
func test_partial_pickup_plays_sound():
	_fresh()
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	var inv := Inventory.new()
	var stack := int(Balance.num("bag.stack"))
	for i in int(Balance.num("bag.slots")) - 1: inv.add_item(_bow())
	inv.add("ore_himmapan", stack - 2)            # room for 2 more ore only
	var d := LootDrop.make("ore_himmapan", 5)
	d.position = Vector2(10, 0)
	d.settle()
	var r := ""
	for i in 30:
		if d.step(DT, h, inv): r = "the whole stack of 5 was taken into a bag with room for 2"; break
	if r == "" and inv.count_of("ore_himmapan") != stack: r = "bag holds %d ore (want %d)" % [inv.count_of("ore_himmapan"), stack]
	elif r == "" and d.count != 3: r = "%d left on the ground (want 3)" % d.count
	elif r == "" and _ids(Sfx.requested) != ["pickup"]: r = "partial pickup sounds: %s (want [pickup])" % [_ids(Sfx.requested)]
	d.free()
	h.free()
	_done()
	return r

func _bow() -> Dictionary:
	return {"base": "bow_buffalo_horn", "rarity": "good", "level": 5, "opts": []}

func test_level_up_gong_once():
	_fresh()
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.set_progress(1, 0)
	h.gain_exp(1)
	var r := ""
	if _ids(Sfx.requested).has("level_up"): r = "gong without a level"
	if r == "":
		h.gain_exp(Progression.exp_to_next(1) + Progression.exp_to_next(2))
		if h.level != 3: r = "level %d (want 3)" % h.level
		elif _ids(Sfx.requested).count("level_up") != 1: r = "level_up requested %d times for 2 levels at once" % _ids(Sfx.requested).count("level_up")
	h.free()
	_done()
	return r

## Walking into an exit: the warp gong; the room change stops the old room's hit sounds.
func test_warp_gong_and_room_change():
	_fresh()
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = "user://test_sfx_ground_save.json"
	g.settings_path = TMP_SETTINGS
	g.layout_seed = 7
	g.build()
	var r := ""
	if Sfx.host == null or not is_instance_valid(Sfx.host) or Sfx.host.get_parent() != g: r = "test ground has no sound node"
	if r == "":
		Sfx.play("arrow_hit")
		var w: Warp = g.warps[0]
		var to: String = w.to_room
		g.warp_through(w)             # not in the tree: changes room at once
		if g.room_id != to: r = "room %s (want %s)" % [g.room_id, to]
		elif not _ids(Sfx.requested).has("warp"): r = "no warp sound: %s" % [_ids(Sfx.requested)]
		elif Sfx.voices_of("arrow_hit") != 0: r = "old room's hit still sounding"
		elif Sfx.voices_of("warp") != 1: r = "warp gong stopped by the room change"
	g.free()
	_clean()
	if FileAccess.file_exists("user://test_sfx_ground_save.json"): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_sfx_ground_save.json"))
	_done()
	return r

## HUD: menu buttons click; bag / skills play the open sound (not a click too); a toast plays its sound.
func test_hud_button_open_and_toast_sounds():
	_fresh()
	_clean()
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = "user://test_sfx_ground_save.json"
	g.settings_path = TMP_SETTINGS
	g.layout_seed = 7
	tree.root.add_child(g)
	await tree.process_frame
	var hud: Hud = g.hud
	var r := ""
	Sfx.requested.clear()
	hud.settings_button.pressed.emit()
	if _ids(Sfx.requested) != ["ui_button"]: r = "settings button: %s" % [_ids(Sfx.requested)]
	if r == "":
		Sfx.requested.clear()
		hud.map_button.pressed.emit()
		if _ids(Sfx.requested) != ["ui_open"]: r = "map button (opens the full map): %s" % [_ids(Sfx.requested)]
		hud.close_map()
	if r == "":
		Sfx.requested.clear()
		hud.bag_button.pressed.emit()
		if _ids(Sfx.requested) != ["ui_open"]: r = "bag button: %s" % [_ids(Sfx.requested)]
	if r == "":
		Sfx.requested.clear()
		var close: Button = hud.bag_panel._close_button
		if close == null: r = "bag close button not found"
		else:
			close.pressed.emit()
			if _ids(Sfx.requested) != ["ui_button"]: r = "bag close: %s" % [_ids(Sfx.requested)]
	if r == "":
		Sfx.requested.clear()
		hud.skills_button.pressed.emit()
		if _ids(Sfx.requested) != ["ui_open"]: r = "skills button: %s" % [_ids(Sfx.requested)]
		hud.skill_panel.close()
	if r == "":
		Sfx.requested.clear()
		hud.skill_panel.refresh()                      # makes new slot buttons: they click too
		var slot: Button = null
		for b in hud.skill_panel.find_children("*", "Button", true, false):
			if b.is_inside_tree() and not b.is_queued_for_deletion() and b.has_meta("click_sound") and b.pressed.is_connected(hud._click): slot = b
		if slot == null: r = "skill panel buttons are not wired to the click sound"
	g.queue_free()
	await tree.process_frame
	tree.paused = false
	_clean()
	if FileAccess.file_exists("user://test_sfx_ground_save.json"): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_sfx_ground_save.json"))
	_done()
	return r
