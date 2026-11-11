extends Node3D

const TRAM = preload("res://assets/tram.glb")
const Route = preload("res://route.gd")
const RailDynamics = preload("res://rail_dynamics.gd")
const CrashBody = preload("res://crash_body.gd")
const TrackCollision = preload("res://track_collision.gd")
const Driver = preload("res://driver.gd")
const Weather = preload("res://weather.gd")
const Cab = preload("res://cab.gd")
const Display = preload("res://display.gd")
const CAST = ["luca","giulia","samir","elena","amina","marco","mei","matteo","babusia","anna","ravi","didus","sofia","enzo","fatima","yuki","nadia","pietro","ada","noah","clara","ren"]
const GROUP = [0,3,5,8,11,15,17,20,22,22]
const GRANDMOTHER := 8
const GRANDFATHER := 11
const GRANDMOTHER_STOP := 3
const GRANDFATHER_EXIT := 5
const DOOR_Z := 5.63
const MODE_NAMES := ["Лёгкий","Средний","Тяжёлый"]
const MODE_MARGIN := [11,5,0]
const MODE_BRAKES := [1.12,1.0,.65]
const MODE_TOP_SPEED := [14.4,17.5,17.5]
static var restart_mode := -1
const CAPTIONS := {
    "welcome":"Добрый день! Трамвай №1 до железнодорожного вокзала. Осторожно, здесь ступенька.",
    "babusia":"Подождите, пожалуйста! Я ещё не села!",
    "didus":"Водитель, мне выходить! Откройте, пожалуйста, я спешу.",
    "depart":"Все зашли? Закрываю двери. Держитесь, пожалуйста.",
    "levytskoho":"Следующая остановка — улица Левицкого.",
    "lychakiv":"Подъезжаем к Лычаковскому кладбищу.",
    "mytna":"Следующая остановка — Таможенная площадь.",
    "rynok":"Вот и площадь Рынок. Кто выходит, подойдите к дверям.",
    "doroshenka":"Следующая остановка — улица Дорошенко.",
    "polytechnic":"Через минуту будем у Львовской политехники.",
    "kropyvnytskoho":"Следующая — площадь Кропивницкого. Дальше вокзал.",
    "railway":"Приехали. Железнодорожный вокзал, конечная. Проверьте, не забыли ли вещи. Хорошего дня!"
}
const VOICE_STOPS := ["","levytskoho","lychakiv","mytna","rynok","doroshenka","polytechnic","kropyvnytskoho",""]

var line: Node3D
var cab: Node3D
var ui: CanvasLayer
var vehicle: Node3D
var view: Camera3D
var model: Node3D
var doors: Array[Node3D] = []
var home: Array[Vector3] = []
var opened_amount := 0.
var distance := 0.
var velocity := 0.
var throttle := 0
var brake := 4
var pressure := 0.
var reverser := 0
var master := false
var doors_open := false
var wiper := false
var headlights := false
var emergency := false
var driving := false
var paused := false
var finished := false
var difficulty := 0
var derailed := false
var overload := 0.0
var derail_time := 0.0
var dynamics = RailDynamics.new()
var crash: RigidBody3D
var collision_world: Node3D
var acceleration := 0.0
var third_person := false
var third_pivot: Node3D
var third_arm: SpringArm3D
var third_view: Camera3D
var third_yaw := -0.45
var third_pitch := -0.24
var driver: Node3D
var weather: Node3D
var crash_still_time := 0.0
var rain_loop: AudioStreamPlayer
var web_chunk_timer := 0.0
var web_sections := {}
var clock := 0.
var next_stop := 0
var boarded := 0
var delivered := 0
var yaw := 0.
var pitch := -.19
var switch_hint := ""
var route_log := ""
var notice_left := 0.
var beam: SpotLight3D
var audio_motor: AudioStreamPlayer
var audio_roll: AudioStreamPlayer
var fx: AudioStreamPlayer
var sounds := {}
var announcements: AudioStreamPlayer
var voice_queue: Array[String] = []
var voice_enabled := true
var spoken_caption := ""
var spoken_stop := -1

var next_spawn := 0
var current_group := -1
var queued: Array[Node3D] = []
var onboard: Array[Node3D] = []
var outgoing: Array[Node3D] = []
var departing: Array[Node3D] = []
var ambient: Array[Node3D] = []
var boarding: Node3D
var grandmother: Node3D
var grandfather: Node3D
var grandfather_requested := false
var leaving: Node3D
var crowd_sector := -999

