extends RefCounted
## Finger posing shared by the driver and everyone else. The rig's finger bones are not
## aligned with the knuckles, so each joint gets its own bending axis measured from the
## rest pose, and the splayed rest fingers are gathered toward the middle finger.
const FINGERS := ["index","middle","ring","pinky","thumb"]
const PARTS := ["01","02","03"]

## side -> finger -> {"joints": [[bone, rest rotation, bend axis], ...], "gather": angle, "normal": axis}
static func rig(sk: Skeleton3D) -> Dictionary:
    var out := {}
    for side: String in ["l","r"]:
        var hand := sk.find_bone("hand_"+side)
        var first := sk.find_bone("index_01_"+side)
        var last := sk.find_bone("pinky_01_"+side)
        var centre := sk.find_bone("middle_01_"+side)
        if hand<0 or first<0 or last<0 or centre<0 or sk.find_bone("middle_02_"+side)<0: continue
        var wrist := sk.get_bone_global_rest(hand)
        var index_root := sk.get_bone_global_rest(first).origin
        var pinky_root := sk.get_bone_global_rest(last).origin
        var palm := (index_root-wrist.origin).cross(pinky_root-wrist.origin).normalized()
        if palm.dot(wrist.basis.z)<0.0: palm = -palm
        var straight := sk.get_bone_global_rest(sk.find_bone("middle_02_"+side)).origin-sk.get_bone_global_rest(centre).origin
        straight = (straight-palm*straight.dot(palm)).normalized()
        var fingers := {}
        for finger: String in FINGERS:
            var joints := []
            var ids: Array[int] = []
            for part: String in PARTS: ids.append(sk.find_bone("%s_%s_%s" % [finger,part,side]))
            if ids.has(-1): continue
            for i in 3:
                var frame := sk.get_bone_global_rest(ids[i])
                var along := frame.basis.y.normalized()
                if i<2: along = (sk.get_bone_global_rest(ids[i+1]).origin-frame.origin).normalized()
                # Fingers close onto the palm; the thumb closes across it, toward the base of the fingers.
                var toward := palm
                if finger=="thumb": toward = ((index_root+pinky_root)*.5+palm*.035-frame.origin).normalized()
                var axis := along.cross(toward).normalized()
                joints.append([ids[i],sk.get_bone_rest(ids[i]).basis.get_rotation_quaternion(),(frame.basis.orthonormalized().inverse()*axis).normalized()])
            var root := sk.get_bone_global_rest(ids[0])
            var gather := 0.0
            if finger!="thumb" and finger!="middle":
                var reach := sk.get_bone_global_rest(ids[1]).origin-root.origin
                gather = (reach-palm*reach.dot(palm)).normalized().signed_angle_to(straight,palm)
            fingers[finger] = {"joints":joints,"gather":gather,"normal":(root.basis.orthonormalized().inverse()*palm).normalized()}
        out[side] = fingers
    return out

## Bone rotations for one hand. `amount` runs from 0 (flat) through about 0.3 (relaxed)
## to 1.2 (fist); `point` keeps the index finger straight; `gather` closes the spread.
static func shape(hand_rig: Dictionary,side: String,amount: float,point := false,gather := .75) -> Dictionary:
    var out := {}
    if not hand_rig.has(side): return out
    var fingers: Dictionary = hand_rig[side]
    var order := 0
    for finger: String in FINGERS:
        if not fingers.has(finger): continue
        var data: Dictionary = fingers[finger]
        var bend := amount*(.86+.13*order)
        var share := [.8,1.15,.75]
        if finger=="thumb":
            bend = amount
            share = [.3,.42,.4]
        elif point and finger=="index":
            bend = .06
        order += 1
        var joints: Array = data["joints"]
        for i in joints.size():
            var joint: Array = joints[i]
            var turn: Quaternion = joint[1]
            if i==0: turn *= Quaternion(data["normal"],float(data["gather"])*gather)
            out[joint[0]] = turn*Quaternion(joint[2],bend*float(share[i]))
    return out
