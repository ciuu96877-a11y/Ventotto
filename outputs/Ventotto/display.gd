extends CanvasLayer

const WHITE := Color("#fff5e2")
const FAINT := Color("#ded4c1")
const AMBER := Color("#ffc250")
const GREEN := Color("#94ca50")
const ALERT := Color("#ff9a58")
const BACK := Color("#262b38b9")
const CONTROL_NAMES := {"traction":"Контроллер тяги","brake":"Пневматический тормоз","master":"Главный выключатель","reverser":"Реверсор","doors":"Двери","wiper":"Стеклоочиститель","headlights":"Фара","bell":"Звонок"}

class TramIcon extends Control:
    var tint := Color("#94ca50")

    func pill(at: Vector2,size: Vector2,radius: int,ink: Color) -> void:
        var shape := StyleBoxFlat.new()
        shape.bg_color = ink
        shape.set_corner_radius_all(radius)
        draw_style_box(shape,Rect2(at,size))

    func _draw() -> void:
        var x := size.x*.5
        pill(Vector2(x-19,5),Vector2(38,99),14,tint)
        pill(Vector2(x-29,22),Vector2(58,14),6,tint)
        pill(Vector2(x-29,73),Vector2(58,14),6,tint)
        var window := Color("#293842")
        pill(Vector2(x-12,12),Vector2(24,10),4,window)
        pill(Vector2(x-11,42),Vector2(22,22),6,window)
        pill(Vector2(x-12,89),Vector2(24,8),3,window)
        draw_circle(Vector2(x-9,27),2.4,WHITE,true,-1.0,true)
        draw_circle(Vector2(x+9,27),2.4,WHITE,true,-1.0,true)

var bold: Font
var hud: Control
var instruments: PanelContainer
var prompt: Label
var train_state: Label
var door_state: Label
var train_icon: TramIcon
var speed: Label
var traction: Label
var brake: Label
var direction: Label
var goal: Label
var bar: ProgressBar
var count: Label
var delivered: Label
var alert_card: PanelContainer
var alert_text: Label
var crosshair: Label
var interaction: Label
var subtitle: Label
var menu: Control
var action_button: Button
var title_card: PanelContainer
var modes: PanelContainer
var mode_focus: Button
var failure: Control
var rain_overlay: ColorRect
var rain_material: ShaderMaterial
var run_started := false
var mode_info: Label
var controls_panel: PanelContainer
var map_panel: PanelContainer
var route_nodes: Array[Label] = []
var show_route := true

func text(content: String,size: int,tint: Color,weight := false) -> Label:
    var n := Label.new()
    n.text = content
    n.add_theme_font_size_override("font_size",size)
    n.add_theme_color_override("font_color",tint)
    if OS.has_feature("web"):
        n.text = content.replace("◆",">").replace("◉","П").replace("●","*").replace("○","o").replace("←","<").replace("↵","Enter")
    if weight: n.add_theme_font_override("font",bold)
    return n

func style(color: Color,radius := 12,x := 13,y := 9,shadow := true) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = color
    s.set_corner_radius_all(radius)
    s.corner_detail = 9
    s.content_margin_left = x
    s.content_margin_right = x
    s.content_margin_top = y
    s.content_margin_bottom = y
    if shadow:
        s.shadow_color = Color("#090e1a57")
        s.shadow_size = 7
        s.shadow_offset = Vector2(0,4)
    return s

func card(parent: Control,fill: Color = BACK,shadow := true) -> PanelContainer:
    var n := PanelContainer.new()
    n.add_theme_stylebox_override("panel",style(fill,12,13,9,shadow))
    n.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(n)
    return n

func col(parent: Control,gap := 4) -> VBoxContainer:
    var n := VBoxContainer.new()
    n.add_theme_constant_override("separation",gap)
    parent.add_child(n)
    return n

func row(parent: Control,gap := 8) -> HBoxContainer:
    var n := HBoxContainer.new()
    n.add_theme_constant_override("separation",gap)
    parent.add_child(n)
    return n

func anchor(node: Control,preset: int,l: float,t: float,r: float,b: float) -> void:
    node.set_anchors_and_offsets_preset(preset)
    node.offset_left = l
    node.offset_top = t
    node.offset_right = r
    node.offset_bottom = b