func _ready() -> void:
    if OS.has_feature("web"): print("WEB_INIT: enter")
    if OS.has_feature("web"):
        print("WEB_INIT: world load")
        line = load("res://web_world.scn").instantiate()
        print("WEB_INIT: world loaded")
        add_child(line)
    else:
        line = Route.new()
        add_child(line)
        line.setup()
    collision_world = TrackCollision.new()
    add_child(collision_world)
    collision_world.setup(line)
    vehicle = Node3D.new()
    add_child(vehicle)
    if OS.has_feature("web"): print("WEB_INIT: tram")
    model = TRAM.instantiate()
    vehicle.add_child(model)
    var glass: StandardMaterial3D
    for mesh in model.find_children("*","MeshInstance3D",true,false):
        var tag := str(mesh.name).to_lower()
        if tag=="route": mesh.hide()
        if mesh.mesh.get_surface_count()>0:
            var original: Material = mesh.get_active_material(0)
            if original is StandardMaterial3D and original.resource_name.begins_with("Window glass"):
                if glass==null:
                    glass = original.duplicate()
                    glass.albedo_color.a = .095
                mesh.set_surface_override_material(0,glass)
                mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        if tag.begins_with("driver console") or tag.begins_with("instrument fascia") or tag.begins_with("dial ") or tag.begins_with("controller ") or tag.begins_with("brake wheel") or tag.begins_with("driver stool") or tag.begins_with("wiper"):
            mesh.hide()
        var p := vehicle.to_local(mesh.global_position)
        if p.x > 1.1 and (tag.begins_with("folding door lower leaf") or tag.begins_with("door kick plate") or tag.begins_with("door hinge") or tag.begins_with("window jamb") or tag.begins_with("window rail") or tag.begins_with("side pane")):
            for z in [5.63,-.81,-5.94]:
                if absf(p.z-z)<.48:
                    doors.append(mesh)
                    home.append(mesh.position)
                    break
    var destination := Label3D.new()
    destination.text = "1  ВОКЗАЛ"
    destination.font_size = 55
    destination.pixel_size = .00155
    destination.outline_size = 0
    destination.modulate = Color("#f5ebd1")
    vehicle.add_child(destination)
    destination.position = Vector3(0,2.78,6.844)
    if OS.has_feature("web"): print("WEB_INIT: cab")
    cab = Cab.new()
    vehicle.add_child(cab)
    cab.setup()
    cab.finish_interior(model)
    view = Camera3D.new()
    vehicle.add_child(view)
    view.position = Vector3(.028,2.29,5.73)
    view.fov = 70
    view.near = .035
    view.far = 310.
    view.make_current()
    driver = Driver.new()
    vehicle.add_child(driver)
    driver.setup()
    third_pivot = Node3D.new()
    add_child(third_pivot)
    third_arm = SpringArm3D.new()
    third_pivot.add_child(third_arm)
    third_arm.spring_length = 12.5
    third_arm.margin = 0.25
    third_arm.collision_mask = 1
    third_view = Camera3D.new()
    third_arm.add_child(third_view)
    third_view.fov = 66.0
    third_view.near = 0.1
    third_view.far = 310.0
    weather = Weather.new()
    add_child(weather)
    weather.setup(vehicle, model, cab, line)
    beam = SpotLight3D.new()
    vehicle.add_child(beam)
    beam.position = Vector3(0,1.42,6.98)
    beam.rotation.y = PI
    beam.spot_range = 32
    beam.spot_angle = 33
    beam.light_color = Color("#ffdda0")
    beam.light_energy = 1.22
    beam.hide()
    if OS.has_feature("web"): print("WEB_INIT: ui")
    ui = Display.new()
    add_child(ui)
    ui.setup(self)
    if OS.has_feature("web"): print("WEB_INIT: audio")
    setup_audio()
    move_vehicle()
    update_view()
    if OS.has_feature("web"):
        for child in line.get_children():
            if child is GeometryInstance3D:
                child.visible=child.position.distance_to(vehicle.position)<165.
        print("WEB_INIT: ready")
    if restart_mode>=0:
        var selected := restart_mode
        restart_mode = -1
        begin_run.call_deferred(selected)

