extends SceneTree
## Headless test runner: godot --headless --path . --script tests/run_tests.gd
## Runs every test_*.gd in res://tests, calls each test_* method (awaited, so a test may
## `await tree.physics_frame` after setup(tree)), exits 1 on any failure.

var failures := 0
var passed := 0

func _initialize() -> void:
	_run_all()

func _run_all() -> void:
	var dir := DirAccess.open("res://tests")
	var files := Array(dir.get_files())
	files.sort()
	var only := OS.get_environment("TEST_ONLY")      # e.g. TEST_ONLY=test_monsters to run one file
	for f in files:
		if only != "" and not f.begins_with(only): continue
		if f.begins_with("test_") and f.ends_with(".gd"):
			await _run_file("res://tests/" + f)
	print("RESULT passed=%d failed=%d" % [passed, failures])
	quit(1 if failures > 0 else 0)

func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		failures += 1
		print("  FAIL %s — script failed to load/parse" % path.get_file())
		return
	var inst = script.new()
	if inst.has_method("setup"):
		inst.setup(self)
	for m in script.get_script_method_list():
		var name: String = m["name"]
		if name.begins_with("test_"):
			var err = await inst.call(name)
			# A test passes only by returning "" explicitly. A script error inside a test makes
			# the call return null, which must count as a failure, never as a pass.
			if err == null:
				err = "test errored or returned nothing (see SCRIPT ERROR above)"
			if typeof(err) == TYPE_STRING and err == "":
				passed += 1
				print("  ok   %s::%s" % [path.get_file(), name])
			else:
				failures += 1
				print("  FAIL %s::%s — %s" % [path.get_file(), name, err])
