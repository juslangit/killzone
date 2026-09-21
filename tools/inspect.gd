extends SceneTree
func _initialize() -> void:
	for m in ClassDB.class_get_method_list("AnimationNodeBlendSpace2D", true):
		if "blend_point" in String(m.name):
			var args := []
			for a in m.args:
				args.append("%s: %s" % [a.name, type_string(a.type)])
			print(m.name, "(", ", ".join(args), ")")
	quit()
