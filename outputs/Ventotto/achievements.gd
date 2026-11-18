extends Node
## Achievements: each is earned once, kept in career.cfg, announced with a banner,
## listed in the menu window «Досягнення» and summed up at the end of a shift.

const Events = preload("res://passenger_events.gd")
# id, name, how to earn it.
const LIST := [
    ["finish","До вокзалу","Доїхати до Залізничного вокзалу."],
    ["no_emergency","Без паніки","Завершити рейс без екстреного гальмування."],
    ["precise","Точно в ціль","Зупинитися біля позначки F точніше ніж за 30 см."],
    ["rain","Під дощем","Завершити рейс, коли під час нього йшов дощ."],
    ["derail","Ой...","Уперше зійти з рейок."],
    ["everyone","Усі доїхали","Завершити рейс, коли всі пасажири вийшли на своїх зупинках."],
    ["grandma","Зачекайте!","Дочекатися бабусю на площі Митна."],
    ["grandpa","Дідусь устиг","Випустити дідуся на Дорошенка."],
    ["calm","Миротворець","Заспокоїти пасажира напідпитку розмовою."],
    ["promise","Слово водія","Виконати обіцянку бабусі: 20 секунд плавної їзди."],
    ["ticket","Квиток, будь ласка","Пасажирка оплатила проїзд."],
    ["fight","Відбився","Вистояти в бійці, поки пасажир не здасться."],
    ["favourite","Улюбленець пасажирів","Завершити рейс з репутацією 90 або більше."],
    ["clean_hands","Чисті руки","Завершити рейс, жодного разу не вдаривши пасажира."],
    ["earner","Гарна зміна","Заробити 300 грн за одну зміну."],
    ["tour","Екскурсія салоном","Дійти до задніх дверей."],
    ["bell","Дзень-дзелень","Подзвонити 10 разів за один рейс."],
    ["outside","Погляд збоку","Подивитися на трамвай ззовні."],
    ["punch","Так не можна","Вдарити пасажира."],
]
const BANNER_TIME := 3.4

var game: Node3D
var earned := {}
var run_new: Array[String] = []
var used_emergency := false
var saw_rain := false
var bells := 0
var hits := 0
var doors_were_open := false
var finish_checked := false
var opened := false
var queue: Array[String] = []
var banner_left := 0.0
var banner: PanelContainer
var banner_name: Label
var window: PanelContainer
var window_title: Label
var rows := {}
var summary: PanelContainer
var summary_list: Label

func setup(owner_game: Node3D) -> void:
    game = owner_game
    var career := ConfigFile.new()
    career.load(Events.career_file)
    for item in LIST:
        if bool(career.get_value("achievements",item[0],false)): earned[item[0]] = true
    var ui: CanvasLayer = game.ui
    # The menu card grows by one button, «Досягнення», under «Налаштування».
    ui.anchor(ui.title_card,Control.PRESET_CENTER_LEFT,45,-262,479,262)
    var open_button: Button = ui.menu_button("Досягнення")
    ui.action_button.get_parent().add_child(open_button)
    open_button.pressed.connect(open_window)

    window = ui.card(ui.menu,Color("#222b3af5"))
    ui.anchor(window,Control.PRESET_CENTER,-330,-300,330,300)
    window.mouse_filter = Control.MOUSE_FILTER_STOP
    var content: VBoxContainer = ui.col(window,12)
    window_title = ui.text("",27,ui.WHITE,true)
    content.add_child(window_title)
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(620,440)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    content.add_child(scroll)
    var list: VBoxContainer = ui.col(scroll,9)
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for item in LIST:
        var entry: VBoxContainer = ui.col(list,1)
        var title: Label = ui.text(item[1],16,ui.WHITE,true)
        entry.add_child(title)
        var how: Label = ui.text(item[2],13,ui.FAINT)
        how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        how.custom_minimum_size.x = 590
        entry.add_child(how)
        rows[item[0]] = title
    var back: Button = ui.menu_button("Повернутися · Esc")
    content.add_child(back)
    back.pressed.connect(close_window)
    window.hide()

    # Banner and summary sit above the HUD, the menu and the failure screen alike.
    var overlay := Control.new()
    ui.add_child(overlay)
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    banner = ui.card(overlay,Color("#2a3346f0"))
    ui.anchor(banner,Control.PRESET_CENTER_TOP,-220,150,220,212)
    var banner_text: VBoxContainer = ui.col(banner,1)
    var label: Label = ui.text("ДОСЯГНЕННЯ",12,ui.AMBER,true)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner_text.add_child(label)
    banner_name = ui.text("",19,ui.WHITE,true)
    banner_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner_text.add_child(banner_name)
    banner.hide()

    summary = ui.card(overlay,Color("#252d3bf2"))
    ui.anchor(summary,Control.PRESET_CENTER,-244,132,244,250)
    var summary_text: VBoxContainer = ui.col(summary,6)
    summary_text.add_child(ui.text("ЗА РЕЙС",13,ui.AMBER,true))
    summary_list = ui.text("",15,ui.WHITE,true)
    summary_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    summary_list.custom_minimum_size.x = 460
    summary_text.add_child(summary_list)
    summary.hide()
    refresh_window()

