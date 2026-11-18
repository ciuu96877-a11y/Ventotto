extends Node
## First-shift guide: a checklist of the first departure and a pulsing ring on the control to use.
## It shows until the player has done every step once; «Навчання» in the settings brings it back.

# Each step: the cab control it points at ("" for none) and what to do.
const STEPS := [
    ["doors","F — відчини двері"],
    ["","Дочекайся, поки всі зайдуть"],
    ["doors","F — зачини двері"],
    ["master","K — увімкни живлення"],
    ["reverser","Z — коробка передач: вперед"],
    ["brake","Q — відпусти гальмо до нуля"],
    ["traction","D — дай тягу й рушай"],
    ["brake","E — гальмуй до позначки F на Левицького й відчини двері"],
]
const SHOW_DONE := 4.0 # Seconds the finished checklist stays on screen.

## A pulsing ring on the control, or an arrow at the screen edge pointing where to look.
class Ring extends Control:
    var phase := 0.0
    var pointing := Vector2.ZERO

    func _draw() -> void:
        var middle := size*.5
        var pulse := .5+.5*sin(phase*5.0)
        var ink := Color(1.0,.76,.31,.95)
        var shade := Color(.08,.1,.16,.75)
        if pointing==Vector2.ZERO:
            var radius := 17.0+pulse*8.0
            draw_arc(middle,radius,0.0,TAU,48,shade,7.0,true)
            draw_arc(middle,radius,0.0,TAU,48,Color(ink,1.0-pulse*.45),4.0,true)
            draw_circle(middle,5.0,shade)
            draw_circle(middle,3.5,ink)
            return
        var ahead := pointing.normalized()
        var side := Vector2(-ahead.y,ahead.x)
        var tip := middle+ahead*(14.0+pulse*5.0)
        draw_colored_polygon(PackedVector2Array([tip+ahead*3.0,tip-ahead*20.0+side*15.0,tip-ahead*20.0-side*15.0]),shade)
        draw_colored_polygon(PackedVector2Array([tip,tip-ahead*16.0+side*11.0,tip-ahead*16.0-side*11.0]),ink)
        draw_arc(middle,8.0,0.0,TAU,24,Color(ink,.6+pulse*.35),2.5,true)

var game: Node3D
var card: PanelContainer
var heading: Label
var lines: Array[Label] = []
var done: Array[bool] = []
var ring: Ring
var active := false
var over := false # Done or cut short in this shift: it does not come back until the next one.
var complete_for := -1.0

func setup(owner_game: Node3D) -> void:
    game = owner_game
    var ui: CanvasLayer = game.ui
    card = ui.card(ui.hud,Color("#222b3ae6"))
    ui.anchor(card,Control.PRESET_BOTTOM_LEFT,17,-300,317,-33)
    var list: VBoxContainer = ui.col(card,6)
    heading = ui.text("ПЕРШИЙ РЕЙС · ЩО РОБИТИ",13,ui.AMBER,true)
    list.add_child(heading)
    for step in STEPS:
        var line: Label = ui.text("",13,ui.WHITE,true)
        line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        line.custom_minimum_size.x = 272
        list.add_child(line)
        lines.append(line)
        done.append(false)
    card.hide()
    ring = Ring.new()
    ring.size = Vector2(72,72)
    ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.hud.add_child(ring)
    ring.hide()

## True once the step's goal has been reached at least once in this shift.
func reached(index: int) -> bool:
    match index:
        0: return game.doors_open or game.next_stop>0
        1: return (game.doors_open and not game.is_processing_passengers()) or game.next_stop>0
        2: return game.next_stop>0
        3: return game.master
        4: return game.reverser==1
        5: return game.brake==0 and not game.emergency
        6: return absf(game.velocity)>1.0
        7: return game.next_stop>=2 or (game.next_stop==1 and game.doors_open)
    return false

func current() -> int:
    for i in done.size():
        if not done[i]: return i
    return -1

func mark(content: String) -> String:
    if OS.has_feature("web"): return content.replace("●","*").replace("◆",">").replace("○","o")
    return content

func tick(dt: float) -> void:
    if not active:
        # The guide covers the first leg of the shift; switching it on later waits for the next shift.
        if game.driving and game.preferences.tutorial and game.next_stop<=1 and not game.finished and not game.derailed and not over:
            active = true
        else:
            return
    if game.derailed or game.finished:
        stop()
        return
    for i in done.size():
        if not done[i] and reached(i): done[i] = true
    var now := current()
    if now<0 and complete_for<0.0:
        complete_for = SHOW_DONE
        heading.text = "ГОТОВО! ДАЛІ — САМ"
        game.preferences.tutorial = false
        game.preferences.save()
    if complete_for>=0.0:
        complete_for -= dt
        if complete_for<=0.0:
            stop()
            return
    for i in lines.size():
        var line := lines[i]
        line.text = mark(("●  " if done[i] else ("◆  " if i==now else "○  "))+STEPS[i][1])
        line.modulate = game.ui.GREEN if done[i] else (game.ui.AMBER if i==now else game.ui.FAINT)
    card.show()
    game.ui.controls_panel.hide()
    place_ring(now,dt)

func place_ring(step: int,dt: float) -> void:
    ring.hide()
    if step<0 or game.third_person or game.encounters.interacting: return
    var control: String = STEPS[step][0]
    if control=="" or not game.cab.controls.has(control): return
    var view: Camera3D = game.view
    var spot: Vector3 = game.cab.to_global(game.cab.controls[control])
    var area := view.get_viewport().get_visible_rect()
    var screen := view.unproject_position(spot)
    var behind := view.is_position_behind(spot)
    ring.pointing = Vector2.ZERO
    if behind or not area.grow(-30.0).has_point(screen):
        # Off screen: an arrow near the edge shows which way to look.
        var middle := area.get_center()
        var away := (middle-screen if behind else screen-middle)
        if away.length()<1.0: away = Vector2.DOWN
        var reach := minf((area.size.x*.5-60.0)/maxf(absf(away.x),.001),(area.size.y*.5-60.0)/maxf(absf(away.y),.001))
        screen = middle+away*minf(reach,1.0e6)
        ring.pointing = away
    ring.position = screen-ring.size*.5
    ring.phase += dt
    ring.queue_redraw()
    ring.show()

func stop() -> void:
    active = false
    over = true
    card.hide()
    ring.hide()
    game.ui.controls_panel.show()