func metric(parent: Control,caption: String,width: float) -> Label:
    var group := col(parent,0)
    group.custom_minimum_size.x = width
    group.add_child(text(caption,11,FAINT,true))
    var value := text("",19,WHITE,true)
    group.add_child(value)
    return value

func setup(game: Node) -> void:
    bold = SystemFont.new()
    if OS.has_feature("web"):
        bold = ThemeDB.fallback_font
    else:
        bold.font_names = PackedStringArray(["Segoe UI","Arial"])
        bold.font_weight = 750
    var weather_layer := Control.new()
    add_child(weather_layer)
    weather_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    weather_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rain_overlay = ColorRect.new()
    weather_layer.add_child(rain_overlay)
    rain_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    rain_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rain_material = ShaderMaterial.new()
    rain_material.shader = preload("res://rain.gdshader")
    rain_overlay.material = rain_material
    rain_overlay.hide()

    hud = Control.new()
    add_child(hud)
    hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var wagon := card(hud)
    anchor(wagon,Control.PRESET_TOP_LEFT,16,16,176,176)
    var wagon_inner := col(wagon,3)
    var wagon_header := row(wagon_inner,8)
    var title := text("ВАГОН",12,FAINT,true)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    wagon_header.add_child(title)
    train_state = text("1565",14,GREEN,true)
    wagon_header.add_child(train_state)
    train_icon = TramIcon.new()
    train_icon.custom_minimum_size = Vector2(105,110)
    wagon_inner.add_child(train_icon)
    door_state = text("",12,WHITE,true)
    wagon_inner.add_child(door_state)

    var task := card(hud,Color("#333e50c0"),false)
    anchor(task,Control.PRESET_CENTER_TOP,-274,14,274,48)
    var task_row := row(task,8)
    task_row.add_child(text("◆",14,ALERT,true))
    prompt = text("",16,WHITE,true)
    task_row.add_child(prompt)
    instruments = card(hud,Color("#232736c7"))
    anchor(instruments,Control.PRESET_CENTER_TOP,-297,55,297,148)
    var instruments_inner := col(instruments,6)
    var metrics := row(instruments_inner,14)
    speed = metric(metrics,"СКОРОСТЬ",108)
    traction = metric(metrics,"ТЯГА",69)
    brake = metric(metrics,"ТОРМОЗ",81)
    direction = metric(metrics,"РЕВЕРСОР",91)
    var right := col(metrics,0)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mode_info = text("Т01  ·  ЛЬВІВ",11,FAINT,true)
    right.add_child(mode_info)
    var power := ProgressBar.new()
    power.name = "Power"
    power.show_percentage = false
    power.custom_minimum_size.y = 8
    power.max_value = 5
    power.add_theme_stylebox_override("background",style(Color("#7f8b9d71"),5,0,0,false))
    power.add_theme_stylebox_override("fill",style(GREEN,5,0,0,false))
    right.add_child(power)
    var path := row(instruments_inner,8)
    path.add_child(text("◆",11,FAINT,true))
    bar = ProgressBar.new()
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.custom_minimum_size.y = 6
    bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    bar.show_percentage = false
    bar.max_value = game.Route.LENGTH
    bar.add_theme_stylebox_override("background",style(Color("#9da6b18f"),5,0,0,false))
    bar.add_theme_stylebox_override("fill",style(GREEN,5,0,0,false))
    path.add_child(bar)
    path.add_child(text("◆",11,ALERT,true))
    goal = text("",14,WHITE,true)
    path.add_child(goal)

    var passengers := card(hud)
    anchor(passengers,Control.PRESET_TOP_RIGHT,-232,16,-16,84)
    var passengers_inner := col(passengers,1)
    var passengers_row := row(passengers_inner,12)
    var icon := text("◉",25,AMBER,true)
    passengers_row.add_child(icon)
    count = text("",24,WHITE,true)
    if OS.has_feature("web"): count.add_theme_font_size_override("font_size",21)
    count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    passengers_row.add_child(count)
    delivered = text("",12,FAINT,true)
    if OS.has_feature("web"): delivered.add_theme_font_size_override("font_size",11)
    delivered.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    passengers_inner.add_child(delivered)
    alert_card = card(hud,Color("#37394ab8"),false)
    anchor(alert_card,Control.PRESET_TOP_RIGHT,-283,104,-16,167)
    var alert_row := row(alert_card,8)
    var strip := ColorRect.new()
    strip.color = ALERT
    strip.custom_minimum_size.x = 3
    alert_row.add_child(strip)
    alert_row.add_child(text("!",20,ALERT,true))
    alert_text = text("",13,WHITE,true)
    alert_text.custom_minimum_size.x = 217
    alert_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    alert_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    alert_row.add_child(alert_text)

    controls_panel = card(hud,Color("#292c36a4"),false)
    anchor(controls_panel,Control.PRESET_BOTTOM_LEFT,17,-205,193,-33)
    var keys := col(controls_panel,2)
    for item in [["A / D","Тяга"],["Q / E","Тормоз"],["Z","Реверсор"],["K","Питание"],["F","Двери"],["Space","Экстр. тормоз"],["B","Звонок"],["L / V","Фара / дворник"]]:
        var key_row := row(keys,6)
        var key := text(item[0],12,AMBER,true)
        key.custom_minimum_size.x = 53
        key_row.add_child(key)
        key_row.add_child(text(item[1],12,WHITE,true))

    var subtitle_panel := card(hud,Color("#18242cdd"),false)
    anchor(subtitle_panel,Control.PRESET_CENTER_BOTTOM,-317,-73,317,-22)
    subtitle = text("",15,WHITE,true)
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    subtitle.custom_minimum_size.x = 600
    subtitle_panel.add_child(subtitle)

    crosshair = text("·",24,Color("#fff9e5c6"),true)
    crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hud.add_child(crosshair)
    anchor(crosshair,Control.PRESET_CENTER,-12,-16,12,16)
    interaction = text("",13,WHITE,true)
    interaction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    interaction.add_theme_constant_override("outline_size",6)
    interaction.add_theme_color_override("font_outline_color",Color("#242635"))
    hud.add_child(interaction)
    anchor(interaction,Control.PRESET_CENTER,-210,18,210,48)

    map_panel = card(hud,Color("#202b39ed"))
    anchor(map_panel,Control.PRESET_CENTER_RIGHT,-346,-156,-17,196)
    var route_list := col(map_panel,9)
    route_list.add_child(text("Т01   /   СХЕМА МАРШРУТУ",15,AMBER,true))
    route_list.add_child(text("Погулянка → Залізничний вокзал",13,FAINT))
    route_list.add_child(HSeparator.new())
    for stop in game.Route.NAMES:
        var item := text("○   "+stop,14,WHITE,true)
        route_list.add_child(item)
        route_nodes.append(item)
    map_panel.hide()

    menu = Control.new()
    add_child(menu)
    menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var veil := ColorRect.new()
    veil.color = Color("#121a2780")
    menu.add_child(veil)
    veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var intro := card(menu,Color("#222b3ae9"))
    title_card = intro
    intro.mouse_filter = Control.MOUSE_FILTER_STOP
    intro.add_theme_stylebox_override("panel",style(Color("#222b3ae9"),16,24,18))
    anchor(intro,Control.PRESET_CENTER_LEFT,45,-208,479,208)
    var summary := col(intro,10)
    summary.add_child(text("ЛЬВІВ    ·    МАРШРУТ Т01",14,AMBER,true))
    summary.add_child(text("Ventotto",48,WHITE,true))
    summary.add_child(text("Погулянка  →  Залізничний вокзал\n12,2 км   ·   9 остановок   ·   Вагон 1565",17,FAINT))
    summary.add_child(HSeparator.new())
    summary.add_child(text("ПЕРВЫЙ РЕЙС",12,AMBER,true))
    summary.add_child(text("F — открыть двери и дождаться пассажиров.\nK — питание, Z — реверсор вперёд.\nQ × 4 — отпустить тормоз, D — дать тягу.",15,WHITE))
    summary.add_child(text("Мышь — осмотр кабины и управление приборами.\nR — камера, Tab — маршрут, M — озвучка, Esc — пауза.",13,FAINT))
    action_button = Button.new()
    action_button.text = "Играть   ↵"
    action_button.custom_minimum_size.y = 43
    action_button.add_theme_font_override("font",bold)
    action_button.add_theme_font_size_override("font_size",16)
    action_button.add_theme_color_override("font_color",Color("#273142"))
    action_button.add_theme_color_override("font_hover_color",Color("#273142"))
    action_button.add_theme_stylebox_override("normal",style(AMBER,9,10,6,false))
    action_button.add_theme_stylebox_override("hover",style(Color("#ffd57b"),9,10,6,false))
    action_button.pressed.connect(func():
        if run_started: game.start()
        else: open_modes()
    )
    summary.add_child(action_button)
    modes = card(menu,Color("#222b3af5"))
    anchor(modes,Control.PRESET_CENTER_LEFT,45,-226,545,226)
    modes.mouse_filter = Control.MOUSE_FILTER_STOP
    modes.add_theme_stylebox_override("panel",style(Color("#222b3af5"),16,22,16))
    var options := col(modes,9)
    options.add_child(text("ЛЬВІВ    ·    МАРШРУТ Т01",14,AMBER,true))
    options.add_child(text("Выбери сложность",31,WHITE,true))
    var descriptions := [
        "Сухо, ограниченная тяга, ранние подсказки о поворотах.",
        "Сухо, полная тяга. Следи за скоростью и креном.",
        "Ливень, туман и мокрые рельсы. Тормози заранее."
    ]
    for i in range(3):
        var option := menu_button(game.MODE_NAMES[i])
        options.add_child(option)
        option.pressed.connect(game.begin_run.bind(i))
        if i==1: mode_focus = option
        options.add_child(text(descriptions[i],13,FAINT))
    var back := menu_button("←  Назад")
    options.add_child(back)
    back.pressed.connect(func():
        modes.hide()
        title_card.show()
        action_button.grab_focus()
    )
    modes.hide()

    failure = Control.new()
    add_child(failure)
    failure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var dim := ColorRect.new()
    dim.color = Color("#161923a9")
    failure.add_child(dim)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var result := card(failure,Color("#252d3bf5"))
    anchor(result,Control.PRESET_CENTER,-244,-117,244,117)
    var outcome := col(result,12)
    outcome.add_child(text("РЕЙС ПРЕРВАН",14,ALERT,true))
    outcome.add_child(text("Сход с рельсов",33,WHITE,true))
    outcome.add_child(text("Потерян контакт колёс с рельсами. R — сменить вид.",15,FAINT))
    var restart := menu_button("Начать рейс заново  ·  Enter")
    outcome.add_child(restart)
    restart.pressed.connect(game.restart_run)
    failure.hide()
    show_menu(true)

