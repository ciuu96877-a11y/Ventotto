extends Node
## Passenger encounters run alongside boarding and never move a running tram.
var game: Node3D
var actor: Node3D
var kind := ""
var phase := "idle"
var interacting := false
var reputation := 60
var cash := 0
var health := 100.0
var stamina := 100.0
var resolve := 100.0
var agitation := 35.0
var attack_clock := 0.0
var attack_cooldown := 0.0
var actor_recoil := 0.0
var actor_rest: Vector3
var actor_skeleton: Skeleton3D
var actor_pose: Array[Quaternion] = []
var elapsed := 0.0
var smooth_seconds := 0.0
var rough_seconds := 0.0
var last_acceleration := 0.0
var help_seconds := -1.0
var result_time := 0.0
var encountered := {}
var panel: PanelContainer
var title: Label
var dialogue: Label
var meters: Label
var choices: Array[Button] = []
var cue: Label
var score: Label
var scenario_panel: PanelContainer
var voice_player: AudioStreamPlayer
var impact_player: AudioStreamPlayer
var message := ""
var result_message := ""
var saved_yaw := 0.0
var saved_pitch := 0.0
var saved_view := Vector3.ZERO
var attack_hit := false
var journey_saved := false
var blocking_requested := false

func setup(owner_game: Node3D) -> void:
    game=owner_game
    voice_player=AudioStreamPlayer.new()
    voice_player.volume_db=-5.0
    add_child(voice_player)
    impact_player=AudioStreamPlayer.new()
    impact_player.volume_db=-13.0
    add_child(impact_player)
    var score_panel:PanelContainer=game.ui.card(game.ui.hud)
    game.ui.anchor(score_panel,Control.PRESET_TOP_LEFT,16,187,176,250)
    score=game.ui.text("",12,game.ui.WHITE,true)
    score_panel.add_child(score)
    var cue_panel:PanelContainer=game.ui.card(game.ui.hud)
    game.ui.anchor(cue_panel,Control.PRESET_TOP_RIGHT,-318,180,-16,264)
    cue=game.ui.text("",14,game.ui.AMBER,true)
    cue.custom_minimum_size.x=270
    cue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    cue_panel.add_child(cue)
    panel=game.ui.card(game.ui.hud,Color("#202b38f2"))
    game.ui.anchor(panel,Control.PRESET_CENTER_RIGHT,-430,-145,-18,245)
    panel.mouse_filter=Control.MOUSE_FILTER_STOP
    var content:VBoxContainer=game.ui.col(panel,10)
    title=game.ui.text("",23,game.ui.AMBER,true)
    content.add_child(title)
    dialogue=game.ui.text("",16,game.ui.WHITE,true)
    dialogue.custom_minimum_size=Vector2(380,74)
    dialogue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    content.add_child(dialogue)
    meters=game.ui.text("",13,game.ui.FAINT)
    meters.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    content.add_child(meters)
    for i in 4:
        var button:Button=game.ui.menu_button("")
        button.add_theme_font_size_override("font_size",14)
        content.add_child(button)
        button.pressed.connect(choose.bind(i))
        choices.append(button)
    scenario_panel=game.ui.card(game.ui.menu,Color("#222b3aeb"))
    game.ui.anchor(scenario_panel,Control.PRESET_CENTER_RIGHT,-370,-155,-30,155)
    scenario_panel.mouse_filter=Control.MOUSE_FILTER_STOP
    var scenarios:VBoxContainer=game.ui.col(scenario_panel,10)
    scenarios.add_child(game.ui.text("СЛОЖНЫЕ ПАССАЖИРЫ",19,game.ui.AMBER,true))
    scenarios.add_child(game.ui.text("Короткие сценарии на остановке",13,game.ui.FAINT))
    var names:=["Пассажир навеселе","Недовольная бабушка","Проверка билетов"]
    for i in names.size():
        var button:Button=game.ui.menu_button(names[i])
        button.pressed.connect(preview.bind(["drunk","grandma","fare"][i]))
        scenarios.add_child(button)
    refresh()

func voice(clip: String) -> void:
    var file:="res://assets/voice/events/"+clip+".mp3"
    if game.voice_enabled and ResourceLoader.exists(file):
        voice_player.stream=load(file)
        voice_player.play()

func impact(blocked: bool) -> void:
    var file:="res://assets/voice/events/"+("block.wav" if blocked else "impact.wav")
    if ResourceLoader.exists(file):
        impact_player.stream=load(file)
        impact_player.play()

func on_board(person: Node3D) -> void:
    var index:int=person.get_meta("cast_index",-1)
    person.set_meta("paid",index!=4)
    if index!=4: cash+=15

