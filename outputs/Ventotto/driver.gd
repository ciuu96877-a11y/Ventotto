extends Node3D
const Hands = preload("res://hands.gd")
var skeleton: Skeleton3D
var hand_rig := {}
var body: Node3D
var head_id := -1
var exterior := false
var body_meshes: Array[Dictionary] = []
var rest_rotations: Array[Quaternion] = []
var hands := {"l":{"control":"","hold":0.0,"blend":0.0},"r":{"control":"","hold":0.0,"blend":0.0}}
var standing := false
var combat := false
var guard := false
var strike := 0.0
var gesture_clock := 0.0
var upright := 0.0 # 0 on the stool, 1 standing at the controls; main.gd moves it when N is pressed.
var collar: MeshInstance3D
# On foot: main.gd moves the body around the tram and its own Idle / Walk clips animate it.
var roam := false
var roam_at := Vector3.ZERO
var roam_yaw := 0.0
var roam_speed := 0.0
var walker: AnimationPlayer
var strolling := false

func setup() -> void:
    body = preload("res://assets/people/luca.glb").instantiate()
    add_child(body)
    position = Vector3(0.028, 0.59, 5.55)
    for player in body.find_children("*", "AnimationPlayer", true, false):
        player.stop()
        player.active = false
        walker = player
    skeleton = body.find_children("*", "Skeleton3D", true, false)[0]
    skeleton.reset_bone_poses()
    for i in skeleton.get_bone_count(): rest_rotations.append(skeleton.get_bone_pose_rotation(i))
    head_id = skeleton.find_bone("head")
    hand_rig = Hands.rig(skeleton)
    # Slight forward lean; the spine, pelvis and clothing retain their real skinning.
    var spine := skeleton.find_bone("spine_02")
    skeleton.set_bone_pose_rotation(spine, rest_rotations[spine] * Quaternion(Vector3.RIGHT, 0.10))
    skeleton.force_update_all_bone_transforms()
    for side in ["l", "r"]:
        var sign_x := 1.0 if side == "l" else -1.0
        pose_limb("thigh_"+side, "calf_"+side, "foot_"+side, Vector3(sign_x*0.20, 0.51, 0.57), Vector3(0,0,1))
        for finger in ["index", "middle", "ring", "pinky"]:
            for part in ["01","02","03"]:
                var id := skeleton.find_bone(finger+"_"+part+"_"+side)
                if id >= 0: skeleton.set_bone_pose_rotation(id, rest_rotations[id])
    # A separate neckless mesh prevents seeing one's own face from inside the head.
    # Skinning and the complete exterior model are retained, without shrinking bones.
    for node: MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
        var original: Mesh = node.mesh
        body_meshes.append({"node":node,"original":original,"cut":trimmed(original,1.35 if str(node.name)=="Luca Skin" else 1.47)})
    # Looking straight down, the open collar would show the inside of the body; close it.
    var neck := BoneAttachment3D.new()
    skeleton.add_child(neck)
    neck.bone_name = "neck_01"
    var disc := CylinderMesh.new()
    disc.top_radius = .11
    disc.bottom_radius = .11
    disc.height = .004
    disc.radial_segments = 16
    disc.rings = 1
    var shade := StandardMaterial3D.new()
    shade.albedo_color = Color("#17120f")
    shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    disc.material = shade
    collar = MeshInstance3D.new()
    collar.mesh = disc
    collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    neck.add_child(collar)
    collar.position = Vector3(0,-.05,0)
    set_exterior(false)

func trimmed(original: Mesh,limit: float) -> ArrayMesh:
    var cut := ArrayMesh.new()
    for surface in original.get_surface_count():
        var arrays := original.surface_get_arrays(surface)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
        var kept := PackedInt32Array()
        for triangle in range(0,indices.size(),3):
            if vertices[indices[triangle]].y < limit and vertices[indices[triangle+1]].y < limit and vertices[indices[triangle+2]].y < limit:
                kept.append_array(indices.slice(triangle,triangle+3))
        if kept.is_empty(): continue
        arrays[Mesh.ARRAY_INDEX]=kept
        cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
        cut.surface_set_material(cut.get_surface_count()-1,original.surface_get_material(surface))
    return cut

func set_exterior(value: bool) -> void:
    exterior = value
    if skeleton == null: return
    collar.visible = not value
    for part in body_meshes:
        part.node.visible=value or part.cut.get_surface_count()>0
        part.node.mesh=part.original if value else part.cut

