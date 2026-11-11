extends Node3D

const VISUAL = preload("res://assets/driver_cab.glb")
const CONTROLS = {
    "traction":Vector3(.666,2.059,6.065),
    "brake":Vector3(-.668,1.944,6.022),
    "reverser":Vector3(.416,1.750,6.114),
    "master":Vector3(-.444,1.774,6.186),
    "doors":Vector3(-.328,1.775,6.185),
    "headlights":Vector3(-.086,1.690,6.145),
    "wiper":Vector3(0,1.690,6.145),
    "bell":Vector3(.086,1.690,6.145),
}

var controls := CONTROLS
var pivots := {}
var lights := {}
var wiper_phase := 0.0
var cabin: Node3D

func setup() -> void:
    cabin = VISUAL.instantiate()
    add_child(cabin)
    for key in ["traction","brake","reverser","master","wiper"]:
        pivots[key] = cabin.find_child("CTRL_"+key,true,false)
    for key in ["speed","pressure","amps"]:
        pivots[key] = cabin.find_child("NEEDLE_"+key,true,false)
    for key in ["master","doors"]:
        var l := cabin.find_child("LAMP_"+key,true,false) as MeshInstance3D
        var mat := l.get_active_material(0).duplicate() as StandardMaterial3D
        l.material_override = mat
        lights[key] = mat
    var bounce := OmniLight3D.new()
    bounce.light_energy = .35
    bounce.light_color = Color("#ffe2b8")
    bounce.omni_range = 2.4
    add_child(bounce)
    bounce.position = Vector3(.10,2.76,5.55)

func finish_interior(tram: Node3D) -> void:
    var detail := preload("res://assets/interior/details.glb").instantiate()
    add_child(detail)
    var oak: StandardMaterial3D
    var upholstery: StandardMaterial3D
    for node: MeshInstance3D in cabin.find_children("*","MeshInstance3D",true,false):
        var m := node.get_active_material(0)
        if m is StandardMaterial3D:
            if m.resource_name.begins_with("Quercia") and oak == null:
                oak=m.duplicate()
                oak.uv1_triplanar=false
                oak.uv1_scale=Vector3.ONE
                oak.normal_scale=0.12
                oak.roughness=0.42
            if m.resource_name.begins_with("Cuio") and upholstery == null: upholstery=m
        if str(node.name).begins_with("Sedile cucito"): node.hide()
    if oak != null:
        for node: MeshInstance3D in tram.find_children("*","MeshInstance3D",true,false):
            for surface in node.mesh.get_surface_count():
                var m := node.get_active_material(surface)
                if m != null and m.resource_name.begins_with("Rovere"):
                    node.set_surface_override_material(surface,oak)
        for node: MeshInstance3D in detail.find_children("*","MeshInstance3D",true,false):
            if "oak" in str(node.name).to_lower(): node.material_override=oak
            if "upholstery" in str(node.name).to_lower() and upholstery != null: node.material_override=upholstery
    for z in [-4.8,-2.4,0.0,2.4,4.5]:
        var light := OmniLight3D.new()
        light.position=Vector3(0,2.70,z)
        light.light_color=Color("#ffdfac")
        light.light_energy=.29
        light.omni_range=2.8
        add_child(light)

func read_controls(view: Camera3D) -> String:
    var center := view.get_viewport().get_visible_rect().size*.5
    var nearest := 38.0
    var hit := ""
    for key in controls:
        var p := to_global(controls[key])
        if view.is_position_behind(p): continue
        var pixels := center.distance_to(view.unproject_position(p))
        if pixels<nearest:
            nearest = pixels
            hit = key
    return hit

func glow(key: String,enabled: bool,color: Color) -> void:
    var m: StandardMaterial3D = lights[key]
    m.emission_enabled = enabled
    m.emission = color
    m.emission_energy_multiplier = 1.4

func update_instruments(dt: float,speed: float,pressure: float,amps: float,traction: int,brake: int,reverser: int,master: bool,doors: bool,wiper: bool) -> void:
    for value in [["speed",speed/60.0],["pressure",pressure/6.0],["amps",amps/400.0]]:
        var needle: Node3D = pivots[value[0]]
        needle.rotation.z = lerpf(needle.rotation.z,-2.17+4.34*clampf(value[1],0,1),minf(dt*12,1))
    var controller: Node3D = pivots["traction"]
    var valve: Node3D = pivots["brake"]
    controller.rotation.y = lerpf(controller.rotation.y,-.70+traction*.235,minf(dt*14,1))
    valve.rotation.y = lerpf(valve.rotation.y,.53-brake*.27,minf(dt*14,1))
    pivots["reverser"].rotation.y = reverser*.43
    pivots["master"].rotation.y = 1.12 if master else 0
    glow("master",master,Color("#96bf68"))
    glow("doors",doors,Color("#ffba60"))
    if wiper or wiper_phase>0.0:
        wiper_phase = fmod(wiper_phase+dt*3.2,TAU)
        if not wiper and wiper_phase<dt*3.3: wiper_phase = 0
    pivots["wiper"].rotation.z = -.40+(1-cos(wiper_phase))*.61