func name_of(id: String) -> String:
    for item in LIST:
        if item[0]==id: return item[1]
    return id

func unlock(id: String) -> void:
    if earned.has(id): return
    earned[id] = true
    run_new.append(name_of(id))
    queue.append(name_of(id))
    var career := ConfigFile.new()
    career.load(Events.career_file)
    career.set_value("achievements",id,true)
    career.save(Events.career_file)
    refresh_window()

## Things that happen in a moment rather than as a lasting state.
func note(what: String) -> void:
    match what:
        "bell":
            bells += 1
            if bells>=10: unlock("bell")
        "hit":
            hits += 1
            unlock("punch")

func tick(dt: float) -> void:
    if game.driving and not game.paused:
        watch()
    show_banner(dt)
    summary.visible = (game.finished and not game.ui.menu.visible) or game.ui.failure.visible
    if summary.visible:
        var found := "Нові досягнення: "+", ".join(PackedStringArray(run_new)) if not run_new.is_empty() else "Нових досягнень немає"
        summary_list.text = found+"\nУсього: %d / %d" % [earned.size(),LIST.size()]

func watch() -> void:
    if game.emergency: used_emergency = true
    if game.rain>.45: saw_rain = true
    if game.third_person: unlock("outside")
    if game.upright and game.foot.y<-5.3: unlock("tour")
    if game.derailed: unlock("derail")
    if game.encounters.cash>=300: unlock("earner")
    # The shift starts lined up with F at Погулянка, so only later stops count.
    if game.doors_open and not doors_were_open and game.next_stop>0 and absf(game.distance_to_stop())<.3: unlock("precise")
    doors_were_open = game.doors_open
    if game.finished and not finish_checked:
        finish_checked = true
        unlock("finish")
        if not used_emergency: unlock("no_emergency")
        if saw_rain: unlock("rain")
        if game.delivered>=game.boarded: unlock("everyone")
        if game.encounters.reputation>=90: unlock("favourite")
        if hits==0: unlock("clean_hands")

func show_banner(dt: float) -> void:
    if banner_left>0.0:
        banner_left -= dt
        if banner_left<=0.0: banner.hide()
        return
    if queue.is_empty(): return
    banner_name.text = queue.pop_front()
    banner_left = BANNER_TIME
    banner.show()

func refresh_window() -> void:
    if window_title==null: return
    window_title.text = "ДОСЯГНЕННЯ   %d / %d" % [earned.size(),LIST.size()]
    for id in rows:
        var title: Label = rows[id]
        title.modulate = game.ui.AMBER if earned.has(id) else Color("#8f97a6")

func open_window() -> void:
    opened = true
    game.ui.title_card.hide()
    refresh_window()
    window.show()

func close_window() -> void:
    opened = false
    window.hide()
    game.ui.title_card.show()
