extends Node3D

const TRAM = preload("res://assets/tram.glb")
const Route = preload("res://route.gd")
const RailDynamics = preload("res://rail_dynamics.gd")
const CrashBody = preload("res://crash_body.gd")
const TrackCollision = preload("res://track_collision.gd")
const Driver = preload("res://driver.gd")
const Weather = preload("res://weather.gd")
const PassengerEvents = preload("res://passenger_events.gd")
const NpcLife = preload("res://npc_life.gd")
const Preferences = preload("res://preferences.gd")
const Cab = preload("res://cab.gd")
const Display = preload("res://display.gd")
const CAST = ["luca","giulia","samir","elena","amina","marco","mei","matteo","babusia","anna","ravi","didus","sofia","enzo","fatima","yuki","nadia","pietro","ada","noah","clara","ren"]
const GROUP = [0,3,5,8,11,15,17,20,22,22]
const GRANDMOTHER := 8
const GRANDFATHER := 11
const GRANDMOTHER_STOP := 3
const GRANDFATHER_EXIT := 5
# Passengers use the middle and rear doors; the front door beside the cab stays shut.
const PASSENGER_DOORS := [-.81,-5.94]
const EXTRA_RIDERS := 3 # People waiting at each stop besides the regulars.
const CROWD := [14,24,34] # Pedestrians on the pavements, by graphics quality.
const CHAT_PAIRS := 3
const TOP_SPEED := 17.5
const WALK_PACE := 1.22 # Ground speed in m/s that the Walk clip covers at normal playback.
const SEAT_EYE := Vector3(.028,2.29,5.73)
const STAND_EYE := Vector3(.028,2.54,5.72) # Under the windshield header, which ends at 2.59 m.
const STAND_SPOT := Vector2(.028,5.46) # Where the driver stands at the controls: x and z in tram space.
# Floor the driver can walk on: the aisle, the gap to the right of the driver's seat, the cab
# in front of the seat, and the two door vestibules. Each is [x from, x to, z from, z to].
const WALKABLE := [[-.32,.32,-6.15,5.05],[.26,.86,4.85,5.55],[-.60,.86,5.40,5.95],[.32,.95,-1.25,-.37],[.32,.95,-6.35,-5.50]]
static var restart_now := false
const CAPTIONS := {
    "welcome":"Доброго дня! Сідайте, будь ласка. Це перший трамвай, до залізничного вокзалу. Обережно, тут сходинка.",
    "babusia":"Зачекайте, будь ласка! Я ще не сіла!",
    "didus":"Водію, я тут виходжу! Відчиніть, будь ласка, я поспішаю.",
    "depart":"Усі зайшли? Зачиняю двері. Тримайтеся, будь ласка.",
    "levytskoho":"Наступна зупинка — вулиця Левицького.",
    "lychakiv":"Під’їжджаємо до Личаківського цвинтаря.",
    "mytna":"Наступна зупинка — площа Митна.",
    "rynok":"От і площа Ринок. Хто виходить, можете підходити до дверей.",
    "doroshenka":"Наступна зупинка — вулиця Дорошенка.",
    "polytechnic":"За хвилину будемо біля Львівської політехніки.",
    "kropyvnytskoho":"Наступна зупинка — площа Кропивницького. Далі — вокзал.",
    "railway":"Ну от, приїхали. Залізничний вокзал, кінцева. Перевірте, чи нічого не лишилося на сидінні. Гарного дня!"
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
var rain := 0.0 # Falling right now, 0..1.
var puddles := 0.0 # Water lying on the ground, 0..1.
var rain_target := 0.0
var weather_left := 0.0
var sky_applied := -1.0
var derailed := false
var derail_time := 0.0
var dynamics = RailDynamics.new()
var crash: RigidBody3D
var collision_world: Node3D
var acceleration := 0.0
var third_person := false
var upright := false
var stance := 0.0
var foot := STAND_SPOT # The standing driver's position inside the tram.
var foot_speed := 0.0
var stride := 0.0
var hit_wait := 0.0
var third_pivot: Node3D
var third_arm: SpringArm3D
var third_view: Camera3D
var third_yaw := -0.45
var third_pitch := -0.24
var driver: Node3D
var weather: Node3D
var encounters: Node
var life: Node
var preferences: Node
var crash_still_time := 0.0
var rain_loop: AudioStreamPlayer
var web_chunk_timer := 0.0
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
var chatters: Array[Node3D] = []
var transit: Array = [] # Who is stepping through each passenger door right now.
var extras_left := 0
var stop_order := 0
var walker_serial := 0
var grandmother: Node3D
var grandfather: Node3D
var grandfather_requested := false
var people_scenes := {}

func _ready() -> void:
    # The game was renamed: bring settings and career over from the old save folder once.
    if not OS.has_feature("web"):
        var old := OS.get_user_data_dir().get_base_dir().path_join("Ventotto — Львів")
        for file in ["settings.cfg","career.cfg"]:
            if not FileAccess.file_exists("user://"+file) and FileAccess.file_exists(old.path_join(file)):
                DirAccess.copy_absolute(old.path_join(file),ProjectSettings.globalize_path("user://"+file))
    if OS.has_feature("web"): print("WEB_INIT: enter")
    if OS.has_feature("web"):
        print("WEB_INIT: world load")
        line = load("res://web_world.scn").instantiate()
        print("WEB_INIT: world loaded")
        add_child(line)
        line.relink()
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
            for z: float in PASSENGER_DOORS:
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
    view.position = SEAT_EYE
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
    life = NpcLife.new()
    add_child(life)
    life.setup(self)
    # The driver's own body walks with the same relaxed arms as everyone else.
    for clip in ["Idle","Walk"]:
        if driver.walker!=null and driver.walker.has_animation(clip):
            var motion: Animation = driver.walker.get_animation(clip)
            motion.loop_mode = Animation.LOOP_LINEAR
            life.complete(motion,driver.skeleton)
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
    preferences=Preferences.new()
    add_child(preferences)
    preferences.setup(self)
    encounters=PassengerEvents.new()
    add_child(encounters)
    encounters.setup(self)
    if OS.has_feature("web"): print("WEB_INIT: audio")
    setup_audio()
    preferences.apply()
    move_vehicle()
    update_view()
    if OS.has_feature("web"):
        for child in line.get_children():
            if child is GeometryInstance3D:
                child.visible=child.position.distance_to(vehicle.position)<165.
        print("WEB_INIT: ready")
    transit.resize(PASSENGER_DOORS.size())
    if restart_now:
        restart_now = false
        begin_run.call_deferred()

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
    notify("Озвучення увімкнено" if voice_enabled else "Озвучення вимкнено")

func sound(name: String) -> void:
    fx.stream = sounds[name]
    fx.play()

func begin_run() -> void:
    if driving: return
    # Every shift has its own weather, and it keeps changing along the route.
    rain_target = randf_range(.65,1.) if randf()<.35 else 0.
    rain = rain_target
    puddles = .85 if rain_target>0. else 0.
    weather_left = randf_range(60.,130.) if rain_target>0. else randf_range(80.,170.)
    update_sky(0.)
    start()

func restart_run() -> void:
    restart_now = true
    get_tree().reload_current_scene()

## Wet rails: less grip for traction and braking, and easier to derail.
func slippery() -> bool:
    return rain>.3 or puddles>.25

## Rain comes and goes during a shift. Puddles fill while it rains and dry slowly afterwards.
func update_sky(dt: float) -> void:
    weather_left -= dt
    if weather_left<=0.:
        rain_target = 0. if rain_target>0. else randf_range(.65,1.)
        weather_left = randf_range(60.,130.) if rain_target>0. else randf_range(80.,170.)
        notify("Починається дощ · рейки стануть слизькими" if rain_target>0. else "Дощ вщухає")
    rain = move_toward(rain,rain_target,dt/12.)
    puddles = move_toward(puddles,1. if rain>.45 else 0.,dt/(38. if rain>.45 else 140.))
    weather.set_weather(rain,puddles)
    if absf(rain-sky_applied)>.02 or (rain==rain_target and sky_applied!=rain):
        sky_applied = rain
        line.apply_weather(rain)
    if rain>.02 and not rain_loop.playing:
        rain_loop.volume_db = -45.
        rain_loop.play()
    elif rain<=.02 and rain_loop.playing:
        rain_loop.stop()

func curve_limit(index: int) -> int:
    return int(Route.CURVES[index].w)

func operating_limit() -> int:
    var turn: int = line.turn_at(distance,95.)
    return curve_limit(turn) if turn>=0 else line.speed_limit(distance)

func check_curve(dt: float) -> void:
    dynamics.step(line, distance, velocity, acceleration, onboard.size(), slippery(), dt)
    move_vehicle()
    if dynamics.failed_bogie >= 0 and not derailed:
        derailed = true
        throttle = 0
        brake = 4
        voice_queue.clear()
        announcements.stop()
        spoken_caption = ""
        life.silence()
        collision_world.update_near(vehicle.global_position)
        crash = CrashBody.new()
        crash.freeze = true
        add_child(crash)
        crash.global_transform = vehicle.global_transform
        crash.configure(line, dynamics, distance, velocity, slippery())
        vehicle.reparent(crash, true)
        third_arm.add_excluded_object(crash.get_rid())
        crash.freeze = false
        sound("derail")
        notify("Схід з рейок · R — змінити камеру")

func start() -> void:
    if not driving:
        driving = true
        audio_motor.play()
        audio_roll.play()
        speak("welcome")
    paused = false
    rain_loop.stream_paused = false
    announcements.stream_paused = false
    life.hush(false)
    ui.show_menu(false)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if encounters.interacting and encounters.phase!="fight" else Input.MOUSE_MODE_CAPTURED

func pause() -> void:
    paused = true
    rain_loop.stream_paused = true
    announcements.stream_paused = true
    life.hush(true)
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
    if driving: notify("Вид іззовні · миша — огляд" if third_person else "Вид із кабіни")

func update_camera(dt: float) -> void:
    var forward := vehicle.global_basis.z
    var target_heading := atan2(forward.x, forward.z)
    third_pivot.global_position = third_pivot.global_position.lerp(vehicle.global_position + Vector3.UP * 1.8, 1.0-exp(-dt*9.0))
    third_arm.rotation = Vector3(third_pitch, PI + target_heading + third_yaw, 0)
    # G: the driver stands up at the controls or sits back on the stool. Standing, they can walk.
    stance = move_toward(stance,1.0 if upright else 0.0,(0.0 if paused else dt)*1.7)
    if not upright: foot = foot.move_toward(STAND_SPOT,dt*2.5)
    driver.upright = stance
    driver.roam = upright and stance>.98 and (foot.distance_to(STAND_SPOT)>.2 or foot_speed>.05)
    driver.roam_at = Vector3(foot.x,1.082,foot.y)
    driver.roam_yaw = yaw
    driver.roam_speed = foot_speed
    var limit := lerpf(2.11,PI,stance)
    if stance>.98: yaw = wrapf(yaw,-PI,PI)
    elif absf(yaw)>limit:
        yaw = clampf(yaw,-limit,limit)
        update_view()
    if encounters!=null and not encounters.interacting:
        var rise := smoothstep(0.0,1.0,stance)
        # The head follows the tram with a little inertia, more so when standing.
        var inertia := Vector3(life.sway.x,0,life.sway.y)*lerpf(.12,.3,rise)
        stride += foot_speed*dt*3.3
        var bob := sin(stride*2.0)*.014*minf(foot_speed,1.0)
        # At the console the eyes lean over the controls; walking, they stay closer to the body.
        var ahead := lerpf(STAND_EYE.z-STAND_SPOT.y,.17,clampf(foot.distance_to(STAND_SPOT)/.5,0.0,1.0))
        var on_foot := Vector3(foot.x,STAND_EYE.y+bob,foot.y)+Vector3(sin(yaw),0,cos(yaw))*ahead
        view.position = SEAT_EYE.lerp(on_foot,rise)+Vector3(0,0,sin(rise*PI)*.07)+inertia
    driver.animate_controls(cab, 0.0 if paused else dt)
    if encounters!=null: encounters.update_view()
    weather.update_weather(dt, third_view if third_person else view, wiper, paused)
    if rain_loop!=null and rain_loop.playing:
        rain_loop.volume_db=lerpf(rain_loop.volume_db,lerpf(-45.0,-13.0 if third_person else -22.0,rain),minf(dt*3.0,1.0))

func update_view() -> void:
    view.rotation = Vector3(pitch,PI+yaw,0)

func _input(event: InputEvent) -> void:
    if encounters!=null and encounters.handle_input(event): return
    if event is InputEventMouseMotion and driving and not paused:
        if third_person:
            third_yaw -= event.relative.x * 0.003*preferences.sensitivity
            third_pitch = clampf(third_pitch-event.relative.y*0.0025*preferences.sensitivity, -1.1, 0.25)
            return
        var limit := lerpf(2.11,PI,stance)
        yaw -= event.relative.x*.0022*preferences.sensitivity
        yaw = wrapf(yaw,-PI,PI) if stance>.98 else clampf(yaw,-limit,limit)
        pitch = clampf(pitch-event.relative.y*.0022*preferences.sensitivity,-1.14,.43)
        update_view()
    if event is InputEventMouseButton and event.pressed and driving and not paused and not derailed and not third_person:
        if event.button_index==MOUSE_BUTTON_LEFT:
            if not swing(): operate(cab.read_controls(view),1)
        elif event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
            var lever: String = cab.read_controls(view)
            if lever in ["traction","brake","reverser"]:
                operate(lever,1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    if encounters!=null and encounters.interacting and event.physical_keycode!=KEY_ESCAPE: return
    var key := (event as InputEventKey).physical_keycode
    if preferences.opened:
        if key==KEY_ESCAPE:preferences.close_settings()
        return
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
        else: begin_run()
        return
    if not driving or paused: return
    if upright and key in [KEY_A,KEY_D,KEY_W,KEY_S]: return # Walking keys while on foot.
    if upright and not at_controls() and key in [KEY_E,KEY_Q,KEY_Z,KEY_K,KEY_F,KEY_V,KEY_L,KEY_B,KEY_SPACE]:
        notify("Органи керування біля пульта · поверніться до кабіни")
        return
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
        KEY_N: toggle_stance()
        KEY_TAB: ui.toggle_map()
        KEY_ENTER:
            if finished: restart_run()

## G (or N) when no passenger is waiting for the driver.
func toggle_stance() -> void:
    if upright and not (foot.y>5.3 and absf(foot.x-STAND_SPOT.x)<.75):
        notify("Сісти можна лише в кабіні · поверніться до пульта")
        return
    upright = not upright
    notify("Ви встали · W A S D — ходьба · ЛКМ — удар · G — сісти" if upright else "Ви сіли на місце · G — встати")

## Seated, or standing close enough to reach the controls.
func at_controls() -> bool:
    return not upright or foot.distance_to(STAND_SPOT)<.55

func walkable(point: Vector2) -> bool:
    for zone: Array in WALKABLE:
        if point.x>=zone[0] and point.x<=zone[1] and point.y>=zone[2] and point.y<=zone[3]: return true
    return false

## Someone standing in the way: the driver cannot walk through people.
func crowded(point: Vector2) -> bool:
    for p in onboard+transit:
        if not is_instance_valid(p) or p.get_parent()!=vehicle or p.get_meta("life_seat","")=="seated": continue
        var place := Vector2(p.position.x,p.position.z)
        if place.distance_to(point)<.42 and place.distance_to(point)<place.distance_to(foot): return true
    return false

## Walks the standing driver through the cab and saloon. `move` is right / forward input.
func step_on_foot(move: Vector2,dt: float) -> void:
    foot_speed = 0.
    if not upright or stance<.98 or move.length()<.01: return
    move = move.limit_length(1.)
    var forward := Vector2(sin(yaw),cos(yaw))
    var right := Vector2(-cos(yaw),sin(yaw))
    var step := (forward*move.y+right*move.x)*1.5*dt
    # Slide along walls and benches instead of stopping dead.
    for target: Vector2 in [foot+step,foot+Vector2(step.x,0),foot+Vector2(0,step.y)]:
        if target==foot or not walkable(target) or crowded(target): continue
        foot_speed = foot.distance_to(target)/dt
        foot = target
        break
    if not at_controls() and throttle>0:
        throttle = 0
        notify("Ви відійшли від пульта · тягу скинуто")

func person_in_reach() -> Node3D:
    if not upright or stance<.98: return null
    var forward := Vector2(sin(yaw),cos(yaw))
    var best: Node3D = null
    var nearest := 1.15
    for p in onboard+transit:
        if not is_instance_valid(p) or p.get_parent()!=vehicle: continue
        var gap := Vector2(p.position.x,p.position.z)-foot
        if gap.length()<nearest and (gap.length()<.3 or absf(forward.angle_to(gap))<.75):
            nearest = gap.length()
            best = p
    return best

## LMB on foot throws a punch at whoever is within reach. True when the click was a swing
## rather than a press on one of the cab controls.
func swing() -> bool:
    if not upright or stance<.98: return false
    var victim := person_in_reach()
    if victim==null and (at_controls() or not cab.read_controls(view).is_empty()): return false
    if hit_wait>0.: return true
    hit_wait = .6
    driver.punch()
    if victim!=null: encounters.struck(victim)
    return true

func notify(message: String) -> void:
    route_log = message
    notice_left = 3.0

func operate(which: String, delta: int) -> void:
    if cab.controls.has(which): driver.touch_control(which)
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
                notify("Коробка передач: зупиніться й скиньте тягу")
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
                    notify("Екстрене гальмо відпущено")
            else:
                emergency = true
                throttle = 0
                brake = 4
                sound("air")
                notify("Екстрене гальмування")

func distance_to_stop() -> float:
    return Route.STOPS[next_stop]-distance if next_stop<Route.STOPS.size() else 0.

func toggle_doors() -> void:
    if finished: return
    if doors_open:
        if is_processing_passengers():
            notify("Дочекайтеся завершення посадки й висадки")
            return
        doors_open = false
        if next_stop==0: speak("depart")
        next_stop += 1
        if next_stop==Route.STOPS.size():
            finished = true
            throttle = 0
            brake = 4
            notify("Рейс завершено")
        sound("air")
        return
    if absf(velocity)>.11:
        notify("Двері заблоковано під час руху")
    elif absf(distance_to_stop())>2.45:
        notify("Сумістіть кабіну з позначкою F")
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
    return master and reverser!=0 and brake==0 and not emergency and not doors_open and opened_amount<.01 and not finished and not encounters.interacting and at_controls()

func simulate_train(dt: float) -> void:
    var requested := float(brake)/4. if not emergency else 1.
    pressure = move_toward(pressure,requested,dt*(.95 if requested>pressure else .68))
    if doors_open:
        velocity = 0
        return
    var before := velocity
    acceleration = dynamics.longitudinal(velocity, throttle, traction_allowed(), reverser, pressure, emergency, slippery(), onboard.size(), TOP_SPEED)
    velocity += acceleration * dt
    if before * velocity < 0.0 and not traction_allowed(): velocity = 0.0
    velocity = clampf(velocity, -3.5, TOP_SPEED)
    var step := clampf(distance+velocity*dt,-40.,Route.LENGTH+82.)
    var junction: int = line.junction_near(distance+9.,18.)
    if junction>=0 and line.crossing_red(junction,clock):
        var stop_line: float = Route.JUNCTIONS[junction]-9.
        if distance<=stop_line and step>stop_line:
            step = stop_line
            if velocity>1.25:
                notify("Червоний сигнал · спрацювало аварійне гальмування")
                sound("air")
            velocity = 0.
    distance = step
    if distance<=-40. or distance>=Route.LENGTH+82.:
        velocity = 0
    move_vehicle()

func move_vehicle() -> void:
    vehicle.transform = dynamics.body_frame(line.frame(distance))

func make_person(index: int,at: Vector3) -> Node3D:
    # Keeping the scenes loaded avoids re-reading a model each time that person reappears.
    if not people_scenes.has(index): people_scenes[index] = load("res://assets/people/%s.glb" % CAST[index])
    var pack := people_scenes[index] as PackedScene
    if pack==null: return null
    var p := Node3D.new()
    p.name = CAST[index].capitalize()
    p.set_meta("cast_index",index)
    p.add_child(pack.instantiate())
    add_child(p)
    p.position = at
    var players := p.find_children("*","AnimationPlayer",true,false)
    if not players.is_empty():
        var player := players[0] as AnimationPlayer
        p.set_meta("player",player)
        player.speed_scale = .92+float(index%6)*.033
        p.set_meta("tempo",player.speed_scale)
        for clip in ["Idle","Walk"]:
            if player.has_animation(clip): player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
        life.adopt(p)
    return p

func play(p: Node3D,clip: String) -> void:
    if not p.has_meta("player"): return
    var player: AnimationPlayer = p.get_meta("player")
    var now := str(player.current_animation)
    # A gesture or the seated pose from npc_life.gd is not cut short by Idle; walking takes over.
    if clip=="Idle" and (now.begins_with("life/") or now.begins_with("sit/")): return
    if clip=="Walk":
        # The step rate follows ground speed and body size, so feet do not slide.
        player.speed_scale = clampf(float(p.get_meta("pace",WALK_PACE))/(WALK_PACE*float(p.get_meta("life_scale",1.0))),.6,2.1)
    if player.has_animation(clip) and now!=clip:
        if clip!="Walk": player.speed_scale = p.get_meta("tempo",1.0)
        player.clear_queue()
        player.play(clip,.17)

func walk_to(p: Node3D,to: Vector3,dt: float,pace := 1.30) -> bool:
    var delta := to-p.position
    if delta.length()<=maxf(.025,pace*dt):
        p.position = to
        play(p,"Idle")
        return true
    p.position += delta.normalized()*pace*dt
    if absf(delta.x)+absf(delta.z)>.01:
        p.rotation.y = lerp_angle(p.rotation.y,atan2(delta.x,delta.z),minf(dt*7.0,1.0))
    p.set_meta("pace",pace)
    play(p,"Walk")
    return false

## Someone who is not on the tram or at the stop now and is not due at the next few stops.
func spare_cast() -> int:
    var busy := {}
    for p in onboard+queued+outgoing+transit:
        if is_instance_valid(p): busy[p.get_meta("cast_index",-1)] = true
    var soon: int = GROUP[mini(next_stop+4,GROUP.size()-1)]
    for n in CAST.size():
        var index := (n*7+next_stop*5+stop_order*3)%CAST.size()
        if not busy.has(index) and not (index>=GROUP[next_stop] and index<soon): return index
    return -1

func stage_people() -> void:
    if next_stop>=Route.STOPS.size() or absf(distance_to_stop())>115.: return
    if current_group!=next_stop:
        current_group = next_stop
        next_spawn = GROUP[next_stop]
        extras_left = (1 if OS.has_feature("web") else EXTRA_RIDERS) if next_stop<Route.STOPS.size()-1 else 0
        stop_order = 0
    var regular: bool = next_spawn<GROUP[next_stop+1]
    var late: bool = regular and next_spawn==GRANDMOTHER and next_stop==GRANDMOTHER_STOP
    var index := next_spawn
    if not regular or (late and distance_to_stop()>36.):
        # Besides the regulars, a few more people wait at every stop.
        if extras_left<=0: return
        extras_left -= 1
        index = spare_cast()
        if index<0: return
        regular = false
        late = false
    var s: float = Route.STOPS[next_stop]
    var order := stop_order
    stop_order += 1
    var door := order%PASSENGER_DOORS.size()
    var gate: float = PASSENGER_DOORS[door]
    var rank := order/PASSENGER_DOORS.size()
    # People arrive along the platform from either end and wait beside their door.
    var from := s+16.2 if late else (s+gate+10.+rank*1.2 if door==0 else s-8.4+rank*.6)
    var p := make_person(index,line.position_at(3.66 if late else 3.2+float(rank%2)*.5,.285,from))
    if p==null: return
    p.set_meta("spot",line.position_at(2.12+float(rank%2)*.31,.285,s+gate+.7+rank*.85))
    p.set_meta("door",door)
    p.rotation.y = line.heading(from)+(PI if door==0 else 0.)
    if regular:
        p.set_meta("destination",mini(Route.STOPS.size()-1,next_stop+1+next_spawn%3))
        if late:
            grandmother = p
            p.name = "Бабуся"
            speak("babusia")
            notify("Бабуся наздоганяє трамвай. Зупиніться й дочекайтеся її.")
        elif next_spawn==GRANDFATHER:
            grandfather = p
            p.name = "Дідусь"
            p.set_meta("destination",GRANDFATHER_EXIT+1)
        next_spawn += 1
    else:
        p.set_meta("destination",mini(Route.STOPS.size()-1,next_stop+1+(index+order)%4))
        life.restyle(p,index+order)
    queued.append(p)

## The browser version keeps the same life on a smaller scale: every animated person costs it far more.
func crowd_size() -> int:
    return 6 if OS.has_feature("web") else CROWD[preferences.quality]

func chat_pairs() -> int:
    return 1 if OS.has_feature("web") else CHAT_PAIRS

func spawn_walker(slot: int,s: float) -> Node3D:
    walker_serial += 1
    var side := 1. if slot%2==0 else -1.
    var x := side*(6.25+fposmod(slot*.618+walker_serial*.37,1.)*2.)
    var p := make_person((slot*7+walker_serial*5+3)%CAST.size(),line.position_at(x,.178,s))
    if p==null: return null
    life.restyle(p,walker_serial)
    life.simplify(p)
    var speed := .95+fposmod(slot*.37+walker_serial*.21,1.)*.6
    p.set_meta("lateral",x)
    p.set_meta("s",s)
    p.set_meta("stride",speed if (slot/2)%2==0 else -speed)
    p.set_meta("pace",speed)
    p.set_meta("stop_at",clock+randf_range(4.,30.))
    play(p,"Walk")
    return p

func walk_city(dt: float) -> void:
    var want := crowd_size()
    while ambient.size()>want: ambient.pop_back().queue_free()
    for n in 2:
        # The street fills up over the first moments of a shift.
        if ambient.size()<want:
            var fresh := spawn_walker(ambient.size(),distance+randf_range(-30.,125.))
            if fresh!=null: ambient.append(fresh)
    for i in ambient.size():
        var p := ambient[i]
        var s: float = p.get_meta("s")
        var stride: float = p.get_meta("stride")
        var hold: float = p.get_meta("hold",0.)
        var stop_at: float = p.get_meta("stop_at",INF)
        if hold>0.:
            hold -= dt
            p.set_meta("hold",hold)
            if hold<=0.: play(p,"Walk")
        elif clock>=stop_at:
            # Now and then a pedestrian stops for a moment: a phone, a watch, a wave.
            p.set_meta("hold",life.perform(p,"",life.street_pool)+.25)
            p.set_meta("stop_at",clock+randf_range(14.,34.))
        else:
            s += stride*dt
        var beyond := 0.
        if s<distance-38.: beyond = distance+randf_range(96.,128.)
        elif s>distance+132.: beyond = distance-randf_range(28.,36.)
        if beyond!=0.:
            # Out of sight: someone else walks into view at the far end.
            var fresh := spawn_walker(i,beyond)
            if fresh!=null:
                p.queue_free()
                ambient[i] = fresh
                continue
            s = beyond
        p.set_meta("s",s)
        p.position = line.position_at(p.get_meta("lateral"),.179,s)
        p.rotation.y = line.heading(s)+(0. if stride>0 else PI)
        var close := absf(s-distance)<65.
        if close!=p.get_meta("life_shaded",true): life.shade(p,close)
        if OS.has_feature("web"): p.visible = absf(s-distance)<85.
    # Pairs of neighbours stand by the wall; npc_life.gd runs their conversations.
    if chatters.size()<chat_pairs()*2:
        var pair := chatters.size()/2
        var both: Array[Node3D] = []
        for k in 2:
            var p := make_person((pair*9+k*4+walker_serial+1)%CAST.size(),Vector3(0,-50,0))
            if p!=null: both.append(p)
        if both.size()==2:
            for k in 2:
                both[k].set_meta("stander",pair)
                life.restyle(both[k],pair*2+k+1)
                life.simplify(both[k])
            chatters.append_array(both)
            place_chatters(pair,distance+24.+pair*41.)
        else:
            for p in both: p.queue_free()
    for pair in chatters.size()/2:
        var at: float = chatters[pair*2].get_meta("s")
        if at<distance-38.: place_chatters(pair,distance+randf_range(96.,128.))
        elif at>distance+135.: place_chatters(pair,distance-randf_range(28.,36.))

func place_chatters(pair: int,s: float) -> void:
    if line.junction_near(s,10.)>=0: s += 18.
    var side := 1. if (pair+floori(s/60.))%2==0 else -1.
    for k in 2:
        var p := chatters[pair*2+k]
        life.release(p)
        p.set_meta("s",s)
        p.position = line.position_at(side*8.0,.179,s+k*.84)
        p.rotation.y = line.heading(s)+(0. if k==0 else PI)
        play(p,"Idle")

func update_grandfather(dt: float) -> void:
    if not is_instance_valid(grandfather) or not onboard.has(grandfather): return
    if not grandfather_requested and next_stop==GRANDFATHER_EXIT and velocity>.35 and distance-Route.STOPS[GRANDFATHER_EXIT-1]>18.:
        grandfather_requested = true
        grandfather.set_meta("destination",GRANDFATHER_EXIT)
        speak("didus")
        notify("Дідусь просить відчинити на ходу. Випустіть його на наступній зупинці.")
    if grandfather_requested and next_stop==GRANDFATHER_EXIT and not doors_open:
        var near_door := Vector3(.45,1.08,PASSENGER_DOORS[0]+.35)
        if life.rise(grandfather) and walk_to(grandfather,near_door,dt,1.77):
            grandfather.rotation.y = PI/2

func event_hint() -> String:
    if next_stop==GRANDMOTHER_STOP and is_instance_valid(grandmother) and queued.has(grandmother):
        return "Бабуся наздоганяє трамвай · зупиніться й відчиніть двері"
    if next_stop==GRANDFATHER_EXIT and grandfather_requested and is_instance_valid(grandfather) and onboard.has(grandfather):
        return "Дідусь чекає біля дверей · випустіть на зупинці"
    return ""

func move_people(dt: float) -> void:
    for p in departing.duplicate():
        if walk_to(p,p.get_meta("walk_out"),dt):
            departing.erase(p)
            join_street(p)
    for p in queued:
        if p==grandmother and p.has_meta("player"):
            var player: AnimationPlayer = p.get_meta("player")
            player.speed_scale = 1.57
        if walk_to(p,p.get_meta("spot"),dt,2.46 if p==grandmother else 1.30):
            p.rotation.y = lerp_angle(p.rotation.y,p.get_meta("life_face",line.heading(distance)-PI/2),minf(dt*6,1))
    if not doors_open or opened_amount<.70: return
    for door in PASSENGER_DOORS.size(): use_door(door,dt)

## One person at a time passes through each door: those getting off first, then those waiting.
func use_door(door: int,dt: float) -> void:
    var gate: float = PASSENGER_DOORS[door]
    var p: Node3D = transit[door]
    if is_instance_valid(p):
        if not life.rise(p): return # Still getting up from the bench.
        var path: Array = p.get_meta("path")
        var step: int = p.get_meta("path_step")
        if step==0 and not p.get_meta("boarding"): path[0] = Vector3(0,1.08,p.position.z)
        if not walk_to(p,path[step],dt,1.6): return
        if step<path.size()-1:
            p.set_meta("path_step",step+1)
            return
        transit[door] = null
        if p.get_meta("boarding"):
            var seat: Vector3 = p.get_meta("seat")
            p.rotation.y = PI/2 if seat.x<0 else -PI/2
            if p==grandmother: notify("Бабуся встигла сісти")
            onboard.append(p)
            life.settle(p)
            encounters.on_board(p)
            boarded += 1
        else:
            p.reparent(self)
            p.set_meta("walk_out",line.position_at(6.3+randf()*1.6,.179,Route.STOPS[next_stop]+gate+randf_range(-7.,5.)))
            departing.append(p)
            if not p.get_meta("ejected",false): delivered += 1
            if p==grandfather: notify("Дідусь вийшов на зупинці")
        return
    for q in outgoing:
        var nearest := 0
        for d in PASSENGER_DOORS.size():
            if absf(q.position.z-PASSENGER_DOORS[d])<absf(q.position.z-PASSENGER_DOORS[nearest]): nearest = d
        if nearest!=door: continue
        outgoing.erase(q)
        onboard.erase(q)
        q.set_meta("boarding",false)
        q.set_meta("path",[Vector3.ZERO,Vector3(0,1.08,gate),Vector3(.56,1.08,gate),Vector3(1.12,.78,gate),Vector3(1.5,.286,gate)])
        q.set_meta("path_step",0)
        transit[door] = q
        return
    for q in queued:
        if q.get_meta("door",0)!=door: continue
        queued.erase(q)
        q.reparent(vehicle)
        var riders := onboard.duplicate()
        for other in transit:
            if is_instance_valid(other) and other.get_meta("boarding",false): riders.append(other)
        q.set_meta("door_z",gate)
        life.assign_seat(q,riders)
        var seat: Vector3 = q.get_meta("seat")
        q.set_meta("boarding",true)
        q.set_meta("path",[Vector3(1.53,.288,gate),Vector3(1.12,.78,gate),Vector3(.62,1.08,gate),Vector3(0,1.08,gate),Vector3(0,1.08,seat.z),seat])
        q.set_meta("path_step",0)
        transit[door] = q
        return

## A passenger who got off walks away along the pavement like everyone else.
func join_street(p: Node3D) -> void:
    var far := -1
    for i in ambient.size():
        var gap := absf(float(ambient[i].get_meta("s"))-distance)
        if gap>60. and (far<0 or gap>absf(float(ambient[far].get_meta("s"))-distance)): far = i
    if far<0:
        p.queue_free()
        return
    var s: float = line.project_distance(p.position,distance)
    var away := 1. if p.get_meta("cast_index",0)%2==0 else -1.
    var speed := 1.05+fposmod(float(p.get_meta("cast_index",0))*.37,1.)*.4
    p.set_meta("lateral",(p.position-line.position_at(0,0,s)).dot(Vector3.RIGHT.rotated(Vector3.UP,line.heading(s))))
    p.set_meta("s",s)
    p.set_meta("stride",away*speed)
    p.set_meta("pace",speed)
    p.set_meta("stop_at",clock+randf_range(10.,30.))
    for tag in ["path","path_step","boarding","seat","bench","seat_index","walk_out","destination"]:
        if p.has_meta(tag): p.remove_meta(tag)
    ambient[far].queue_free()
    ambient[far] = p
    play(p,"Walk")

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
        update_sky(dt)
        hit_wait = maxf(0.,hit_wait-dt)
        var move := Vector2.ZERO
        if upright and not encounters.interacting:
            move.y = float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
            move.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
        step_on_foot(move,dt)
        life.tick(dt)
        var moving := absf(velocity)
        audio_roll.volume_db = lerpf(-60.,-18.,clampf(moving/10.,0,1))
        audio_roll.pitch_scale = .67+moving*.087
        audio_motor.volume_db = -22.+throttle*2.0 if traction_allowed() and throttle>0 else -60.
        audio_motor.pitch_scale = .77+moving*.105
        switch_hint = "" if third_person or encounters.interacting else cab.read_controls(view)
    else:
        audio_roll.volume_db = -60.
        audio_motor.volume_db = -60.
    var amps := throttle*70.0 if traction_allowed() else 0.
    cab.update_instruments(dt,absf(velocity)*3.6,pressure*6.,amps,throttle,brake,reverser,master,doors_open,wiper)
    encounters.tick(dt)
    ui.refresh(self)

func is_processing_passengers() -> bool:
    if next_stop>=Route.STOPS.size(): return false
    for p in transit:
        if is_instance_valid(p): return true
    return not outgoing.is_empty() or not queued.is_empty() or next_spawn<GROUP[next_stop+1] or extras_left>0
