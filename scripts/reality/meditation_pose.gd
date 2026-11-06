class_name MeditationPose
extends RefCounted
## Pose de méditation (assis en tailleur) d'un KWAvatar, par Tween sur ses pivots.
## On fige l'animation procédurale de l'avatar via son drapeau d'emote (« meditate »).

const BODY_DROP := -0.5


static func sit(av: KWAvatar, dur := 0.6, instant := false) -> Tween:
	av._emote_name = "meditate"
	var tw := av.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var d := maxf(dur, 0.001) if not instant else 0.001
	tw.tween_property(av.body_root, "position:y", BODY_DROP, d)
	tw.tween_property(av.leg_l, "rotation", Vector3(1.4, 0.75, 0.0), d)
	tw.tween_property(av.leg_r, "rotation", Vector3(1.4, -0.75, 0.0), d)
	tw.tween_property(av.torso, "rotation", Vector3(0.08, 0.0, 0.0), d)
	tw.tween_property(av.arm_l, "rotation", Vector3(0.75, 0.0, -0.18), d)
	tw.tween_property(av.arm_r, "rotation", Vector3(0.75, 0.0, 0.18), d)
	tw.tween_property(av.head, "rotation", Vector3(0.15, 0.0, 0.0), d)
	if instant:
		tw.custom_step(1.0)
	return tw


static func stand(av: KWAvatar, dur := 0.5) -> Tween:
	var tw := av.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(av.body_root, "position:y", 0.0, dur)
	for n in [av.leg_l, av.leg_r, av.torso, av.arm_l, av.arm_r, av.head]:
		tw.tween_property(n, "rotation", Vector3.ZERO, dur)
	tw.chain().tween_callback(func():
		if is_instance_valid(av):
			av._emote_name = "")
	return tw