func aim_bone(id: int, child_id: int, target: Vector3) -> void:
    var pose := skeleton.get_bone_global_pose(id)
    var direction := (target - pose.origin).normalized()
    var current := (skeleton.get_bone_global_pose(child_id).origin-pose.origin).normalized()
    pose.basis = Basis(Quaternion(current, direction)) * pose.basis
    skeleton.set_bone_global_pose_override(id, pose, 1.0, true)
    skeleton.force_update_all_bone_transforms()

func pose_limb(upper: String, lower: String, end: String, target: Vector3, pole: Vector3) -> void:
    var a := skeleton.find_bone(upper)
    var b := skeleton.find_bone(lower)
    var c := skeleton.find_bone(end)
    var start := skeleton.get_bone_global_pose(a).origin
    var length_a := skeleton.get_bone_global_rest(a).origin.distance_to(skeleton.get_bone_global_rest(b).origin)
    var length_b := skeleton.get_bone_global_rest(b).origin.distance_to(skeleton.get_bone_global_rest(c).origin)
    var delta := target - start
    var distance := clampf(delta.length(), absf(length_a-length_b)+0.05, (length_a+length_b)*0.95)
    var forward := delta.normalized()
    var bend := (pole-forward*pole.dot(forward)).normalized()
    var along := (length_a*length_a+distance*distance-length_b*length_b)/(2.0*distance)
    var elbow := start+forward*along+bend*sqrt(maxf(0.0,length_a*length_a-along*along))
    aim_bone(a,b,elbow)
    aim_bone(b,c,start+forward*distance)

func touch_control(control: String) -> void:
    if standing or control.is_empty(): return
    var side := "l" if control in ["traction","reverser","bell"] else "r"
    hands[side].control = control
    hands[side].hold = 0.52 if control in ["traction","brake"] else 0.35

func set_standing(value: bool) -> void:
    standing=value
    combat=false
    for state in hands.values(): state.hold=0.0;state.blend=0.0
    guard=false
    strike=0.0

func punch() -> void:
    strike=0.48

