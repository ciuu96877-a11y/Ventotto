extends Node3D

const STEP := 2.0
const KIT = preload("res://assets/street_kit.glb")
const LANDMARKS = preload("res://assets/lviv_landmarks.glb")
const LENGTH := 12200.0
const START := -100.0
const END := 12370.0
const STOPS := [0.0, 1400.0, 2770.0, 4100.0, 5680.0, 7240.0, 8950.0, 10580.0, 12200.0]
const NAMES := ["Погулянка","Левицького","Личаківський цвинтар","площа Митна","площа Ринок","Дорошенка","Львівська політехніка","площа Кропивницького","Залізничний вокзал"]
const SPEEDS := [35, 48, 50, 32, 45, 52, 48, 53, 35]
# Each entry is curve center, half-length, heading change, and base speed in km/h.
const CURVES := [
    Vector4(310,19.2000,.64,25), Vector4(1040,24.3000,-.72,24),
    Vector4(1700,25.5000,.68,27), Vector4(2400,19.9500,-.70,24),
    Vector4(3120,22.3200,-.62,26), Vector4(3740,18.3600,.72,23),
    Vector4(4490,32.5875,.79,28), Vector4(5240,21.9000,-.73,24),
    Vector4(6060,18.3750,-.70,23), Vector4(6790,25.5600,.71,27),
    Vector4(7550,19.5000,.65,25), Vector4(8130,23.2200,-.72,24), Vector4(8660,15.3600,-.64,23),
    Vector4(9360,27.7500,.74,26), Vector4(10170,17.5500,-.65,24),
    Vector4(10960,25.9200,.72,26), Vector4(11570,18.2400,.64,24), Vector4(11900,19.5000,-.65,24)
]
const JUNCTIONS := [1550.,3440.,4780.,7710.,9700.,11280.]
const STONE := Color("#948a7c")
const STEEL := Color("#737a7c")
const DARK := Color("#3f4442")
const ROAD := Color("#505252")
const KERB := Color("#968f83")
const RAILBED := Color("#6a6761")

@export_storage var collision_boxes: Array[Transform3D] = []
@export_storage var coords := PackedVector3Array()
var groups := {}
var finishes := {}
var kit_meshes := {}
var kit_instances := {}
var rng := RandomNumberGenerator.new()
@export_storage var weather_environment: Environment
@export_storage var daylight: DirectionalLight3D
@export_storage var crossing_cars: Array[Node3D] = []
@export_storage var crossing_lenses: Array[StandardMaterial3D] = []
@export_storage var wet_materials: Array[StandardMaterial3D] = []

func heading(s: float) -> float:
    var angle := 0.0
    for c in CURVES:
        if s<c.x-c.y: break
        angle += c.z*smoothstep(c.x-c.y,c.x+c.y,s)
    return angle

func curvature(s: float) -> float:
    var value := 0.0
    for c in CURVES:
        var u: float = (s - c.x + c.y) / (2.0 * c.y)
        if u > 0.0 and u < 1.0: value += c.z * 6.0 * u * (1.0 - u) / (2.0 * c.y)
    return value

func project_distance(point: Vector3, guess: float) -> float:
    var s := guess
    for i in 4:
        var tangent := Vector3(sin(heading(s)), 0, cos(heading(s)))
        s += clampf((point - position_at(0,0,s)).dot(tangent), -20.0, 20.0)
    return clampf(s, START, END - STEP)

func turn_at(s: float,lookahead := 0.) -> int:
    for i in CURVES.size():
        var c: Vector4 = CURVES[i]
        if s>=c.x-c.y*.66-lookahead and s<=c.x+c.y*.66:
            return i
    return -1

## 0 is a clear day with crisp shadows, 1 a downpour under a low grey sky.
func apply_weather(wet: float) -> void:
    weather_environment.fog_density = lerpf(.004,.019,wet)
    weather_environment.fog_light_color = Color("#c3cbcd").lerp(Color("#7c8a99"),wet)
    weather_environment.ambient_light_energy = lerpf(.56,.48,wet)
    weather_environment.ambient_light_color = Color("#d0dde4").lerp(Color("#98adc1"),wet)
    if daylight!=null:
        daylight.light_energy = lerpf(.95,.30,wet)
        daylight.shadow_opacity = lerpf(1.0,.55,wet) # Overcast light throws soft, pale shadows.
    var sky_material := weather_environment.sky.sky_material as ProceduralSkyMaterial
    sky_material.sky_top_color = Color("#7894aa").lerp(Color("#465969"),wet)
    sky_material.sky_horizon_color = Color("#d7d9d6").lerp(Color("#8091a0"),wet)
    for m in wet_materials:
        m.roughness = lerpf(.89,.48,wet)

