extends Node3D
var vehicle: Node3D
var cab: Node3D
var route: Node3D
var rain: MultiMeshInstance3D
var splashes: MultiMeshInstance3D
var rain_material: ShaderMaterial
var splash_material: ShaderMaterial
var glass_materials: Array[ShaderMaterial] = []
var glass_front: Array[Dictionary] = []
var applied := false
var rain_level := 0.0
var puddle_level := 0.0
var weather_time := 0.0
var mask_timer := 0.0
var last_wiper_angle := -0.40
var road_materials: Array[ShaderMaterial] = []

func instances(count: int, shader: Shader, size: Vector2) -> MultiMeshInstance3D:
    var material := ShaderMaterial.new()
    material.shader = shader
    var mesh := QuadMesh.new()
    mesh.size = size
    mesh.material = material
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.use_custom_data = true
    multi.mesh = mesh
    multi.instance_count = count
    var rng := RandomNumberGenerator.new()
    rng.seed = 9128
    for i in count:
        multi.set_instance_transform(i,Transform3D.IDENTITY)
        multi.set_instance_custom_data(i,Color(rng.randf(),rng.randf(),rng.randf(),rng.randf()))
    multi.custom_aabb = AABB(Vector3(-40,0,-40),Vector3(80,22,80))
    var node := MultiMeshInstance3D.new()
    node.multimesh = multi
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)
    return node

func setup(tram: Node3D, model: Node3D, cabin: Node3D, line: Node3D) -> void:
    vehicle=tram
    cab=cabin
    route=line
    rain=instances(10000,preload("res://rain_world.gdshader"),Vector2(0.017,0.32))
    splashes=instances(360,preload("res://rain_splash.gdshader"),Vector2(0.19,0.19))
    rain_material=rain.multimesh.mesh.material
    splash_material=splashes.multimesh.mesh.material
    var converted := {}
    for node in route.get_children():
        if not node is MultiMeshInstance3D: continue
        var material: Material=node.multimesh.mesh.surface_get_material(0)
        if not material in route.wet_materials: continue
        var key:=material.get_instance_id()
        if not converted.has(key):
            var road:=ShaderMaterial.new()
            road.shader=preload("res://wet_road.gdshader")
            road.set_shader_parameter("road_texture",material.albedo_texture)
            road.set_shader_parameter("tint",material.albedo_color)
            converted[key]=road
            road_materials.append(road)
        node.material_override=converted[key]
    for node: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
        var tag := str(node.name).to_lower()
        if not (tag.begins_with("side pane") or tag.begins_with("windshield glass")): continue
        var box := node.get_aabb()
        var size := box.size
        var pane := MeshInstance3D.new()
        var quad := QuadMesh.new()
        var side := size.x < 0.025
        quad.size=Vector2(size.z,size.y) if side else Vector2(size.x,size.y)
        pane.mesh=quad
        node.add_child(pane)
        pane.position=box.get_center()
        if side: pane.rotation.y=PI*0.5
        # Render only one transparent surface per window, without the old solid box.
        node.transparency=1.0
        for surface in node.mesh.get_surface_count():
            var clear := StandardMaterial3D.new()
            clear.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
            clear.albedo_color=Color(1,1,1,0)
            node.set_surface_override_material(surface,clear)
        node.transparency=0.0
        var material := ShaderMaterial.new()
        material.shader=preload("res://rain_glass.gdshader")
        material.set_shader_parameter("glass_size",quad.size)
        pane.material_override=material
        pane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        glass_materials.append(material)
        var local := vehicle.to_local(pane.global_position)
        if not side and local.z>6.0:
            var mask := Image.create(96,96,false,Image.FORMAT_R8)
            mask.fill(Color.WHITE)
            var texture := ImageTexture.create_from_image(mask)
            material.set_shader_parameter("wiped",true)
            material.set_shader_parameter("wiped_mask",texture)
            glass_front.append({"image":mask,"texture":texture,"pane":pane,"size":quad.size})
    set_weather(0.0,0.0)

## `falling` is the rain right now, `lying` the water already on the ground; both 0..1.
func set_weather(falling: float,lying: float) -> void:
    if absf(falling-rain_level)<.002 and absf(lying-puddle_level)<.002 and applied: return
    applied=true
    rain_level=falling
    puddle_level=lying
    rain.visible=falling>.01
    splashes.visible=falling>.01
    for material in glass_materials: material.set_shader_parameter("intensity",maxf(falling,lying*.3))
    for material in [rain_material,splash_material]: material.set_shader_parameter("intensity",falling)
    for material in road_materials:
        material.set_shader_parameter("wetness",maxf(falling,lying))
        material.set_shader_parameter("puddles",lying)
        material.set_shader_parameter("rain",falling)

func update_weather(dt: float, camera: Camera3D, wiper: bool, paused: bool) -> void:
    if rain_level<=.01 and puddle_level<=.01: return
    if not paused: weather_time+=dt
    var origin := camera.global_position.snapped(Vector3(8,1000,8))
    origin.y=0.0
    for node in [rain,splashes]: node.global_position=origin
    for material in [rain_material,splash_material]:
        material.set_shader_parameter("origin",origin)
        material.set_shader_parameter("weather_time",weather_time)
        material.set_shader_parameter("tram_inverse",vehicle.global_transform.affine_inverse())
    for material in glass_materials: material.set_shader_parameter("weather_time",weather_time)
    for material in road_materials: material.set_shader_parameter("weather_time",weather_time)
    mask_timer+=dt
    if mask_timer<0.05 or paused: return
    var elapsed:=mask_timer
    mask_timer=0.0
    var angle: float = cab.pivots["wiper"].rotation.z
    for window in glass_front:
        var mask: Image=window.image
        var pane: Node3D=window.pane
        var size: Vector2=window.size
        var pivot:=vehicle.to_local(cab.pivots["wiper"].global_position)
        var center:=vehicle.to_local(pane.global_position)
        for y in 96:
            for x in 96:
                var point:=center+Vector3((float(x)/95.0-0.5)*size.x,(0.5-float(y)/95.0)*size.y,0)
                var delta:=Vector2(point.x-pivot.x,point.y-pivot.y)
                var a:=atan2(-delta.x,delta.y)
                var cleared:=wiper and delta.length()>0.09 and delta.length()<0.77 and a>=minf(angle,last_wiper_angle)-0.055 and a<=maxf(angle,last_wiper_angle)+0.055
                var water:=0.02 if cleared else minf(1.0,mask.get_pixel(x,y).r+elapsed*0.085)
                mask.set_pixel(x,y,Color(water,water,water,1))
        window.texture.update(mask)
    last_wiper_angle=angle