func preview(which: String) -> void:
    if game.driving: return
    game.begin_run(1)
    var index:int={"drunk":2,"grandma":8,"fare":4}[which]
    game.set_meta("preview_actor_index",index)
    var person:Node3D=game.make_person(index,Vector3.ZERO)
    person.reparent(game.vehicle,false)
    person.position=Vector3(0,1.082,2.6)
    person.set_meta("seat",person.position)
    person.set_meta("seat_index",10)
    person.set_meta("destination",3)
    person.set_meta("paid",which!="fare")
    game.onboard.append(person)
    game.boarded+=1
    game.voice_queue.clear()
    game.announcements.stop()
    game.spoken_caption=""
    start_event(which,person)

func start_event(which: String,person: Node3D) -> void:
    if phase!="idle" or not is_instance_valid(person): return
    kind=which
    actor=person
    actor_rest=person.position
    actor.set_meta("encounter_busy",true)
    encountered[which]=true
    phase="approach"
    agitation=35.0
    resolve=100.0
    health=100.0
    stamina=100.0
    elapsed=0.0
    message={"drunk":"Пассажир шумит и мешает людям.\n«Чего встал? Мне ехать надо!»","grandma":"«Ты картошку везёшь или людей?\nНа каждом торможении сумка летает!»","fare":"«Я всего одну остановку.\nДавайте в этот раз без билета?»"}[kind]
    voice(kind)
    game.notify("Пассажир зовёт водителя · G после остановки")

func find_person(index: int) -> Node3D:
    for person in game.onboard:
        if person.get_meta("cast_index",-1)==index and not game.outgoing.has(person): return person
    return null

func enter() -> void:
    if not is_instance_valid(actor): game.notify("Пока никто не зовёт водителя");return
    if absf(game.velocity)>.12: game.notify("Сначала остановите вагон, затем нажмите G");return
    if phase not in ["approach","waiting"]: return
    game.throttle=0
    game.brake=4
    game.pressure=1.0
    game.third_person=false
    game.driver.set_exterior(false)
    game.view.make_current()
    saved_yaw=game.yaw
    saved_pitch=game.pitch
    saved_view=game.view.position
    interacting=true
    phase="dialogue"
    game.driver.set_standing(true)
    game.view.position=Vector3(0,2.65,4.36)
    Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
    set_actor_animation(false)
    update_view()
    refresh()

func leave() -> void:
    if not interacting:return
    interacting=false
    game.driver.set_standing(false)
    game.view.position=saved_view
    game.yaw=saved_yaw
    game.pitch=saved_pitch
    game.update_view()
    Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func set_actor_animation(active: bool) -> void:
    if not is_instance_valid(actor): return
    if actor.has_meta("player"):
        var player:AnimationPlayer=actor.get_meta("player")
        player.active=active
        if not active: player.stop()
    if not active:
        actor_skeleton=actor.find_children("*","Skeleton3D",true,false)[0]
        actor_skeleton.reset_bone_poses()
        actor_pose.clear()
        for i in actor_skeleton.get_bone_count():actor_pose.append(actor_skeleton.get_bone_pose_rotation(i))
    elif is_instance_valid(actor_skeleton):
        actor_skeleton.clear_bones_global_pose_override()
        actor_skeleton.reset_bone_poses()
        game.play(actor,"Idle")
        actor_skeleton=null

func update_view() -> void:
    if interacting and is_instance_valid(actor):
        var target:Vector3=actor.global_position+Vector3.UP*1.43
        game.view.look_at(target,Vector3.UP)

func start_fight() -> void:
    phase="fight"
    game.driver.combat=true
    reputation=maxi(0,reputation-5)
    attack_clock=0.0
    attack_hit=false
    attack_cooldown=0.0
    actor_recoil=0.0
    blocking_requested=false
    help_seconds=-1.0
    Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
    voice("fight")

func attack() -> void:
    if phase!="fight" or attack_cooldown>0.0 or stamina<20.0:return
    stamina-=20.0
    attack_cooldown=.60
    var counter:=attack_clock>1.05 and attack_clock<1.78
    resolve-=38.0 if counter else 22.0
    actor_recoil=.45
    game.driver.punch()
    impact(false)
    if counter: attack_clock=0.0;attack_hit=false
    message="Удачный контрудар" if counter else "Пассажир отступил"
    if resolve<=0.0:
        reputation=maxi(0,reputation-3)
        finish("Пассажир прекратил драку. Конфликт стоил репутации.",0,0)