func animate_controls(cab: Node3D, dt: float) -> void:
    if skeleton == null: return
    gesture_clock+=dt
    strike=maxf(0.0,strike-dt)
    skeleton.clear_bones_global_pose_override()
    if roam and not standing and walker!=null:
        if not strolling:
            strolling=true
            walker.active=true
        var clip:="Walk" if roam_speed>.15 else "Idle"
        if walker.current_animation!=clip: walker.play(clip,.2)
        walker.speed_scale=clampf(roam_speed/1.22,.6,2.0) if clip=="Walk" else 1.0
        scale=Vector3.ONE*(1.0 if exterior else .86)
        position=roam_at
        rotation.y=roam_yaw
        if strike>0.0:
            # A punch thrown over the walk cycle.
            pose_limb("upperarm_r","lowerarm_r","hand_r",Vector3(-.23,1.2,.2).lerp(Vector3(-.06,1.46,.66),sin((1.0-strike/.48)*PI)),Vector3(-.32,-1,-.12))
        return
    if strolling:
        # Back at the controls: the posed body takes over from the walk clips.
        strolling=false
        walker.stop()
        walker.active=false
        skeleton.reset_bone_poses()
    var lean := 0.0
    var reach := 0.0
    for side in hands:
        var state: Dictionary=hands[side]
        state.hold=maxf(0.0,state.hold-dt)
        state.blend=move_toward(state.blend,1.0 if state.hold>0.0 else 0.0,dt*(4.8 if state.hold>0.0 else 2.8))
        lean+=state.blend*(1.0 if side=="l" else -1.0)
        reach=maxf(reach,state.blend)
    # `upright` blends the stool pose into standing at the controls, feet on the floor.
    var up:=smoothstep(0.0,1.0,upright)
    # The windshield is low, so the standing eye point is too. Seen from the inside the body is
    # drawn a little smaller to keep the shoulders under the camera; from outside it is full size.
    var shrink:=1.0 if exterior or standing else lerpf(1.0,.86,up)
    scale=Vector3.ONE*shrink
    var seat:=Vector3(.028+lean*.08,.59,5.55+reach*.11)
    var stand:=Vector3(.028+lean*.15,1.07,5.46+reach*.08)
    position=Vector3(0,1.09,4.40) if standing else seat.lerp(stand,up)
    rotation.y=PI if standing else 0.0
    var spine:=skeleton.find_bone("spine_02")
    skeleton.set_bone_pose_rotation(spine,rest_rotations[spine]*Quaternion(Vector3.RIGHT,0.03 if standing else lerpf(.10+reach*.04,.12+reach*.07,up)))
    for i in skeleton.get_bone_count():
        var name:=skeleton.get_bone_name(i)
        if "arm_" in name or "hand_" in name or "thigh_" in name or "calf_" in name or "foot_" in name:
            skeleton.set_bone_pose_rotation(i,rest_rotations[i])
    skeleton.force_update_all_bone_transforms()
    for side in ["l","r"]:
        var sign_x:=1.0 if side=="l" else -1.0
        if not standing:
            var foot:=Vector3(.028+sign_x*lerpf(.20,.12,up),lerpf(1.10,1.16,up),lerpf(6.12,5.53,up))
            pose_limb("thigh_"+side,"calf_"+side,"foot_"+side,(foot-position)/shrink,Vector3(0,0,1))
        var state:Dictionary=hands[side]
        var target:=Vector3(sign_x*.235,.98,.28).lerp(Vector3(sign_x*.25,.90,.12),up)
        if strike>0.0 and side=="r" and up>.5 and not standing:
            target=target.lerp(Vector3(-.06,1.46,.66),sin((1.0-strike/.48)*PI))
        var curl:=.3
        var pointing:=false
        if standing:
            target=Vector3(sign_x*.22,1.28,.34) if combat else Vector3(sign_x*.23,.94,.13)
            if guard: target=Vector3(sign_x*.16,1.45,.32)
            if strike>0.0 and side=="r":
                var amount:=sin((1.0-strike/.48)*PI)
                target=target.lerp(Vector3(-.10,1.38,.59),amount)
            curl=1.2 if combat else .3
        elif state.blend>0.0 and cab.controls.has(state.control):
            var world_target:Vector3=cab.to_global(cab.controls[state.control])
            if state.control in ["traction","brake"]:
                var pivot:Node3D=cab.pivots[state.control]
                var grip:=Vector3(.012,.087,-.153) if state.control=="traction" else Vector3(-.013,.022,-.158)
                world_target=pivot.to_global(grip)
            var aim:=skeleton.to_local(world_target)
            aim-=Vector3(0,-.2,1).normalized()*.10
            target=target.lerp(aim,state.blend)
            target.y+=sin(state.blend*PI)*.045
            # A lever is gripped; a switch or button is pressed with the index finger.
            pointing=not state.control in ["traction","brake","reverser"]
            curl=lerpf(.3,.95,state.blend)
        target.y+=sin(gesture_clock*1.7)*.002
        pose_limb("upperarm_"+side,"lowerarm_"+side,"hand_"+side,target,Vector3(sign_x*.32,-1,-.12))
        if not standing and state.blend>.01: orient_palm(side,state.blend)
        var fingers:Dictionary=Hands.shape(hand_rig,side,curl,pointing and state.blend>.4)
        for id:int in fingers: skeleton.set_bone_pose_rotation(id,fingers[id])
    skeleton.force_update_all_bone_transforms()

func orient_palm(side: String,weight: float) -> void:
    var hand:=skeleton.find_bone("hand_"+side)
    var index:=skeleton.find_bone("index_01_"+side)
    var middle:=skeleton.find_bone("middle_01_"+side)
    var pinky:=skeleton.find_bone("pinky_01_"+side)
    var pose:=skeleton.get_bone_global_pose(hand)
    var original:=pose.basis.get_rotation_quaternion()
    var forward:=(skeleton.get_bone_global_pose(middle).origin-pose.origin).normalized()
    var desired:=Vector3(0,-.2,1).normalized()
    var turn:=Basis(Quaternion(forward,desired))
    var across:=turn*(skeleton.get_bone_global_pose(pinky).origin-skeleton.get_bone_global_pose(index).origin)
    across=(across-desired*across.dot(desired)).normalized()
    var roll:=across.signed_angle_to(Vector3.RIGHT if side=="l" else Vector3.LEFT,desired)
    var aimed:=Basis(Quaternion(desired,roll))*turn*pose.basis
    var goal:=aimed.get_rotation_quaternion()
    var angle:=original.angle_to(goal)
    pose.basis=Basis(original.slerp(goal,weight*minf(1.0,.48/maxf(angle,.001))))
    skeleton.set_bone_global_pose_override(hand,pose,1.0,true)