func loop_sound(name: String) -> AudioStreamPlayer:
    var stream: AudioStreamWAV = sounds[name].duplicate()
    stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    stream.loop_begin = 0
    stream.loop_end = roundi(stream.mix_rate * stream.get_length())
    var player := AudioStreamPlayer.new()
    player.stream = stream
    player.volume_db = -50
    add_child(player)
    return player

func setup_audio() -> void:
    for name in ["motor","rolling","bell","notch","air"]:
        sounds[name] = load("res://assets/scenery/%s.wav" % name)
    audio_motor = loop_sound("motor")
    audio_roll = loop_sound("rolling")
    fx = AudioStreamPlayer.new()
    fx.volume_db = -12
    add_child(fx)
    sounds["rain"] = preload("res://assets/scenery/rain.wav")
    sounds["derail"] = preload("res://assets/scenery/derail.wav")
    rain_loop = loop_sound("rain")
    announcements = AudioStreamPlayer.new()
    announcements.volume_db = -6.
    announcements.finished.connect(play_announcement)
    add_child(announcements)

func speak(clip: String) -> void:
    if not voice_enabled or clip.is_empty(): return
    voice_queue.append(clip)
    if not announcements.playing: play_announcement()

func play_announcement() -> void:
    if voice_queue.is_empty():
        spoken_caption = ""
        return
    var clip: String = voice_queue.pop_front()
    spoken_caption = CAPTIONS[clip]
    announcements.stream = load("res://assets/voice/%s.mp3" % clip)
    announcements.play()

func toggle_voice() -> void:
    voice_enabled = not voice_enabled
    if not voice_enabled:
        voice_queue.clear()
        announcements.stop()
        spoken_caption = ""
    notify("Озвучка включена" if voice_enabled else "Озвучка выключена")

func sound(name: String) -> void:
    fx.stream = sounds[name]
    fx.play()

func begin_run(mode: int) -> void:
    if driving: return
    difficulty = clampi(mode,0,2)
    line.apply_weather(difficulty==2)
    ui.set_rain(difficulty==2)
    weather.set_wet(difficulty==2)
    if difficulty==2:
        rain_loop.volume_db = -17.
        rain_loop.play()
    start()

func restart_run() -> void:
    restart_mode = difficulty
    get_tree().reload_current_scene()

func curve_limit(index: int) -> int:
    return int(Route.CURVES[index].w)

func operating_limit() -> int:
    var turn: int = line.turn_at(distance,95.)
    return curve_limit(turn) if turn>=0 else line.speed_limit(distance)

func check_curve(dt: float) -> void:
    dynamics.step(line, distance, velocity, acceleration, onboard.size(), difficulty==2, dt)
    move_vehicle()
    if dynamics.failed_bogie >= 0 and not derailed:
        derailed = true
        throttle = 0
        brake = 4
        voice_queue.clear()
        announcements.stop()
        spoken_caption = ""
        collision_world.update_near(vehicle.global_position)
        crash = CrashBody.new()
        crash.freeze = true
        add_child(crash)
        crash.global_transform = vehicle.global_transform
        crash.configure(line, dynamics, distance, velocity, difficulty==2)
        vehicle.reparent(crash, true)
        third_arm.add_excluded_object(crash.get_rid())
        crash.freeze = false
        sound("derail")
        notify("Сход с рельсов · R — сменить камеру")

func start() -> void:
    if not driving:
        driving = true
        audio_motor.play()
        audio_roll.play()
        speak("welcome")
    paused = false
    if difficulty==2: rain_loop.stream_paused = false
    announcements.stream_paused = false
    ui.show_menu(false)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func pause() -> void:
    paused = true
    if difficulty==2: rain_loop.stream_paused = true
    announcements.stream_paused = true
    ui.show_menu(true)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
    if what==NOTIFICATION_APPLICATION_FOCUS_OUT and driving and not paused and not derailed:
        pause()

func toggle_camera() -> void:
    third_person = not third_person
    if third_person:
        third_pivot.global_position = vehicle.global_position + Vector3.UP * 1.8
        third_view.make_current()
    else:
        view.make_current()
    driver.set_exterior(third_person)
    if driving: notify("Вид снаружи · мышь — обзор" if third_person else "Вид из кабины")

