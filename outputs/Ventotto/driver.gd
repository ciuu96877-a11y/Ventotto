extends Node3D
var skeleton: Skeleton3D
var body: Node3D
var head_id := -1
var exterior := false
var body_meshes: Array[Dictionary] = []

func setup() -> void:
    body = preload("res://assets/people/luca.glb").instantiate()
    add_child(body)
    position = Vector3(0.028, 0.59, 5.55)
    for player in body.find_children("*", "AnimationPlayer", true, false):
        player.stop()
        player.active = false
    skeleton = body.find_children("*", "Skeleton3D", true, false)[0]
    head_id = skeleton.find_bone("head")
    # Slight forward lean; the spine, pelvis and clothing retain their real skinning.
    var spine := skeleton.find_bone("spine_02")
    skeleton.set_bone_pose_rotation(spine, Quaternion(Vector3.RIGHT, 0.17))
    skeleton.force_update_all_bone_transforms()
    for side in ["l", "r"]:
        var sign_x := 1.0 if side == "l" else -1.0
        pose_limb("thigh_"+side, "calf_"+side, "foot_"+side, Vector3(sign_x*0.20, 0.51, 0.57), Vector3(0,0,1))
        for finger in ["index", "middle", "ring", "pinky"]:
            for part in ["01","02","03"]:
                var id := skeleton.find_bone(finger+"_"+part+"_"+side)
                if id >= 0: skeleton.set_bone_pose_rotation(id, Quaternion(Vector3.RIGHT, 0.45))
    # A separate neckless mesh prevents seeing one's own face from inside the head.
    # Skinning and the complete exterior model are retained, without shrinking bones.
    for node: MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
        var original: Mesh = node.mesh
        var cut := ArrayMesh.new()
        var neck_cut := 1.35 if str(node.name)=="Luca Skin" else 1.47
        for surface in original.get_surface_count():
            var arrays := original.surface_get_arrays(surface)
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            var kept := PackedInt32Array()
            for triangle in range(0,indices.size(),3):
                if vertices[indices[triangle]].y < neck_cut and vertices[indices[triangle+1]].y < neck_cut and vertices[indices[triangle+2]].y < neck_cut:
                    kept.append_array(indices.slice(triangle,triangle+3))
            if kept.is_empty(): continue
            arrays[Mesh.ARRAY_INDEX]=kept
            cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
            cut.surface_set_material(cut.get_surface_count()-1,original.surface_get_material(surface))
        body_meshes.append({"node":node,"original":original,"cut":cut})
    set_exterior(false)

func set_exterior(value: bool) -> void:
    exterior = value
    if skeleton == null: return
    for part in body_meshes:
        part.node.visible=value or part.cut.get_surface_count()>0
        part.node.mesh=part.original if value else part.cut

func aim_bone(id: int, target: Vector3) -> void:
    var pose := skeleton.get_bone_global_pose(id)
    var direction := (target - pose.origin).normalized()
    pose.basis = Basis(Quaternion(pose.basis.y.normalized(), direction)) * pose.basis
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
    var distance := clampf(delta.length(), 0.04, length_a+length_b-0.005)
    var forward := delta.normalized()
    var bend := (pole-forward*pole.dot(forward)).normalized()
    var along := (length_a*length_a+distance*distance-length_b*length_b)/(2.0*distance)
    var elbow := start+forward*along+bend*sqrt(maxf(0.0,length_a*length_a-along*along))
    aim_bone(a,elbow)
    aim_bone(b,start+forward*distance)

func animate_controls(cab: Node3D, _dt: float) -> void:
    if skeleton == null: return
    for side in ["l","r"]:
        var control: Node3D = cab.pivots["traction" if side=="l" else "brake"]
        var grip := Vector3(0.012,0.087,-0.153) if side=="l" else Vector3(-0.013,0.022,-0.158)
        var target := skeleton.to_local(control.to_global(grip))
        var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone("upperarm_"+side)).origin
        target -= (target-shoulder).normalized()*0.075
        pose_limb("upperarm_"+side,"lowerarm_"+side,"hand_"+side,target,Vector3(0.7 if side=="l" else -0.7,-1,0.1))
