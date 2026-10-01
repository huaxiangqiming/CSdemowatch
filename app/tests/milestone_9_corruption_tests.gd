extends SceneTree
var failures := []
var checks := 0
var root_path := "res://../artifacts/m9/"
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr(label)
func write(name: String, bytes: PackedByteArray) -> String:
	var path := root_path + name
	var f := FileAccess.open(path,FileAccess.WRITE);f.store_buffer(bytes);f.close();return path
func reject(name: String, bytes: PackedByteArray) -> void:
	var result = load("res://scripts/core/ReplayLoader.gd").new().load_replay(write(name,bytes))
	check(not result.ok, name + " rejected")
func rewrite(original: PackedByteArray, header: Dictionary) -> PackedByteArray:
	var old_length := original.decode_u32(12)
	var encoded := JSON.stringify(header).to_utf8_buffer()
	var out := original.slice(0,16)
	out.encode_u32(12,encoded.size());out.append_array(encoded);out.append_array(original.slice(16+old_length));return out
func _initialize() -> void:
	var data := FileAccess.get_file_as_bytes(root_path+"ancient.replay")
	var changed := data.duplicate();changed.encode_u32(8,99);reject("bad-version.replay",changed)
	reject("truncated.replay",data.slice(0,data.size()-1))
	changed=data.duplicate();changed.encode_u32(12,0xffffffff);reject("huge-header.replay",changed)
	var length := data.decode_u32(12)
	var header: Dictionary = JSON.parse_string(data.slice(16,16+length).get_string_from_utf8())
	var altered := header.duplicate(true);altered.chunks[1].offset=0;reject("overlap.replay",rewrite(data,altered))
	altered=header.duplicate(true);altered.chunks[0].raw_size=1000000000;reject("huge-decompression.replay",rewrite(data,altered))
	changed=data.duplicate();changed[16+length+5] ^= 1;reject("checksum.replay",changed)
	changed=data.duplicate();changed[changed.size()-8] ^= 1
	var late = load("res://scripts/core/ReplayLoader.gd").new().load_replay(write("late-corruption.replay",changed))
	check(late.ok, "Unvisited corrupt window is not eagerly decoded")
	if late.ok:
		check(late.data.stream.tracks_at(late.data.metadata.duration).is_empty(), "Late corruption rejected on seek")
		check(not late.data.stream.error.is_empty(), "Late corruption has user-facing error")
	var cache = load("res://scripts/application/ReplayCache.gd").new()
	cache.root=ProjectSettings.globalize_path(root_path+"cache-tests")
	var demo:=write("synthetic.dem",PackedByteArray([1,2,3]))
	var hash := FileAccess.get_sha256(demo)
	DirAccess.make_dir_recursive_absolute(cache.folder(hash))
	var legacy: String=cache.folder(hash).path_join("replay.json")
	var f:=FileAccess.open(legacy,FileAccess.WRITE);f.store_string("{}");f.close()
	check(cache.commit(hash,demo,legacy) and cache.valid(hash), "Legacy manifest remains accepted")
	f=FileAccess.open(cache.binary_path(hash),FileAccess.WRITE);f.store_buffer(data);f.close()
	check(cache.commit(hash,demo,cache.binary_path(hash)) and cache.valid(hash), "Binary manifest accepted")
	check(cache.path(hash)==cache.binary_path(hash), "Manifest selects binary")
	f=FileAccess.open(cache.binary_path(hash),FileAccess.WRITE);f.store_buffer(changed);f.close()
	check(not cache.valid(hash), "Corrupted binary cache triggers rebuild")
	f=FileAccess.open(root_path+"corruption-report.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("Corruption/cache checks: ",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