func update_camera(dt: float) -> void:
    var forward := vehicle.global_basis.z
    var target_heading := atan2(forward.x, forward.z)
    third_pivot.global_position = third_pivot.global_position.lerp(vehicle.global_position + Vector3.UP * 1.8, 1.0-exp(-dt*9.0))
    third_arm.rotation = Vector3(third_pitch, PI + target_heading + third_yaw, 0)
    driver.animate_controls(cab, dt)
    weather.update_weather(dt, third_view if third_person else view, wiper, paused)
    if difficulty==2 and rain_loop!=null:
        rain_loop.volume_db=lerpf(rain_loop.volume_db,-13.0 if third_person else -22.0,minf(dt*3.0,1.0))

func update_view() -> void:
    view.rotation = Vector3(pitch,PI+yaw,0)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and driving and not paused:
        if third_person:
            third_yaw -= event.relative.x * 0.003
            third_pitch = clampf(third_pitch-event.relative.y*0.0025, -1.1, 0.25)
            return
        yaw = clampf(yaw-event.relative.x*.0022,-2.11,2.11)
        pitch = clampf(pitch-event.relative.y*.0022,-1.14,.43)
        update_view()
    if event is InputEventMouseButton and event.pressed and driving and not paused and not derailed and not third_person:
        if event.button_index==MOUSE_BUTTON_LEFT:
            operate(cab.read_controls(view),1)
        elif event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
            var lever: String = cab.read_controls(view)
            if lever in ["traction","brake","reverser"]:
                operate(lever,1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    var key := (event as InputEventKey).physical_keycode
    if key==KEY_R:
        toggle_camera()
        return
    if derailed:
        if key==KEY_ENTER: restart_run()
        return
    if key==KEY_ESCAPE:
        if driving and not paused: pause()
        elif driving: start()
        return
    if key==KEY_ENTER and (not driving or paused):
        if paused: start()
        elif not ui.choosing_mode(): ui.open_modes()
        return
    if not driving or paused: return
    match key:
        KEY_D: operate("traction",1)
        KEY_A: operate("traction",-1)
        KEY_E: operate("brake",1)
        KEY_Q: operate("brake",-1)
        KEY_Z: operate("reverser",1)
        KEY_K: operate("master",1)
        KEY_F: operate("doors",1)
        KEY_V: operate("wiper",1)
        KEY_L: operate("headlights",1)
        KEY_B: operate("bell",1)
        KEY_SPACE: operate("emergency",1)
        KEY_H: ui.toggle_route()
        KEY_M: toggle_voice()
        KEY_TAB: ui.toggle_map()
        KEY_ENTER:
            if finished: restart_run()

func notify(message: String) -> void:
    route_log = message
    notice_left = 3.0

func operate(which: String, delta: int) -> void:
    match which:
        "traction":
            throttle = clampi(throttle+delta,0,5)
            sound("notch")
        "brake":
            brake = clampi(brake+delta,0,4)
            if brake==0 and emergency: brake=1
            sound("air")
        "master":
            master = not master
            if not master: throttle=0
            sound("notch")
        "reverser":
            if absf(velocity)>.12 or throttle>0:
                notify("Реверсор: остановитесь и сбросьте тягу")
            else:
                reverser = posmod(reverser+delta+1,3)-1
                sound("notch")
        "doors": toggle_doors()
        "wiper": wiper = not wiper
        "headlights":
            headlights = not headlights
            beam.visible = headlights
            sound("notch")
        "bell": sound("bell")
        "emergency":
            if emergency:
                if absf(velocity)<.12 and throttle==0:
                    emergency = false
                    notify("Экстренный тормоз снят")
            else:
                emergency = true
                throttle = 0
                brake = 4
                sound("air")
                notify("Экстренное торможение")

func distance_to_stop() -> float:
    return Route.STOPS[next_stop]-distance if next_stop<Route.STOPS.size() else 0.

func toggle_doors() -> void:
    if finished: return
    if doors_open:
        if is_instance_valid(boarding) or is_instance_valid(leaving) or not outgoing.is_empty() or not queued.is_empty() or next_spawn < GROUP[next_stop+1]:
            notify("Дождитесь завершения посадки и высадки")
            return
        doors_open = false
        if next_stop==0: speak("depart")
        next_stop += 1
        if next_stop==Route.STOPS.size():
            finished = true
            throttle = 0
            brake = 4
            notify("Рейс окончен")
        sound("air")
        return
    if absf(velocity)>.11:
        notify("Двери заблокированы в движении")
    elif absf(distance_to_stop())>2.45:
        notify("Совместите кабину с отметкой F")
    else:
        velocity = 0
        doors_open = true
        if next_stop==Route.STOPS.size()-1:
            speak("railway")
        throttle = 0
        brake = maxi(brake,2)
        for person in onboard:
            if person.get_meta("destination")<=next_stop:
                if person==grandfather and grandfather_requested:
                    outgoing.push_front(person)
                else:
                    outgoing.append(person)
        sound("air")

func traction_allowed() -> bool:
    return master and reverser!=0 and brake==0 and not emergency and not doors_open and opened_amount<.01 and not finished

func simulate_train(dt: float) -> void:
    var requested := float(brake)/4. if not emergency else 1.
    pressure = move_toward(pressure,requested,dt*(.95 if requested>pressure else .68))
    if doors_open:
        velocity = 0
        return
    var before := velocity
    acceleration = dynamics.longitudinal(velocity, throttle, traction_allowed(), reverser, pressure, emergency, difficulty==2, onboard.size(), MODE_TOP_SPEED[difficulty])
    velocity += acceleration * dt
    if before * velocity < 0.0 and not traction_allowed(): velocity = 0.0
    velocity = clampf(velocity, -3.5, MODE_TOP_SPEED[difficulty])
    var step := clampf(distance+velocity*dt,-40.,Route.LENGTH+82.)
    var junction: int = line.junction_near(distance+9.,18.)
    if junction>=0 and line.crossing_red(junction,clock):
        var stop_line: float = Route.JUNCTIONS[junction]-9.
        if distance<=stop_line and step>stop_line:
            step = stop_line
            if velocity>1.25:
                notify("Красный сигнал · сработало аварийное торможение")
                sound("air")
            velocity = 0.
    distance = step
    if distance<=-40. or distance>=Route.LENGTH+82.:
        velocity = 0
    move_vehicle()

func move_vehicle() -> void:
    vehicle.transform = dynamics.body_frame(line.frame(distance))

func make_person(index: int,at: Vector3) -> Node3D:
    var path := "res://assets/people/%s.glb" % CAST[index]
    var pack := load(path) as PackedScene
    if pack==null: return null
    var p := Node3D.new()
    p.name = CAST[index].capitalize()
    p.add_child(pack.instantiate())
    add_child(p)
    p.position = at
    var players := p.find_children("*","AnimationPlayer",true,false)
    if not players.is_empty():
        var player := players[0] as AnimationPlayer
        p.set_meta("player",player)
        player.speed_scale = .92+float(index%6)*.033
        for clip in ["Idle","Walk"]:
            if player.has_animation(clip): player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
    return p

func play(p: Node3D,clip: String) -> void:
    if not p.has_meta("player"): return
    var player: AnimationPlayer = p.get_meta("player")
    if player.has_animation(clip) and player.current_animation!=clip: player.play(clip,.17)

func walk_to(p: Node3D,to: Vector3,dt: float,pace := 1.30) -> bool:
    var delta := to-p.position
    if delta.length()<=maxf(.025,pace*dt):
        p.position = to
        play(p,"Idle")
        return true
    p.position += delta.normalized()*pace*dt
    if absf(delta.x)+absf(delta.z)>.01:
        p.rotation.y = lerp_angle(p.rotation.y,atan2(delta.x,delta.z),minf(dt*7.0,1.0))
    play(p,"Walk")
    return false

func stage_people() -> void:
    if next_stop>=Route.STOPS.size() or absf(distance_to_stop())>115.: return
    if current_group!=next_stop:
        current_group = next_stop
        next_spawn = GROUP[next_stop]
    if next_spawn>=GROUP[next_stop+1]: return
    var late := next_spawn==GRANDMOTHER and next_stop==GRANDMOTHER_STOP
    if late and distance_to_stop()>36.: return
    var s: float = Route.STOPS[next_stop]
    var order: int = next_spawn-GROUP[next_stop]
    var from := s+16.2 if late else s+13.8+float(order)*1.33
    var p := make_person(next_spawn,line.position_at(3.66 if late else 4.15,.285,from))
    if p != null:
        p.set_meta("spot",line.position_at(2.12+float(order%2)*.31,.285,s+DOOR_Z+order*1.0))
        p.set_meta("destination",mini(Route.STOPS.size()-1,next_stop+1+next_spawn%3))
        p.rotation.y = line.heading(from)+PI
        if late:
            grandmother = p
            p.name = "Бабуся"
            speak("babusia")
            notify("Бабушка догоняет трамвай. Остановитесь и дождитесь её.")
        elif next_spawn==GRANDFATHER:
            grandfather = p
            p.name = "Дідусь"
            p.set_meta("destination",GRANDFATHER_EXIT+1)
        queued.append(p)
    next_spawn += 1

func walk_city(dt: float) -> void:
    var sector := floori(distance/142.0)
    if sector!=crowd_sector:
        crowd_sector = sector
        for p in ambient: p.queue_free()
        ambient.clear()
    if ambient.size()<6:
        var i := ambient.size()
        var side := 1 if i%2==0 else -1
        var s := distance+18.+float(i)*17.
        var x := side*(6.75+float(i%3)*.37)
        var index := posmod(sector*5+i*3+2,CAST.size())
        var p := make_person(index,line.position_at(x,.178,s))
        if p != null:
            p.set_meta("lateral",x)
            p.set_meta("s",s)
            p.set_meta("stride",(1 if i%3==0 else -1)*(.92+i*.09))
            play(p,"Walk")
            ambient.append(p)
    for p in ambient:
        var s: float = p.get_meta("s")
        var stride: float = p.get_meta("stride")
        s += stride*dt
        if s<distance-35.: s = distance+92.
        if s>distance+127.: s = distance-32.
        p.set_meta("s",s)
        p.position = line.position_at(p.get_meta("lateral"),.179,s)
        p.rotation.y = line.heading(s)+(0. if stride>0 else PI)

func update_grandfather(dt: float) -> void:
    if not is_instance_valid(grandfather) or not onboard.has(grandfather): return
    if not grandfather_requested and next_stop==GRANDFATHER_EXIT and velocity>.35 and distance-Route.STOPS[GRANDFATHER_EXIT-1]>18.:
        grandfather_requested = true
        grandfather.set_meta("destination",GRANDFATHER_EXIT)
        speak("didus")
        notify("Дедушка просит открыть на ходу. Выпустите его на следующей остановке.")
    if grandfather_requested and next_stop==GRANDFATHER_EXIT and not doors_open:
        var near_door := Vector3(.59,1.08,4.82)
        if walk_to(grandfather,near_door,dt,1.77):
            grandfather.rotation.y = PI/2

func event_hint() -> String:
    if next_stop==GRANDMOTHER_STOP and is_instance_valid(grandmother) and queued.has(grandmother):
        return "Бабушка догоняет трамвай · остановитесь и откройте двери"
    if next_stop==GRANDFATHER_EXIT and grandfather_requested and is_instance_valid(grandfather) and onboard.has(grandfather):
        return "Дедушка ждёт у дверей · выпустите на остановке"
    return ""

func move_people(dt: float) -> void:
    for p in departing.duplicate():
        if walk_to(p,p.get_meta("walk_out"),dt):
            departing.erase(p)
            p.queue_free()
    for p in queued:
        if doors_open and p==queued[0] and outgoing.is_empty() and not is_instance_valid(leaving) and not is_instance_valid(boarding):
            continue
        if p==grandmother and p.has_meta("player"):
            var player: AnimationPlayer = p.get_meta("player")
            player.speed_scale = 1.57
        if walk_to(p,p.get_meta("spot"),dt,2.46 if p==grandmother else 1.30):
            p.rotation.y = lerp_angle(p.rotation.y,line.heading(distance)-PI/2,minf(dt*6,1))
    if not doors_open or opened_amount<.70: return
    if is_instance_valid(leaving):
        var step: int = leaving.get_meta("exit_step")
        var target := [Vector3(0,1.08,4.79),Vector3(.56,1.08,DOOR_Z),Vector3(1.12,.78,DOOR_Z),Vector3(1.5,.286,DOOR_Z)]
        if walk_to(leaving,target[step],dt,1.60):
            if step==3:
                leaving.reparent(self)
                leaving.set_meta("walk_out",line.position_at(5.72,.18,Route.STOPS[next_stop]-7.1))
                departing.append(leaving)
                delivered += 1
                if leaving==grandfather: notify("Дедушка вышел на остановке")
                leaving = null
            else: leaving.set_meta("exit_step",step+1)
        return
    if not outgoing.is_empty():
        leaving = outgoing.pop_front()
        onboard.erase(leaving)
        leaving.set_meta("exit_step",0)
        return
    if is_instance_valid(boarding):
        var step: int = boarding.get_meta("entry_step")
        var dest: Vector3 = boarding.get_meta("seat")
        var target := [Vector3(1.12,.78,DOOR_Z),Vector3(.66,1.08,DOOR_Z),Vector3(0,1.08,4.69),Vector3(0,1.08,dest.z),dest]
        if walk_to(boarding,target[step],dt,1.62):
            if step==4:
                boarding.rotation.y = PI/2 if dest.x<0 else -PI/2
                if boarding==grandmother and boarding.has_meta("player"):
                    var player: AnimationPlayer = boarding.get_meta("player")
                    player.speed_scale = 1.0
                    notify("Бабушка успела сесть")
                onboard.append(boarding)
                boarded += 1
                boarding = null
            else: boarding.set_meta("entry_step",step+1)
        return
    if not queued.is_empty():
        var p := queued[0]
        var entry := vehicle.to_global(Vector3(1.53,.288,DOOR_Z))
        if walk_to(p,entry,dt,1.49):
            var occupied := {}
            for rider in onboard: occupied[rider.get_meta("seat_index")] = true
            var slot := 0
            while occupied.has(slot): slot += 1
            queued.pop_front()
            p.reparent(vehicle)
            p.set_meta("entry_step",0)
            p.set_meta("seat_index",slot)
            p.set_meta("seat",Vector3(-.36 if slot%2==0 else .36,1.082,3.94-floori(slot/2.)*1.13))
            boarding = p

func animate_doors(dt: float) -> void:
    var before := opened_amount
    opened_amount = move_toward(opened_amount,1. if doors_open else 0.,dt*1.35)
    if before==opened_amount: return
    for i in doors.size():
        var p := doors[i]
        var origin := home[i]
        var parent := p.get_parent_node_3d()
        var local := vehicle.to_local(parent.to_global(origin))
        var middle := 5.63 if local.z>3. else (-5.94 if local.z < -3. else -.81)
        p.global_position = parent.to_global(origin)+vehicle.global_basis*Vector3(.038*opened_amount,0,signf(local.z-middle)*.31*opened_amount)

func _physics_process(dt: float) -> void:
    if OS.has_feature("web") and is_instance_valid(line):
        web_chunk_timer-=dt
        if web_chunk_timer<=0.:
            web_chunk_timer=.4
            for child in line.get_children():
                if child is GeometryInstance3D:
                    child.visible=child.position.distance_to(vehicle.position)<165.
    collision_world.update_near(vehicle.global_position)
    update_camera(dt)
    if derailed:
        derail_time += dt
        velocity = crash.linear_velocity.length()
        distance = line.project_distance(vehicle.global_position, distance)
        crash_still_time = crash_still_time + dt if velocity < 0.4 else 0.0
        audio_roll.volume_db = lerpf(-60.0,-23.0,clampf(velocity/12.0,0.0,1.0))
        audio_motor.volume_db = -60.0
        ui.refresh(self)
        if crash_still_time > 1.4 and derail_time > 3.0 and not ui.failure.visible:
            ui.show_failure()
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        return
    if driving and not paused:
        clock += dt
        line.update_crossings(clock,distance)
        notice_left = maxf(0.,notice_left-dt)
        simulate_train(dt)
        check_curve(dt)
        if derailed: return
        if next_stop>0 and next_stop<VOICE_STOPS.size() and next_stop!=spoken_stop and distance_to_stop()<80.:
            spoken_stop = next_stop
            speak(VOICE_STOPS[next_stop])
        stage_people()
        walk_city(dt)
        animate_doors(dt)
        update_grandfather(dt)
        move_people(dt)
        var moving := absf(velocity)
        audio_roll.volume_db = lerpf(-60.,-18.,clampf(moving/10.,0,1))
        audio_roll.pitch_scale = .67+moving*.087
        audio_motor.volume_db = -22.+throttle*2.0 if traction_allowed() and throttle>0 else -60.
        audio_motor.pitch_scale = .77+moving*.105
        switch_hint = "" if third_person else cab.read_controls(view)
    else:
        audio_roll.volume_db = -60.
        audio_motor.volume_db = -60.
    var amps := throttle*70.0 if traction_allowed() else 0.
    cab.update_instruments(dt,absf(velocity)*3.6,pressure*6.,amps,throttle,brake,reverser,master,doors_open,wiper)
    ui.refresh(self)

func is_processing_passengers() -> bool:
    if next_stop>=Route.STOPS.size(): return false
    return is_instance_valid(boarding) or is_instance_valid(leaving) or not outgoing.is_empty() or not queued.is_empty() or next_spawn<GROUP[next_stop+1]