func position_at(x: float, y: float, s: float) -> Vector3:
    var u := clampf((s-START)/STEP,0,coords.size()-1.001)
    var a := floori(u)
    return coords[a].lerp(coords[a+1],u-a) + Vector3(x,y,0).rotated(Vector3.UP,heading(s))

func frame(s: float) -> Transform3D:
    return Transform3D(Basis(Vector3.UP,heading(s)),position_at(0,0,s))

func section(s: float) -> int:
    for i in STOPS.size():
        if s < STOPS[i] + 115.0:
            return i
    return STOPS.size()-1

func speed_limit(s: float) -> int:
    return SPEEDS[section(s)]

func place(x: float,y: float,s: float,dim: Vector3,color: Color,kind: StringName = &"paint",yaw := 0.) -> void:
    var key := "%d|%s|%s" % [floori(s/85.0), color.to_html(),kind]
    if not groups.has(key):
        groups[key] = []
        finishes[key] = [color,kind]
    var basis := Basis(Vector3.UP,heading(s)+yaw).scaled_local(dim)
    var placed := Transform3D(basis,position_at(x,y,s))
    groups[key].append(placed)
    if (dim.y >= 4.0 and dim.x >= 3.0 and dim.z >= 3.0) or (dim.y >= 2.0 and dim.x < 0.2 and dim.z < 0.2) or (dim.y >= 0.2 and dim.y <= 0.35 and dim.z >= 6.0):
        collision_boxes.append(placed)

func flush_geometry() -> void:
    var materials := {}
    for key in groups:
        var spec: Array = finishes[key]
        var col: Color = spec[0]
        var kind: StringName = spec[1]
        var mat_key := "%s%s" % [col.to_html(),kind]
        if not materials.has(mat_key):
            var material := StandardMaterial3D.new()
            material.albedo_color = col
            material.roughness = .89
            if kind==&"road" or kind==&"wall" or kind==&"paving":
                material.albedo_texture = load("res://assets/scenery/%s.jpg" % kind)
                if kind==&"road" or kind==&"paving": wet_materials.append(material)
                material.uv1_triplanar = true
                material.uv1_world_triplanar = true
                material.uv1_scale = Vector3.ONE * (1.6 if kind==&"wall" else .48)
                material.uv1_triplanar_sharpness = 5.0
            elif kind==&"rail":
                material.metallic = .60
                material.roughness = .31
            var mesh := BoxMesh.new()
            mesh.size = Vector3.ONE
            mesh.material = material
            materials[mat_key] = mesh
        var transforms: Array = groups[key]
        var batch := MultiMesh.new()
        batch.transform_format = MultiMesh.TRANSFORM_3D
        batch.mesh = materials[mat_key]
        batch.instance_count = transforms.size()
        for i in transforms.size():
            batch.set_instance_transform(i,transforms[i])
        var rendered := MultiMeshInstance3D.new()
        rendered.multimesh = batch
        rendered.visibility_range_end = 250.0
        rendered.visibility_range_end_margin = 14.0
        add_child(rendered)
    groups.clear()
    finishes.clear()

func label_at(label: String,x: float,y: float,s: float,rotation_local: float,pixels: float,ink: Color) -> void:
    var node := Label3D.new()
    node.text = label
    node.font_size = 50
    node.pixel_size = pixels
    node.outline_size = 0
    node.modulate = ink
    node.double_sided = false
    add_child(node)
    node.position = position_at(x,y,s)
    node.rotation.y = heading(s)+rotation_local

func load_kit() -> void:
    for packed: PackedScene in [KIT,LANDMARKS]:
        var source := packed.instantiate()
        for item in source.find_children("*","MeshInstance3D",true,false):
            var key := str(item.name)
            if key.begins_with("KIT_"): kit_meshes[key.trim_prefix("KIT_")] = item.mesh
        source.free()