func choose(option: int) -> void:
    if phase=="defeat":game.restart_run();return
    if phase=="result":leave();return
    if phase=="fight":
        if option==0 and help_seconds<0.0:help_seconds=12.0;message="Диспетчер вызвал помощь. Продержитесь.";voice("help")
        elif option==1:
            finish("Вы закрылись в кабине. Диспетчер займётся нарушителем.",-3,0)
            leave()
        return
    if phase!="dialogue":return
    if kind=="drunk":
        if option==0:
            if agitation<65.0:finish("Разговор помог. Пассажир успокоился.",6,0)
            else:message="Он уже слишком разозлился и замахивается.";start_fight()
        elif option==1:eject()
        elif option==2:start_fight()
        else:
            phase="help"
            help_seconds=8.0
            message="Диспетчер вызвал помощь. Вагон удерживается тормозом."
            voice("help")
    elif kind=="grandma":
        if option==0:
            phase="smooth"
            smooth_seconds=0.0
            rough_seconds=0.0
            elapsed=0.0
            result_message="20 секунд плавной езды: без резких разгонов и торможений."
            voice("promise")
            leave()
            set_actor_animation(true)
        elif option==1:finish("Вы извинились и помогли устроиться удобнее.",3,0)
        elif option==2:finish("Бабушка обещала жалобу в депо.",-10,-20)
        else:leave();phase="waiting"
    elif kind=="fare":
        if option==0:
            actor.set_meta("paid",true)
            finish("Билет оплачен: +15 грн.",3,15)
        elif option==1:finish("Вы ограничились предупреждением.",1,0)
        elif option==2:eject()
        else:leave();phase="waiting"
    refresh()

func eject() -> void:
    if not game.doors_open or absf(game.distance_to_stop())>2.45:
        message="Высадка возможна на остановке с открытыми дверями. F — двери; G — вернуться к управлению."
        return
    actor.set_meta("destination",game.next_stop)
    actor.set_meta("ejected",true)
    if not game.outgoing.has(actor):game.outgoing.append(actor)
    finish("Пассажир выходит на остановке.",2,0,true)

func finish(text: String,rep: int,money: int,ejected:=false) -> void:
    reputation=clampi(reputation+rep,0,100)
    cash=maxi(0,cash+money)
    result_message=text
    result_time=5.0
    phase="result"
    help_seconds=-1.0
    if is_instance_valid(actor):
        actor.set_meta("encounter_busy",false)
        set_actor_animation(true)
        if ejected:actor=null
    game.driver.guard=false
    game.driver.combat=false
    voice("calm" if rep>=0 else "complaint")
    if interacting:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
    game.notify(text)

func handle_input(event: InputEvent) -> bool:
    if not game.driving or game.paused or game.derailed or game.finished:return false
    if interacting and phase=="fight":
        if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
            blocking_requested=event.pressed
            get_viewport().set_input_as_handled()
            return true
        if event is InputEventKey and event.physical_keycode==KEY_SHIFT:
            blocking_requested=event.pressed
            get_viewport().set_input_as_handled()
            return true
    if event is InputEventKey and event.pressed and not event.echo:
        var key:int=event.physical_keycode
        if key==KEY_G:
            if phase=="defeat":get_viewport().set_input_as_handled();return true
            if interacting:
                if phase=="fight":choose(1)
                else:leave();phase="waiting" if phase=="dialogue" else phase
            else:enter()
            get_viewport().set_input_as_handled()
            return true
        if interacting:
            if key==KEY_ESCAPE:return false
            if key==KEY_ENTER and phase in ["result","defeat"]:choose(0)
            elif key>=KEY_1 and key<=KEY_4:choose(key-KEY_1)
            elif key==KEY_F and phase=="dialogue":game.toggle_doors()
            get_viewport().set_input_as_handled()
            return true
    if interacting and event is InputEventMouseButton and phase=="fight":
        if event.pressed and event.button_index==MOUSE_BUTTON_LEFT:attack()
        get_viewport().set_input_as_handled()
    return interacting