func menu_button(title: String) -> Button:
    var b := Button.new()
    b.text = title
    b.custom_minimum_size.y = 40
    b.add_theme_font_override("font",bold)
    b.add_theme_font_size_override("font_size",16)
    b.add_theme_color_override("font_color",Color("#273142"))
    b.add_theme_color_override("font_hover_color",Color("#273142"))
    b.add_theme_stylebox_override("normal",style(AMBER,9,10,6,false))
    b.add_theme_stylebox_override("hover",style(Color("#ffd57b"),9,10,6,false))
    return b

func choosing_mode() -> bool:
    return modes.visible

func open_modes() -> void:
    title_card.hide()
    modes.show()
    mode_focus.grab_focus()

func show_failure() -> void:
    menu.hide()
    hud.hide()
    failure.show()

func set_rain(active: bool) -> void:
    rain_overlay.hide() # Rain now lives in the 3D world and on the window meshes.

func show_menu(open: bool) -> void:
    menu.visible = open
    hud.visible = not open
    if not open:
        run_started = true
        modes.hide()
        title_card.show()
        action_button.text = "Продолжить рейс   ↵"

func toggle_route() -> void:
    show_route = not show_route
    hud.modulate.a = 1.0 if show_route else 0.0

func toggle_map() -> void:
    map_panel.visible = not map_panel.visible