func detail(name: String,x: float,y: float,s: float,yaw: float) -> void:
    var key := "%s|%d" % [name,floori(s/85.)]
    if not kit_instances.has(key): kit_instances[key] = []
    kit_instances[key].append(Transform3D(Basis(Vector3.UP,heading(s)+yaw),position_at(x,y,s)))

func flush_details() -> void:
    for key in kit_instances:
        var name: String = key.get_slice("|",0)
        if not kit_meshes.has(name):
            push_error("Missing Blender street module " + name)
            continue
        var instances: Array = kit_instances[key]
        var batch := MultiMesh.new()
        batch.transform_format = MultiMesh.TRANSFORM_3D
        batch.mesh = kit_meshes[name]
        batch.instance_count = instances.size()
        for i in instances.size(): batch.set_instance_transform(i,instances[i])
        var model := MultiMeshInstance3D.new()
        model.multimesh = batch
        model.visibility_range_end = 195.
        model.visibility_range_end_margin = 10.
        add_child(model)
    kit_instances.clear()

func setup() -> void:
    rng.seed = 1928
    load_kit()
    coords.append(Vector3(0,0,START))
    for i in range(1,roundi((END-START)/STEP)+1):
        var a := heading(START+(i-.5)*STEP)
        coords.append(coords[-1]+Vector3(sin(a),0,cos(a))*STEP)
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("#7894aa")
    sky_material.sky_horizon_color = Color("#d7d9d6")
    sky_material.ground_horizon_color = Color("#b8b3a9")
    sky_material.sun_angle_max = 24.0
    sky.sky_material = sky_material
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#d0dde4")
    env.ambient_light_energy = .63
    env.fog_enabled = true
    env.fog_light_color = Color("#c3cbcd")
    env.fog_density = .004
    var world := WorldEnvironment.new()
    weather_environment = env
    world.environment = env
    add_child(world)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-42,-27,0)
    light.light_color = Color("#ffe8cf")
    light.light_energy = .72
    light.shadow_enabled = true
    light.directional_shadow_max_distance = 88
    daylight = light
    add_child(light)

    for s in range(-75,int(END)-17,6):
        place(0,-.26,s,Vector3(43,.36,6.45),STONE)
        var historic := s>STOPS[4]-220. and s<STOPS[4]+330.
        place(0,-.055,s,Vector3(12,.17,6.25),RAILBED if historic else ROAD,&"paving" if historic else &"road")
        place(0,.025,s,Vector3(3.22,.024,6.15),RAILBED,&"paving")
        for x in [-.755,.755]:
            place(x,.058,s,Vector3(.071,.028,6.13),STEEL,&"rail")
            place(x+.087,.046,s,Vector3(.028,.013,6.13),Color("#252522"))
        for side in [-1,1]:
            place(side*7.23,.055,s,Vector3(2.56,.24,6.28),STONE,&"paving")
            place(side*5.98,.07,s,Vector3(.22,.22,6.23),KERB)
            if s%12==3:
                place(side*4.92,.037,s,Vector3(.085,.013,2.85),Color("#b3aa96"))
            if s%24==21:
                place(side*5.5,.04,s,Vector3(.24,.015,.38),Color("#343936"))
        place(0,4.43,s,Vector3(.023,.024,6.19),Color("#465151"))

    for s in range(-36,int(END)-44,19):
        var district := section(s)
        var is_square := absf(s-STOPS[4])<47. or absf(s-STOPS[8])<53.
        for side in [-1,1]:
            if is_square and side==1:
                place(14.3,.062,s,Vector3(15.8,.16,19.2),Color("#ada192"),&"paving")
                if absf(s-STOPS[4])>22. and absf(s-STOPS[8])>23.: street_tree(10.4,s+1.9)
            elif (s<180. or district in [2,6] and posmod(s,570)<210) and side==1:
                place(15.7,-.058,s,Vector3(17.,.14,19.3),Color("#7e8565"))
                street_tree(9.9,s+2.8)
                street_tree(14.1,s+7.0)
                street_tree(18.3,s-3.8)
            elif junction_near(s,13.)<0 and s%95!=2:
                building(side,s,district)
            else:
                for line in range(7):
                    place(side*5.02,.041,s-3.9+line*.7,Vector3(1.80,.01,.30),Color("#d1c7b1"))
                street_tree(side*7.1,s-3)
    for i in [4,8]:
        var plaza_center: float = STOPS[i]+5.0
        for j in [-2,-1,0,1,2]:
            var z := plaza_center+float(j)*17.0
            place(23.8,.036,z,Vector3(15.5,.16,17.5),Color("#a59985"),&"paving")
            var h := 9.6+float((j+3)%3)*1.5
            var col: Color = [Color("#b6a187"),Color("#bca88f"),Color("#9d8171")][(j+3)%3]
            place(29.2,h*.5,z,Vector3(6.3,h,16.7),col,&"wall")
            place(29.2,h+.12,z,Vector3(6.7,.30,17.0),Color("#715951"))
            for k in [-2,-1,0,1,2]:
                for y in [3.75,6.35,8.70]:
                    if y+1.12<h: detail("arch" if y==3.75 else "window",26.02,y,z+k*2.8,-PI/2)
    detail("ratusha",14.65,.142,STOPS[4]+5.,-PI/2)
    detail("station",14.85,.142,STOPS[8]+5.,-PI/2)
    for i in [0,4,8]:
        var label_name: String = ["ПОГУЛЯНКА","ПЛОЩА РИНОК","ЛЬВІВ · ВОКЗАЛ"][[0,4,8].find(i)]
        var z: float = STOPS[i]+10.6
        place(5.04,2.83,z,Vector3(3.13,.46,.13),Color("#314e64"))
        label_at(label_name,5.04,2.83,z-.074,PI,.0044,Color("#f0ead9"))
    for s in range(-20,int(END)-31,34):
        for side in [-1,1]:
            place(side*6.10,2.33,s,Vector3(.087,4.56,.085),DARK)
            detail("lamp",side*6.81,.175,s+5.0,PI if side==1 else 0.0)
        place(0,4.55,s,Vector3(12.3,.017,.020),DARK)
    for i in STOPS.size():
        platform(i)
    for i in JUNCTIONS.size():
        build_crossing(i)
    for c in CURVES:
        var z: float = c.x-c.y*.66-89.
        place(4.62,1.00,z,Vector3(.085,2.0,.087),DARK)
        place(4.62,2.02,z,Vector3(.75,.39,.096),Color("#d4ae65"))
        label_at("КРИВА",4.62,2.02,z-.056,PI,.0041,Color("#443322"))
    for i in [1770.,3530.,6410.,9530.]:
        for side in [-1,1]:
            for k in range(10):
                var z: float = i+k*3.6
                place(side*3.92,.57,z,Vector3(.10,1.08,.18),Color("#8d552e"))
                place(side*3.91,.72,z,Vector3(.14,.11,2.95),Color("#bf8e48"))

    flush_geometry()
    flush_details()
    update_crossings(0.,0.)