func animate_actor(dt: float) -> void:
    if not is_instance_valid(actor_skeleton) or actor_pose.is_empty():return
    var windup:=smoothstep(.9,1.45,attack_clock)*(1.0-smoothstep(1.72,2.05,attack_clock)) if phase=="fight" else 0.0
    var sway:=sin(elapsed*1.8)*(.035 if kind=="drunk" else .008)
    actor_skeleton.clear_bones_global_pose_override()
    for item in [["spine_02",Vector3.FORWARD,sway]]:
        var id:=actor_skeleton.find_bone(item[0])
        if id>=0:actor_skeleton.set_bone_pose_rotation(id,actor_pose[id]*Quaternion(item[1],item[2]))
    actor_recoil=maxf(0.0,actor_recoil-dt)
    for side in ["l","r"]:
        var sign_x:=1.0 if side=="l" else -1.0
        var target:=Vector3(sign_x*.23,.94,.16)
        if phase=="fight":
            target=Vector3(sign_x*.23,1.25,.28)
            if side=="r":
                target=target.lerp(Vector3(-.24,1.42,.06),windup)
                var extension:=sin(clampf((attack_clock-1.50)/.47,0,1)*PI)
                target=target.lerp(Vector3(-.08,1.35,.63),extension)
        bend_actor_arm(side,target)
        for finger in ["index","middle","ring","pinky","thumb"]:
            for part in ["01","02","03"]:
                var id:=actor_skeleton.find_bone(finger+"_"+part+"_"+side)
                if id>=0:actor_skeleton.set_bone_pose_rotation(id,actor_pose[id]*Quaternion(Vector3.RIGHT,.60 if phase=="fight" else .05))
    actor.position.z=2.95-sin(actor_recoil/.45*PI)*.24
    actor.position.x=sin(elapsed*1.1)*.035
    actor.rotation.y=atan2(-actor.position.x,4.40-actor.position.z)

func bend_actor_arm(side: String,target: Vector3) -> void:
    var a:=actor_skeleton.find_bone("upperarm_"+side)
    var b:=actor_skeleton.find_bone("lowerarm_"+side)
    var c:=actor_skeleton.find_bone("hand_"+side)
    var start:=actor_skeleton.get_bone_global_pose(a).origin
    target*=actor_skeleton.get_bone_global_rest(a).origin.y/1.388
    var la:=actor_skeleton.get_bone_global_rest(a).origin.distance_to(actor_skeleton.get_bone_global_rest(b).origin)
    var lb:=actor_skeleton.get_bone_global_rest(b).origin.distance_to(actor_skeleton.get_bone_global_rest(c).origin)
    var delta:=target-start
    var distance:=clampf(delta.length(),.08,(la+lb)*.95)
    var forward:=delta.normalized()
    var pole:=Vector3(.35 if side=="l" else -.35,-1,0)
    var bend:=(pole-forward*pole.dot(forward)).normalized()
    var along:=(la*la+distance*distance-lb*lb)/(2.0*distance)
    var elbow:=start+forward*along+bend*sqrt(maxf(0,la*la-along*along))
    for item in [[a,b,elbow],[b,c,start+forward*distance]]:
        var pose:=actor_skeleton.get_bone_global_pose(item[0])
        var from:=(actor_skeleton.get_bone_global_pose(item[1]).origin-pose.origin).normalized()
        var to:Vector3=(item[2]-pose.origin).normalized()
        pose.basis=Basis(Quaternion(from,to))*pose.basis
        actor_skeleton.set_bone_global_pose_override(item[0],pose,1.0,true)
        actor_skeleton.force_update_all_bone_transforms()