func refresh(g: Node) -> void:
    var meters: float = g.distance_to_stop()
    var kmh := roundi(absf(g.velocity)*3.6)
    var cap: int = g.operating_limit()
    var turn: int = g.line.turn_at(g.distance,95.)
    if run_started: mode_info.text = "ДОЖДЬ" if g.difficulty==2 else g.MODE_NAMES[g.difficulty].to_upper()

    var next: String = g.Route.NAMES[g.next_stop] if not g.finished else "Залізничний вокзал"
    speed.text = "%d / %d км/ч" % [kmh,cap]
    speed.modulate = ALERT if kmh>cap else WHITE
    traction.text = "%d / 5" % g.throttle
    brake.text = "%.1f бар" % (g.pressure*6.)
    direction.text = ["Назад","Нейтраль","Вперёд"][g.reverser+1]
    bar.value = g.distance
    if map_panel.visible:
        for i in route_nodes.size():
            var marker := "●" if i<g.next_stop else ("◆" if i==g.next_stop else "○")
            route_nodes[i].text = "%s   %s" % [marker,g.Route.NAMES[i]]
            route_nodes[i].modulate = GREEN if i<g.next_stop else (AMBER if i==g.next_stop else WHITE)
    goal.text = "%s  ·  %d м" % [next,roundi(absf(meters))]
    var power: ProgressBar = instruments.find_child("Power",true,false)
    power.value = g.throttle if g.master else 0
    train_icon.tint = GREEN if g.master else Color("#a6afbf")
    train_icon.queue_redraw()
    train_state.modulate = GREEN if g.master else FAINT
    door_state.text = "●  Двери открыты" if g.doors_open else "●  Двери закрыты"
    if OS.has_feature("web"): door_state.text = door_state.text.replace("●","*")
    door_state.modulate = AMBER if g.doors_open else WHITE
    count.text = "%d в вагоне" % g.onboard.size()
    delivered.text = "Доставлено: %d из %d" % [g.delivered,g.CAST.size()]
    prompt.text = "Рейс завершён · Enter — заново" if g.finished else "Следующая остановка  ·  "+next
    var crossing: int = g.line.junction_near(g.distance+41.,44.)
    var red: bool = crossing>=0 and g.line.crossing_red(crossing,g.clock)
    var msg := ""
    if g.notice_left>0:
        msg = g.route_log
    elif g.doors_open:
        msg = "Идёт посадка и высадка" if g.is_processing_passengers() else "F — закрыть двери"
    elif meters < -2.45:
        msg = "Остановка позади. Остановитесь и включите задний ход."
    elif not g.finished and absf(meters)<=2.45 and kmh==0:
        msg = "F — открыть двери на остановке"
    elif not g.master:
        msg = "K — включить питание"
    elif g.reverser==0:
        msg = "Z — перевести реверсор"
    elif g.brake>0 and kmh==0:
        msg = "Q — отпустить тормоз (%d → 0)" % g.brake
    elif not g.event_hint().is_empty():
        msg = g.event_hint()
    elif g.derailed:
        msg = "Сход · R — камера · Enter — начать заново"
    elif g.dynamics.wheel_unload > 0.7:
        msg = "Опасный крен · снижайте скорость"
    elif g.dynamics.slip > 0.1:
        msg = "Буксование · уменьшите тягу"
    elif red:
        msg = "Красный сигнал · пропустите машины на перекрёстке"
    elif turn>=0 and kmh>=cap-5:
        msg = "Поворот · сбросьте скорость до %d км/ч" % cap if kmh>cap else "Поворот впереди · не выше %d км/ч" % cap
    elif meters<100.0 and kmh>0:
        msg = "Тормозите к отметке F"
    alert_text.text = msg
    alert_card.visible = not msg.is_empty()
    subtitle.text = g.spoken_caption
    subtitle.get_parent().visible = not subtitle.text.is_empty()
    var control: String = g.switch_hint
    interaction.text = ""
    if not control.is_empty():
        var setting := ""
        match control:
            "traction": setting = "  %d / 5" % g.throttle
            "brake": setting = "  %d / 4" % g.brake
            "reverser": setting = "  " + ["Назад","Нейтраль","Вперёд"][g.reverser+1]
        interaction.text = "%s%s   ·   %s" % [CONTROL_NAMES[control],setting,"Колесо мыши" if control in ["traction","brake","reverser"] else "ЛКМ"]