func junction_near(s: float,radius: float) -> int:
    for i in JUNCTIONS.size():
        if absf(JUNCTIONS[i]-s)<=radius: return i
    return -1

func junction_phase(index: int,time: float) -> float:
    return fposmod(time+index*4.3,23.)

func crossing_red(index: int,time: float) -> bool:
    return junction_phase(index,time)<10.5

func traffic_box(parent: Node3D,pos: Vector3,dim: Vector3,m: Material) -> void:
    var n := MeshInstance3D.new()
    var block := BoxMesh.new()
    block.size = dim
    block.material = m
    n.mesh = block
    parent.add_child(n)
    n.position = pos

func traffic_material(color: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = .5
    return m

func build_crossing(i: int) -> void:
    var s: float = JUNCTIONS[i]
    place(0,-.062,s,Vector3(38.,.16,8.1),ROAD,&"road")
    for lane in [-1,1]:
        for j in range(10):
            place(-5.2+j*1.15,.037,s+lane*5.0,Vector3(.55,.012,1.78),Color("#d3c7ae"))
    place(4.4,1.5,s-8.,Vector3(.115,3,.115),DARK)
    place(4.4,3.14,s-8.,Vector3(.39,.47,.25),DARK)
    var signal_light := Node3D.new()
    add_child(signal_light)
    signal_light.transform = frame(s-8.)
    var lens := traffic_material(Color("#ef6f56"))
    lens.emission_enabled = true
    lens.emission_energy_multiplier = 1.4
    crossing_lenses.append(lens)
    traffic_box(signal_light,Vector3(4.4,3.14,-.136),Vector3(.21,.26,.038),lens)
    var car := Node3D.new()
    add_child(car)
    crossing_cars.append(car)
    var paint := traffic_material([Color("#594745"),Color("#324d5a"),Color("#a18d63")][i%3])
    var rubber := traffic_material(Color("#262a2d"))
    traffic_box(car,Vector3(0,.55,0),Vector3(1.65,.55,3.48),paint)
    traffic_box(car,Vector3(0,.95,-.23),Vector3(1.37,.43,1.90),traffic_material(Color("#47545c")))
    traffic_box(car,Vector3(0,1.18,-.23),Vector3(1.39,.09,1.88),paint)
    for x in [-.79,.79]:
        for z in [-1.04,1.04]:
            traffic_box(car,Vector3(x,.31,z),Vector3(.21,.52,.54),rubber)
    for x in [-.50,.50]:
        traffic_box(car,Vector3(x,.67,1.746),Vector3(.29,.14,.037),traffic_material(Color("#f2ddb7")))
    car.hide()

## A saved copy of the city (the browser version) comes back without its links to the sun
## and the crossing cars. Find them again among the children.
func relink() -> void:
    if daylight==null:
        for child in get_children():
            if child is DirectionalLight3D: daylight = child
    var linked := crossing_cars.size()==JUNCTIONS.size()
    for car in crossing_cars:
        if car==null: linked = false
    if linked: return
    crossing_cars.clear()
    for child in get_children():
        # A car is a bare group of nine boxes; the signal head next to it has only one.
        if child.get_class()=="Node3D" and child.get_child_count()>=5: crossing_cars.append(child)

func update_crossings(time: float,tram: float) -> void:
    if crossing_cars.size()<JUNCTIONS.size() or crossing_lenses.size()<JUNCTIONS.size(): return
    for i in JUNCTIONS.size():
        var s: float = JUNCTIONS[i]
        var phase := junction_phase(i,time)
        var red := crossing_red(i,time)
        var color := Color("#ef624c") if red else Color("#6fca7a")
        var lens := crossing_lenses[i]
        lens.albedo_color = color
        lens.emission = color
        var car := crossing_cars[i]
        car.visible = absf(s-tram)<175. and phase>.7 and phase<9.6
        if car.visible:
            var direction := 1. if i%2==0 else -1.
            car.position = position_at(direction*lerpf(-20.,20.,(phase-.7)/8.9),.035,s)
            car.rotation.y = heading(s)+direction*PI/2

func building(side: int,s: float,district: int) -> void:
    var row := floori(s/19)
    var scheme := [Color("#ba9c83"),Color("#b7a48c"),Color("#9e7867"),Color("#aaa591"),Color("#b7a792"),Color("#ac9181"),Color("#af9b86"),Color("#9c8575"),Color("#b5a69a")]
    var col: Color = scheme[(row+district+2)%scheme.size()]
    var height := rng.randf_range(8.2,16.6)
    var length := rng.randf_range(14.6,18.2)
    var face := 8.63+float(district%3)*.24
    var roof := Color("#69514a") if row%3!=0 else Color("#5c5c53")
    place(side*(face+3.8),height*.5,s,Vector3(7.6,height,length),col,&"wall")
    place(side*(face+3.8),height+.11,s,Vector3(7.92,.30,length+.27),roof)
    place(side*(face+3.9),height+.43,s,Vector3(7.3,.44,length-.6),roof.lightened(.075))
    place(side*(face-.03),2.99,s,Vector3(.29,.20,length),col.lightened(.21),&"wall")
    place(side*(face-.07),1.32,s,Vector3(.16,2.63,length),col.darkened(.15),&"wall")
    var bays := 4 if length<16.1 else 5
    var levels := clampi(floori((height-3.0)/2.7),2,5)
    for k in bays:
        var z := s+(float(k)-(bays-1)*.5)*2.68
        if row%3!=0 and k%2==0:
            detail("shop",side*(face-.02),.17,z,-side*PI/2)
        else:
            place(side*(face-.14),1.39,z,Vector3(.125,2.14,1.64),Color("#61564a"))
            place(side*(face-.23),1.46,z,Vector3(.034,1.75,1.28),Color("#62523d"))
        for floor_number in levels:
            var y := 4.07+floor_number*2.44
            if y+1.24>=height: continue
            detail("arch" if floor_number==0 or (row+district)%3==0 else "window",side*(face-.017),y,z,-side*PI/2)
            if k%2==1 and floor_number==0 and row%3==0:
                place(side*(face-.45),y-.88,z,Vector3(.93,.13,1.63),STONE)
                place(side*(face-.88),y-.48,z,Vector3(.048,.62,1.57),DARK)
                for j in range(5):
                    place(side*(face-.88),y-.48,z-.63+j*.31,Vector3(.061,.59,.031),Color("#64574b"))
    if row%4==0 and s>0:
        var shop: String = ["КАВ’ЯРНЯ","ПЕКАРНЯ","КНИГАРНЯ","КВІТИ","АПТЕКА"][district%5]
        label_at(shop,side*(face-.27),2.76,s,-side*PI/2,.0036,Color("#edddbb"))

func street_tree(x: float,s: float) -> void:
    place(x,1.37,s,Vector3(.22,2.65,.22),Color("#74604b"))
    for j in range(5):
        var tree := MeshInstance3D.new()
        var crown := SphereMesh.new()
        crown.radial_segments = 8
        crown.rings = 4
        crown.radius = .70 + j*.13
        crown.height = 1.35+j*.12
        var m := StandardMaterial3D.new()
        m.albedo_color = Color("#626e4e").lightened(.032*j)
        m.roughness = 1
        crown.material = m
        tree.mesh = crown
        tree.visibility_range_end = 145
        add_child(tree)
        tree.position = position_at(x+sin(j*2.4)*.55,2.8+j*.22,s+cos(j*2.4)*.56)

func plaza(s: float) -> void:
    place(13.5,.025,s,Vector3(14,.23,18.9),Color("#aaa394"),&"paving")
    for i in [-1,1]:
        street_tree(10.0,s+float(i)*5.2)
        place(13.0,.43,s+float(i)*4.7,Vector3(1.22,.52,2.80),STONE,&"wall")
    place(19.1,3.2,s,Vector3(3,6.6,18.4),Color("#b9b1a2"),&"wall")
    for i in [-1,0,1]:
        var z := s+float(i)*5.5
        place(17.53,2.43,z,Vector3(.41,4.6,1.15),Color("#ccc2af"),&"wall")
        place(18.17,5.59,z,Vector3(1.72,2.40,1.50),Color("#bfb5a3"),&"wall")

func platform(i: int) -> void:
    var s: float = STOPS[i]
    place(2.99,.135,s+3.8,Vector3(3.51,.30,25.5),Color("#b0a58f"),&"paving")
    place(1.31,.295,s+3.8,Vector3(.12,.026,25.1),Color("#c3a46d"))
    detail("shelter",4.02,.286,s,PI/2)
    place(4.52,2.28,s+.2,Vector3(.090,.39,3.30),Color("#334440"))
    label_at(NAMES[i],4.46,2.28,s+.2,-PI/2,.0044,Color("#eee0bd"))
    label_at(NAMES[i],4.58,2.28,s+.2,PI/2,.0044,Color("#eee0bd"))
    place(-1.47,.57,s+6.7,Vector3(.07,1.16,.075),Color("#6d5b4b"))
    place(-1.46,1.19,s+6.7,Vector3(.26,.30,.065),Color("#d7c4a4"))
    label_at("F", -1.46,1.19,s+6.66,PI,.0037,Color("#422f26"))
    place(-3.50,1.45,s+64,Vector3(.095,2.95,.095),DARK)
    place(-3.50,2.96,s+64,Vector3(.30,.29,.09),Color("#c7bfa6"))
    label_at(str(SPEEDS[i]),-3.50,2.96,s+63.945,PI,.0035,Color("#262724"))