func tick(dt: float) -> void:
    voice_player.stream_paused=game.paused
    if not game.driving or game.paused or game.derailed:
        blocking_requested=false
        refresh()
        return
    elapsed+=dt
    stamina=minf(100.0,stamina+dt*13.0)
    attack_cooldown=maxf(0.0,attack_cooldown-dt)
    if phase=="idle":
        if not encountered.has("drunk") and game.next_stop>=1 and game.distance>22.0:
            var p:=find_person(2)
            if p!=null:start_event("drunk",p)
        elif not encountered.has("fare") and game.next_stop>=2:
            var p:=find_person(4)
            if p!=null:start_event("fare",p)
        elif not encountered.has("grandma") and game.next_stop>=4:
            var p:=find_person(8)
            if p!=null:start_event("grandma",p)
    elif phase in ["approach","waiting"]:
        if not is_instance_valid(actor) or not game.onboard.has(actor):phase="idle";actor=null
        else:
            if game.walk_to(actor,Vector3(0,1.082,2.95),dt,1.1):phase="waiting"
            actor.rotation.y=0.0
            agitation=minf(100.0,agitation+dt*(.28+maxf(0.0,absf(game.acceleration)-.8)*6.0))
    elif phase=="fight":
        game.driver.guard=blocking_requested
        attack_clock+=dt
        if attack_clock>=1.78 and not attack_hit:
            attack_hit=true
            var blocked:bool=game.driver.guard and stamina>=9.0
            if blocked:stamina-=9.0;resolve-=4.0;message="Удар заблокирован"
            else:health-=10.0+game.difficulty*3.0;message="Пропущен удар"
            impact(blocked)
            if health<=0.0:
                health=0.0
                reputation=maxi(0,reputation-12)
                phase="defeat"
                game.driver.guard=false
                Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
        if attack_clock>2.55:attack_clock=0.0;attack_hit=false
        if help_seconds>=0.0:
            help_seconds-=dt
            if help_seconds<=0.0:finish("Помощь прибыла. Нарушитель успокоился.",1,0)
    elif phase=="help":
        help_seconds-=dt
        if help_seconds<=0.0:finish("Диспетчер помог разрешить конфликт.",4,0)
    elif phase=="smooth":
        if is_instance_valid(actor):game.walk_to(actor,actor_rest,dt,1.0)
        var jerk:float=absf(game.acceleration-last_acceleration)/maxf(dt,.001)
        if absf(game.velocity)>1.0:
            if absf(game.acceleration)<.95 and jerk<2.4:smooth_seconds+=dt
            else:rough_seconds+=dt
        if smooth_seconds>=20.0:finish("Бабушка довольна: «Вот теперь хорошо!» Чаевые +10 грн.",8,10)
        elif rough_seconds>=3.5:finish("Обещание нарушено. Бабушка написала жалобу.",-6,0)
    elif phase=="result":
        result_time-=dt
        if is_instance_valid(actor) and not game.outgoing.has(actor):game.walk_to(actor,actor_rest,dt,1.1)
        if result_time<=0.0 and not interacting:phase="idle";actor=null
    if phase in ["dialogue","fight","help","defeat"]:animate_actor(dt)
    last_acceleration=game.acceleration
    if game.finished and not journey_saved:
        journey_saved=true
        var career:=ConfigFile.new()
        career.load("user://career.cfg")
        career.set_value("career","completed_runs",int(career.get_value("career","completed_runs",0))+1)
        career.set_value("career","best_reputation",maxi(reputation,int(career.get_value("career","best_reputation",0))))
        career.set_value("career","total_income",cash+int(career.get_value("career","total_income",0)))
        career.save("user://career.cfg")
    refresh()

func refresh() -> void:
    if panel==null:return
    score.text="ЗА СМЕНУ  %d грн\nРЕПУТАЦИЯ  %d / 100" % [cash,reputation]
    scenario_panel.visible=not game.driving and not game.ui.choosing_mode() and not game.preferences.opened
    panel.visible=interacting
    cue.get_parent().visible=not interacting and phase!="idle"
    if phase=="smooth":cue.text="Плавная езда: %d / 20 с\nБез резких ускорений" % int(smooth_seconds)
    elif phase=="result":cue.text=result_message
    else:cue.text="Пассажир зовёт водителя\nG — поговорить после остановки"
    if not interacting:return
    var labels:Array[String]=[]
    title.text={"drunk":"Пассажир навеселе","grandma":"Недовольная бабушка","fare":"Проверка билетов"}.get(kind,"")
    dialogue.text=message
    meters.text="Репутация %d / 100   ·   Касса %d грн" % [reputation,cash]
    if phase=="fight":
        title.text="КОНФЛИКТ В САЛОНЕ"
        dialogue.text="Замах! Блокируйте!" if attack_clock>.95 and attack_clock<1.78 else message
        meters.text="Здоровье %d   Выносливость %d\nНапор пассажира %d\nЛКМ — удар · ПКМ / Shift — блок\n" % [int(health),int(stamina),maxi(0,int(resolve))]
        if help_seconds>=0.0:meters.text+="Помощь: %d с" % ceili(help_seconds)
        labels=["1  Вызвать помощь","2  Отступить в кабину"]
    elif phase=="defeat":
        title.text="РЕЙС ПРЕРВАН"
        dialogue.text="Водитель пострадал в драке. Рейс продолжить нельзя."
        labels=["Enter  Начать заново"]
    elif phase=="result":dialogue.text=result_message;labels=["Enter  Вернуться к управлению"]
    elif phase=="help":meters.text="Помощь: %d с" % ceili(help_seconds)
    elif kind=="drunk":
        meters.text+="\nРаздражение: %d / 100" % int(agitation)
        labels=["1  Спокойно поговорить","2  Высадить на остановке","3  Оттеснить от кабины","4  Вызвать помощь"]
    elif kind=="grandma":labels=["1  Обещать плавную езду","2  Помочь устроиться удобнее","3  Начать спорить","4  Вернуться к управлению"]
    elif kind=="fare":labels=["1  Попросить оплатить билет","2  Сделать предупреждение","3  Высадить на остановке","4  Вернуться к управлению"]
    for i in choices.size():
        choices[i].visible=i<labels.size()
        if i<labels.size():choices[i].text=labels[i]
