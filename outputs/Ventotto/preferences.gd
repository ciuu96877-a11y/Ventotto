extends Node
var game:Node3D
var opened:=false
var volume:=100.0
var voice_volume:=85.0
var sensitivity:=1.0
var fov:=70.0
var quality:=2
var subtitles:=true
var tutorial:=true # Show the first-shift guide; it switches itself off once done.
var panel:PanelContainer
var tutorial_toggle:CheckButton
var dirty_time:=0.0

func setup(owner_game:Node3D) -> void:
    game=owner_game
    var saved:=ConfigFile.new()
    if saved.load("user://settings.cfg")==OK:
        volume=clampf(saved.get_value("audio","volume",100.0),0,100)
        voice_volume=clampf(saved.get_value("audio","voice",85.0),0,100)
        sensitivity=clampf(saved.get_value("view","sensitivity",1.0),.3,2.5)
        fov=clampf(saved.get_value("view","fov",70.0),60,95)
        quality=clampi(saved.get_value("graphics","quality",2),0,2)
        subtitles=saved.get_value("audio","subtitles",true)
        tutorial=saved.get_value("help","tutorial",true)
    game.ui.anchor(game.ui.title_card,Control.PRESET_CENTER_LEFT,45,-235,479,235)
    var settings:Button=game.ui.menu_button("Налаштування")
    game.ui.action_button.get_parent().add_child(settings)
    settings.pressed.connect(show_settings)
    panel=game.ui.card(game.ui.menu,Color("#222b3af5"))
    game.ui.anchor(panel,Control.PRESET_CENTER,-285,-272,285,272)
    panel.mouse_filter=Control.MOUSE_FILTER_STOP
    var content:VBoxContainer=game.ui.col(panel,13)
    content.add_child(game.ui.text("НАЛАШТУВАННЯ",29,game.ui.WHITE,true))
    slider(content,"Загальна гучність",0,100,volume,"volume")
    slider(content,"Голоси",0,100,voice_volume,"voice_volume")
    slider(content,"Чутливість миші",.3,2.5,sensitivity,"sensitivity")
    slider(content,"Кут огляду",60,95,fov,"fov")
    var graphics:HBoxContainer=game.ui.row(content,10)
    graphics.add_child(game.ui.text("Якість графіки",15,game.ui.FAINT))
    var select:=OptionButton.new()
    for label in ["Низька","Середня","Висока"]:select.add_item(label)
    select.selected=quality
    select.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    graphics.add_child(select)
    select.item_selected.connect(func(value:int):quality=value;apply();dirty_time=.4)
    var captions:=CheckButton.new()
    captions.text="Субтитри"
    captions.button_pressed=subtitles
    content.add_child(captions)
    captions.toggled.connect(func(value:bool):subtitles=value;dirty_time=.4)
    var guide:=CheckButton.new()
    guide.text="Навчання"
    guide.button_pressed=tutorial
    content.add_child(guide)
    guide.toggled.connect(func(value:bool):tutorial=value;dirty_time=.4)
    tutorial_toggle=guide
    if not OS.has_feature("web"):
        var fullscreen:=CheckButton.new()
        fullscreen.text="Повний екран"
        fullscreen.button_pressed=DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN
        fullscreen.toggled.connect(func(value:bool):DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED))
        content.add_child(fullscreen)
    var back:Button=game.ui.menu_button("Зберегти й повернутися")
    content.add_child(back)
    back.pressed.connect(close_settings)
    panel.hide()

func slider(parent:Node,caption:String,minimum:float,maximum:float,value:float,property:String) -> void:
    var line:HBoxContainer=game.ui.row(parent,12)
    var name:Label=game.ui.text(caption,15,game.ui.FAINT)
    name.custom_minimum_size.x=215
    line.add_child(name)
    var input:=HSlider.new()
    input.min_value=minimum
    input.max_value=maximum
    input.step=.05 if property=="sensitivity" else 1.0
    input.value=value
    input.custom_minimum_size.x=180
    input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    line.add_child(input)
    var current:Label=game.ui.text("%.2f" % value if property=="sensitivity" else str(int(value)),14,game.ui.AMBER,true)
    current.custom_minimum_size.x=43
    line.add_child(current)
    input.value_changed.connect(func(next:float):
        set(property,next)
        current.text="%.2f" % next if property=="sensitivity" else str(int(next))
        apply()
        dirty_time=.4
    )

func show_settings() -> void:
    opened=true
    tutorial_toggle.set_pressed_no_signal(tutorial)
    game.ui.title_card.hide()
    panel.show()

func close_settings() -> void:
    save()
    opened=false
    panel.hide()
    game.ui.title_card.show()

func apply() -> void:
    AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,volume/100.0)))
    game.view.fov=fov
    if is_instance_valid(game.announcements):game.announcements.volume_db=linear_to_db(maxf(.0001,voice_volume/100.0))-4.0
    if game.encounters!=null:game.encounters.voice_player.volume_db=linear_to_db(maxf(.0001,voice_volume/100.0))-4.0
    if game.life!=null:game.life.voice_db=linear_to_db(maxf(.0001,voice_volume/100.0))-5.0
    game.weather.rain.multimesh.visible_instance_count=[3000,6500,10000][quality]
    game.weather.splashes.multimesh.visible_instance_count=[90,200,360][quality]
    game.view.far=[180.0,250.0,310.0][quality]
    game.third_view.far=game.view.far
    # Shadows stay on at every quality level on desktop; quality sets how far they reach.
    var sun:DirectionalLight3D=game.line.daylight
    if sun!=null:
        sun.shadow_enabled=not OS.has_feature("web")
        sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality==0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
        sun.directional_shadow_max_distance=[55.0,95.0,140.0][quality]
        sun.directional_shadow_blend_splits=quality>0
    game.beam.shadow_enabled=quality>0 and not OS.has_feature("web")

func save() -> void:
    var file:=ConfigFile.new()
    file.set_value("audio","volume",volume)
    file.set_value("audio","voice",voice_volume)
    file.set_value("audio","subtitles",subtitles)
    file.set_value("help","tutorial",tutorial)
    file.set_value("view","sensitivity",sensitivity)
    file.set_value("view","fov",fov)
    file.set_value("graphics","quality",quality)
    file.save("user://settings.cfg")

func _process(dt:float) -> void:
    if dirty_time>0.0:
        dirty_time-=dt
        if dirty_time<=0.0:save()
