extends Node
## Background life for passengers and pedestrians: gesture clips baked onto each rig
## at spawn, random idles, and short Ukrainian small talk between neighbours.
## It only plays animations, text and sound; it never changes gameplay state.

const Hands = preload("res://hands.gd")
const LIB := "life"
const REF_SHOULDER := 1.388 # Hand offsets below are authored for this shoulder height.
const FINGERS := ["index","middle","ring","pinky","thumb"]
const PARTS := ["01","02","03"]
# Imported clips hold the arms out from the body. Each key keeps this share of its
# sideways spread and elbow bend, plus a small resting angle, so arms hang naturally.
const ARM_KEEP := .2
const ARM_HANG := .08
const ELBOW_KEEP := .35
const ELBOW_REST := .10
const FINGER_REST := .3
# Saloon geometry in tram space: floor, bench seat top, backrest face, and [side, from, to] of each bench.
const FLOOR := 1.082
const SEAT_TOP := 1.565
const PELVIS_LIFT := .095
const BACKREST := 1.005
const TONES := [Color.WHITE,Color(.70,.78,.98),Color(.98,.76,.70),Color(.74,.92,.78),Color(.60,.60,.66),Color(1.0,.93,.72),Color(.86,.72,.95),Color(.55,.68,.60)]
const BENCHES := [[-1.0,.88,4.99],[-1.0,-2.62,.66],[-1.0,-5.66,-2.83],[1.0,.09,4.87],[1.0,-5.17,-1.52]]
# First entry is where the talk fits: * anywhere, t tram or stop, i inside, p stop, r rain, d dry.
# Lines alternate between the two speakers and avoid gendered forms, so anyone can say them.
# Each line is recorded twice in assets/voice/chatter as t<talk>_<line>_<m|f>.mp3; re-record after editing.
const TALKS := [
    ["t","Перепрошую, цей трамвай їде до вокзалу?","Так, до самого вокзалу. Ще кілька зупинок.","Дякую! Бо потяг чекати не буде."],
    ["r","Ну й погода сьогодні, правда?","І не кажіть. У Львові без парасолі ніяк.","Зате після дощу місто таке гарне.","Це точно. Бруківка аж блищить."],
    ["d","Яка сьогодні гарна погода!","Нарешті сонце. Саме час прогулятися містом.","Після роботи піду до Стрийського парку.","Гарна думка. Там зараз дуже красиво."],
    ["*","Де тут у центрі найкраща кава?","Біля Ринку. Там кав’ярня на кожному кроці.","А до кави щось смачне знайдеться?","Беріть сирник, не пошкодуєте."],
    ["*","Бачили, які ціни на базарі?","Ой, краще не згадуйте. Помідори як золоті.","А картопля ще дорожча, ніж торік.","Нічого, якось дамо собі раду."],
    ["t","Не підкажете, котра година?","За десять дев’ята.","Ой, я запізнююся на роботу!","Не хвилюйтеся, трамвай їде швидко."],
    ["*","Дивилися вчора футбол?","Аякже! «Карпати» знову тримали в напрузі.","Головне, що не програли.","Ще трохи, і будемо в лізі чемпіонів!"],
    ["i","Гарно водій їде, плавно.","Так, не те що вчора. Мене аж хитало.","Старий вагон, а яка краса всередині.","Дерево, шкіра… Тепер таких не роблять."],
    ["i","Перепрошую, ви виходите на наступній?","Ні, мені ще їхати. Проходьте, будь ласка.","Дякую, ви дуже люб’язні."],
    ["*","Як там ваші діти, вчаться?","Вчаться. Старша вже у Політехніці.","Ого, як час летить!","І не кажіть, наче вчора до школи вели."],
    ["*","Які плани на вихідні?","Хочу піднятися на Високий Замок.","Гарна ідея. Звідти видно все місто.","Ходімо разом, удвох веселіше."],
    ["*","Стільки туристів цього року!","Бо Львів гарний, от і їдуть.","Аби тільки в трамваї місця вистачало."],
    ["*","Ви не знаєте, пекарня на розі ще працює?","Працює. Хліб там свіжий щоранку.","О, тоді зайду дорогою додому."],
    ["*","Маю квитки до опери на суботу.","Справді? А що дають?","«Запорожця за Дунаєм». Кажуть, чудова постановка.","Потім розкажете, чи сподобалося."],
    ["i","Може, вам притримати сумку?","Дякую, вона не важка.","Тоді тримайтеся міцніше, зараз поворот."],
    ["p","Давно чекаєте на трамвай?","Хвилин п’ять. Має ось-ось під’їхати.","Добре, бо я вже починаю мерзнути."],
    ["*","Чули, на проспекті знову ремонт колії?","Так, кажуть, до осені не закінчать.","То доведеться їздити в об’їзд.","Нічого, зате потім буде тихо й рівно."],
    ["*","Кави б зараз, горнятко гарячої.","О, я теж про це думаю.","То ходімо після роботи на каву?","Із задоволенням. Домовилися!"],
]

var game: Node3D
var clock := 0.0
var scan := 0.0
var libraries := {}
var blob: PlaneMesh
var outfits := {}
var seats: Array[Vector2] = []
# These lists can outlive the people in them (a pedestrian leaves the street mid-gesture),
# so they are untyped and cleaned by index: erasing a freed object from a typed array is unsafe.
var movers := []
var homing := []
var sway := Vector2.ZERO
var sway_speed := Vector2.ZERO
var clips := {}
var women := {}
var pose_bones: Array[String] = []
var idle_pool: Array[String] = ["LookAround","CheckWatch","Phone","ScratchHead","Yawn","ArmsCrossed","HandsOnHips","Think","RubNeck","Collar","RubHands","Cough","Shift"]
var ride_pool: Array[String] = []
var stop_pool: Array[String] = []
var street_pool: Array[String] = ["Phone","LookAround","CheckWatch","Stretch","Yawn","ScratchHead","Think","Wave","HandsOnHips"]
var talk_pool: Array[String] = ["TalkOne","TalkBoth","Shrug","TalkOpen","Point"]
var close_talk_pool: Array[String] = ["TalkOne","TalkBoth","Shrug","TalkOpen"]
var listen_pool: Array[String] = ["Nod","Nod","Listen","Laugh","HeadShake"]
var talks: Array[Dictionary] = []
var shouts: Array[Dictionary] = []
var fidgets := []
var recent: Array[int] = []
var near_next := 5.0
var street_next := 2.0
var waved_stop := -1
var voice_db := -6.0
var hushed := false

func _init() -> void:
    clips = specs()
    for bench: Array in BENCHES:
        var count := floori((bench[2]-bench[1]-.66)/.6)+1
        var first: float = (bench[1]+bench[2])*.5-(count-1)*.3
        for i in count: seats.append(Vector2(bench[0],first+i*.6))
    ride_pool = idle_pool + (["LookBack"] as Array[String])
    stop_pool = idle_pool + (["Stretch"] as Array[String])
    pose_bones = ["spine_02","spine_03","neck_01","head"]
    for side in ["l","r"]:
        for bone in ["upperarm_","lowerarm_","hand_"]: pose_bones.append(bone+side)
        for finger in FINGERS:
            for part in PARTS: pose_bones.append("%s_%s_%s" % [finger,part,side])

func setup(owner_game: Node3D) -> void:
    game = owner_game

# ---------------------------------------------------------------- gesture clips

## Every clip is [length, [[time, pose], ...]]; the rig rests in its Idle pose at both ends.
## Pose fields: head / spine = (yaw, pitch, roll); l / r = [anchor, wrist offset];
## lp / rp = elbow direction; lh / rh = [finger direction, palm direction]; lf / rf = finger curl;
## ll / rl = [anchor, ankle offset] for a leg, llp / rlp = knee direction.
## Directions are in body space: +X left, +Y up, +Z forward.
func specs() -> Dictionary:
    var out := {}
    var look_l := {"head":Vector3(.62,.03,0),"spine":Vector3(.10,0,0)}
    var look_r := {"head":Vector3(-.58,.06,0),"spine":Vector3(-.09,0,0)}
    out["LookAround"] = [4.8,[[.8,look_l],[1.8,look_l],[2.9,look_r],[3.9,look_r]]]
    var back := {"head":Vector3(.95,.04,0),"spine":Vector3(.34,0,0)}
    out["LookBack"] = [4.4,[[1.0,back],[3.2,back]]]
    var shift_l := {"spine":Vector3(0,0,.05),"head":Vector3(.08,0,-.04)}
    var shift_r := {"spine":Vector3(0,0,-.05),"head":Vector3(-.10,0,.04)}
    out["Shift"] = [5.0,[[1.0,shift_l],[2.2,shift_l],[3.3,shift_r],[4.2,shift_r]]]

    var watch := {"head":Vector3(.10,.38,0),"l":["chest",Vector3(.02,.15,.30)],"lp":Vector3(.6,-1,-.2),"lh":[Vector3(-1,.05,.2),Vector3(0,-1,.1)],"lf":.35}
    out["CheckWatch"] = [3.6,[[.8,watch],[2.6,watch]]]
    var phone := {"head":Vector3(0,.42,0),"r":["chest",Vector3(-.08,.07,.30)],"rp":Vector3(-.5,-1,-.1),"rh":[Vector3(.3,.45,.8),Vector3(0,.85,-.5)],"rf":.45}
    var phone_near := {"head":Vector3(.04,.47,0),"r":["chest",Vector3(-.07,.10,.29)],"rp":Vector3(-.5,-1,-.1),"rh":[Vector3(.3,.45,.8),Vector3(0,.85,-.5)],"rf":.45}
    out["Phone"] = [7.2,[[.9,phone],[3.4,phone_near],[6.0,phone]]]
    var scratch := {"head":Vector3(0,.10,.08),"r":["head",Vector3(-.13,.08,-.02)],"rp":Vector3(-1,.1,.1),"rh":[Vector3(.55,.75,-.2),Vector3(.7,-.55,.1)],"rf":.45}
    var scratch_up := {"head":Vector3(0,.10,.08),"r":["head",Vector3(-.13,.11,.0)],"rp":Vector3(-1,.1,.1),"rh":[Vector3(.55,.75,-.2),Vector3(.7,-.55,.1)],"rf":.45}
    out["ScratchHead"] = [3.8,[[.9,scratch],[1.2,scratch_up],[1.5,scratch],[1.8,scratch_up],[2.1,scratch],[2.5,scratch]]]
    var yawn := {"head":Vector3(0,-.22,0),"spine":Vector3(0,-.07,0),"r":["head",Vector3(-.09,-.07,.15)],"rp":Vector3(-.8,-1,0),"rh":[Vector3(.95,.3,-.05),Vector3(0,0,-1)],"rf":.15}
    out["Yawn"] = [4.0,[[1.0,yawn],[2.5,yawn]]]
    var crossed := {
        "l":["chest",Vector3(-.04,.10,.20)],"lp":Vector3(.5,-1,.2),"lh":[Vector3(-1,.1,-.15),Vector3(0,0,-1)],"lf":.3,
        "r":["chest",Vector3(.02,.06,.22)],"rp":Vector3(-.5,-1,.2),"rh":[Vector3(1,.1,-.2),Vector3(0,0,-1)],"rf":.3}
    out["ArmsCrossed"] = [7.6,[[1.1,crossed],[6.3,crossed]]]
    var hips := {"spine":Vector3(0,-.03,0),
        "l":["hip",Vector3(.19,.06,.03)],"lp":Vector3(1,0,-.5),"lh":[Vector3(0,-.5,.85),Vector3(-1,0,0)],"lf":.25,
        "r":["hip",Vector3(-.19,.06,.03)],"rp":Vector3(-1,0,-.5),"rh":[Vector3(0,-.5,.85),Vector3(1,0,0)],"rf":.25}
    out["HandsOnHips"] = [6.4,[[1.0,hips],[5.2,hips]]]
    var think := {"head":Vector3(0,.08,.10),
        "r":["head",Vector3(-.05,-.19,.12)],"rp":Vector3(-.3,-1,.3),"rh":[Vector3(.15,.9,.2),Vector3(.2,0,-1)],"rf":.6,
        "l":["chest",Vector3(-.13,.02,.19)],"lp":Vector3(.5,-1,.2),"lh":[Vector3(-1,0,0),Vector3(0,.3,-1)],"lf":.3}
    out["Think"] = [6.0,[[1.2,think],[4.8,think]]]
    var neck := {"head":Vector3(0,.18,-.10),"l":["head",Vector3(.09,-.02,-.12)],"lp":Vector3(1,.6,.5),"lh":[Vector3(-.9,.1,-.3),Vector3(-.2,-.2,1)],"lf":.35}
    var neck_in := {"head":Vector3(0,.18,-.10),"l":["head",Vector3(.07,.01,-.12)],"lp":Vector3(1,.6,.5),"lh":[Vector3(-.9,.1,-.3),Vector3(-.2,-.2,1)],"lf":.35}
    out["RubNeck"] = [4.2,[[1.0,neck],[1.5,neck_in],[2.0,neck],[2.5,neck_in],[3.0,neck]]]
    var collar := {"head":Vector3(0,.25,0),"r":["chest",Vector3(-.05,.22,.16)],"rp":Vector3(-1,-.6,.2),"rh":[Vector3(.6,.7,-.2),Vector3(.3,0,-1)],"rf":.5}
    var collar_up := {"head":Vector3(0,.25,0),"r":["chest",Vector3(-.03,.25,.16)],"rp":Vector3(-1,-.6,.2),"rh":[Vector3(.6,.7,-.2),Vector3(.3,0,-1)],"rf":.5}
    out["Collar"] = [3.4,[[.8,collar],[1.2,collar_up],[1.6,collar],[2.0,collar_up],[2.4,collar]]]
    var rub := {"head":Vector3(0,.12,0),
        "l":["chest",Vector3(.05,.03,.30)],"lp":Vector3(.6,-1,0),"lh":[Vector3(-.2,.4,.9),Vector3(-1,0,0)],"lf":.1,
        "r":["chest",Vector3(-.05,.03,.24)],"rp":Vector3(-.6,-1,0),"rh":[Vector3(.2,.4,.9),Vector3(1,0,0)],"rf":.1}
    var rub_back := {"head":Vector3(0,.12,0),
        "l":["chest",Vector3(.05,.03,.24)],"lp":Vector3(.6,-1,0),"lh":[Vector3(-.2,.4,.9),Vector3(-1,0,0)],"lf":.1,
        "r":["chest",Vector3(-.05,.03,.30)],"rp":Vector3(-.6,-1,0),"rh":[Vector3(.2,.4,.9),Vector3(1,0,0)],"rf":.1}
    out["RubHands"] = [4.4,[[.8,rub],[1.2,rub_back],[1.6,rub],[2.0,rub_back],[2.4,rub],[2.8,rub_back],[3.2,rub]]]
    var cough := {"head":Vector3(0,.15,0),"spine":Vector3(0,.03,0),"r":["head",Vector3(-.06,-.07,.15)],"rp":Vector3(-.8,-1,0),"rh":[Vector3(.95,.3,-.05),Vector3(0,0,-1)],"rf":.7}
    var cough_down := {"head":Vector3(0,.22,0),"spine":Vector3(0,.13,0),"r":["head",Vector3(-.06,-.07,.15)],"rp":Vector3(-.8,-1,0),"rh":[Vector3(.95,.3,-.05),Vector3(0,0,-1)],"rf":.7}
    out["Cough"] = [3.0,[[.7,cough],[.95,cough_down],[1.2,cough],[1.45,cough_down],[1.75,cough],[2.1,cough]]]
    var stretch := {"head":Vector3(0,-.16,0),"spine":Vector3(0,-.10,0),
        "l":["sh",Vector3(.04,.44,-.02)],"lp":Vector3(1,0,-.3),"lh":[Vector3(0,1,0),Vector3(-1,0,0)],
        "r":["sh",Vector3(-.04,.44,-.02)],"rp":Vector3(-1,0,-.3),"rh":[Vector3(0,1,0),Vector3(1,0,0)]}
    var stretch_wide := {"head":Vector3(0,-.20,0),"spine":Vector3(0,-.12,0),
        "l":["sh",Vector3(.12,.42,-.05)],"lp":Vector3(1,0,-.3),"lh":[Vector3(.2,1,0),Vector3(-1,0,0)],
        "r":["sh",Vector3(-.12,.42,-.05)],"rp":Vector3(-1,0,-.3),"rh":[Vector3(-.2,1,0),Vector3(1,0,0)]}
    out["Stretch"] = [5.2,[[1.3,stretch],[2.4,stretch_wide],[3.4,stretch]]]
    var wave := {"r":["sh",Vector3(-.20,.30,.14)],"rp":Vector3(-1,-.6,0),"rh":[Vector3(-.3,1,0),Vector3(0,0,1)]}
    var wave_in := {"r":["sh",Vector3(-.06,.32,.14)],"rp":Vector3(-1,-.6,0),"rh":[Vector3(.3,1,0),Vector3(0,0,1)]}
    out["Wave"] = [3.6,[[.7,wave],[1.0,wave_in],[1.3,wave],[1.6,wave_in],[1.9,wave],[2.2,wave_in],[2.5,wave]]]

    var one := {"head":Vector3(0,.04,0),"r":["chest",Vector3(-.25,.06,.30)],"rp":Vector3(-.7,-1,-.1),"rh":[Vector3(.25,.2,.95),Vector3(.3,.9,-.2)],"rf":.12}
    var one_up := {"head":Vector3(.04,-.03,0),"r":["chest",Vector3(-.29,.12,.33)],"rp":Vector3(-.7,-1,-.1),"rh":[Vector3(.25,.2,.95),Vector3(.3,.9,-.2)],"rf":.12}
    out["TalkOne"] = [3.2,[[.5,one],[.9,one_up],[1.3,one],[1.8,one_up],[2.3,one]]]
    var both := {
        "l":["chest",Vector3(.17,.05,.30)],"lp":Vector3(.7,-1,-.1),"lh":[Vector3(-.15,.25,.95),Vector3(-.7,.6,-.1)],"lf":.1,
        "r":["chest",Vector3(-.17,.05,.30)],"rp":Vector3(-.7,-1,-.1),"rh":[Vector3(.15,.25,.95),Vector3(.7,.6,-.1)],"rf":.1}
    var both_wide := {"head":Vector3(0,-.03,0),
        "l":["chest",Vector3(.24,.10,.31)],"lp":Vector3(.7,-1,-.1),"lh":[Vector3(-.15,.25,.95),Vector3(-.7,.6,-.1)],"lf":.1,
        "r":["chest",Vector3(-.24,.10,.31)],"rp":Vector3(-.7,-1,-.1),"rh":[Vector3(.15,.25,.95),Vector3(.7,.6,-.1)],"rf":.1}
    out["TalkBoth"] = [3.4,[[.5,both],[1.0,both_wide],[1.5,both],[2.0,both_wide],[2.5,both]]]
    var shrug := {"head":Vector3(0,-.05,.12),"spine":Vector3(0,-.03,0),
        "l":["chest",Vector3(.27,.02,.24)],"lp":Vector3(.5,-1,-.3),"lh":[Vector3(.4,.05,.9),Vector3(0,1,0)],
        "r":["chest",Vector3(-.27,.02,.24)],"rp":Vector3(-.5,-1,-.3),"rh":[Vector3(-.4,.05,.9),Vector3(0,1,0)]}
    out["Shrug"] = [2.6,[[.6,shrug],[1.5,shrug]]]
    var open := {"head":Vector3(0,0,-.08),"l":["chest",Vector3(.20,.04,.31)],"lp":Vector3(.7,-1,-.1),"lh":[Vector3(.25,.1,.95),Vector3(-.3,.9,-.1)],"lf":.08}
    var open_up := {"head":Vector3(.05,.03,-.08),"l":["chest",Vector3(.24,.09,.33)],"lp":Vector3(.7,-1,-.1),"lh":[Vector3(.25,.1,.95),Vector3(-.3,.9,-.1)],"lf":.08}
    out["TalkOpen"] = [3.0,[[.5,open],[1.0,open_up],[1.5,open],[2.1,open]]]
    var point := {"head":Vector3(-.2,0,0),"r":["sh",Vector3(-.10,-.06,.44)],"rp":Vector3(-.5,-1,0),"rh":[Vector3(-.15,0,1),Vector3(.3,-1,0)],"rf":.9,"rpoint":true}
    var point_out := {"head":Vector3(-.2,0,0),"r":["sh",Vector3(-.10,-.02,.46)],"rp":Vector3(-.5,-1,0),"rh":[Vector3(-.15,0,1),Vector3(.3,-1,0)],"rf":.9,"rpoint":true}
    out["Point"] = [3.0,[[.6,point],[1.0,point_out],[1.4,point],[1.9,point]]]

    # Recoiling from a blow, hands up in front of the face. Not part of any random pool.
    var flinch := {"head":Vector3(.30,-.10,.10),"spine":Vector3(.12,-.20,.04),
        "l":["head",Vector3(.13,-.10,.20)],"lp":Vector3(.8,-1,-.1),"lh":[Vector3(-.2,1,.1),Vector3(0,0,1)],"lf":.25,
        "r":["head",Vector3(-.11,-.07,.23)],"rp":Vector3(-.8,-1,-.1),"rh":[Vector3(.2,1,.1),Vector3(0,0,1)],"rf":.25}
    var flinch_hold := {"head":Vector3(.24,-.06,.08),"spine":Vector3(.08,-.14,.03),
        "l":["head",Vector3(.13,-.12,.19)],"lp":Vector3(.8,-1,-.1),"lh":[Vector3(-.2,1,.1),Vector3(0,0,1)],"lf":.25,
        "r":["head",Vector3(-.11,-.09,.22)],"rp":Vector3(-.8,-1,-.1),"rh":[Vector3(.2,1,.1),Vector3(0,0,1)],"rf":.25}
    out["Flinch"] = [2.2,[[.14,flinch],[.75,flinch_hold],[1.3,flinch_hold]]]

    out["Nod"] = [2.2,[[.4,{"head":Vector3(0,.16,0)}],[.75,{"head":Vector3(0,-.02,0)}],[1.1,{"head":Vector3(0,.14,0)}],[1.5,{"head":Vector3.ZERO}]]]
    out["HeadShake"] = [2.4,[[.4,{"head":Vector3(.22,0,0)}],[.8,{"head":Vector3(-.22,0,0)}],[1.2,{"head":Vector3(.18,0,0)}],[1.6,{"head":Vector3(-.12,0,0)}]]]
    var laugh := {"head":Vector3(0,-.20,0),"spine":Vector3(0,-.08,0)}
    var laugh_low := {"head":Vector3(0,-.14,0),"spine":Vector3(0,-.03,0)}
    out["Laugh"] = [2.8,[[.5,laugh],[.75,laugh_low],[1.0,laugh],[1.25,laugh_low],[1.5,laugh],[1.9,laugh_low]]]
    var listen := {"head":Vector3(.06,.03,.12)}
    out["Listen"] = [3.6,[[.8,listen],[2.6,listen]]]
    return out

func mirrored(pose: Dictionary) -> Dictionary:
    var out := {}
    for key: String in pose:
        var value = pose[key]
        var name := key
        if key.begins_with("l"): name = "r"+key.substr(1)
        elif key.begins_with("r"): name = "l"+key.substr(1)
        if value is Vector3:
            value = Vector3(-value.x,value.y,-value.z) if key in ["head","spine"] else Vector3(-value.x,value.y,value.z)
        elif value is Array:
            var copy := []
            for item in value: copy.append(Vector3(-item.x,item.y,item.z) if item is Vector3 else item)
            value = copy
        out[name] = value
    return out

func bones_used(poses: Array) -> Array[String]:
    var fields := {}
    for entry: Array in poses:
        for field in entry[1]: fields[field] = true
    var used: Array[String] = []
    if fields.has("spine"): used.append_array(["spine_02","spine_03"])
    if fields.has("head"): used.append_array(["neck_01","head"])
    for side in ["l","r"]:
        if fields.has(side+"l"): used.append_array(["thigh_"+side,"calf_"+side,"foot_"+side])
        if not fields.has(side): continue
        used.append_array(["upperarm_"+side,"lowerarm_"+side,"hand_"+side])
        if fields.has(side+"f"):
            for finger in FINGERS:
                for part in PARTS: used.append("%s_%s_%s" % [finger,part,side])
    return used

## Seated on a bench: feet on the floor, hands on the thighs or folded in the lap.
func sit_pose(female: bool,folded: bool) -> Dictionary:
    var spread := .095 if female else .17
    var knee := 0.0 if female else .2
    var pose := {
        "ll":["bench",Vector3(spread,0,.405)],"llp":Vector3(knee,.6,.8),
        "rl":["bench",Vector3(-spread,0,.405)],"rlp":Vector3(-knee,.6,.8)}
    if folded:
        pose.merge({
            "l":["hip",Vector3(.05,.135,.20)],"lp":Vector3(.9,-.5,-.3),"lh":[Vector3(-.65,-.15,.75),Vector3(-.3,-.9,0)],
            "r":["hip",Vector3(-.04,.125,.22)],"rp":Vector3(-.9,-.5,-.3),"rh":[Vector3(.65,-.15,.75),Vector3(.3,-.9,0)]})
    else:
        pose.merge({
            "l":["hip",Vector3(spread+.035,.12,.25)],"lp":Vector3(.8,-.6,-.4),"lh":[Vector3(0,-.12,1),Vector3(0,-1,-.1)],
            "r":["hip",Vector3(-spread-.035,.12,.25)],"rp":Vector3(-.8,-.6,-.4),"rh":[Vector3(0,-.12,1),Vector3(0,-1,-.1)]})
    return pose

func skeleton_path(clip: Animation) -> String:
    for track in clip.get_track_count():
        if clip.track_get_type(track)==Animation.TYPE_ROTATION_3D:
            return str(clip.track_get_path(track)).get_slice(":",0)
    return ""

## Lowers the arms once per imported clip, so people stand and walk with their arms at their sides.
func complete(clip: Animation,sk: Skeleton3D) -> void:
    var node := skeleton_path(clip)
    if node.is_empty() or clip.has_meta("life_relaxed"): return
    clip.set_meta("life_relaxed",true)
    var tracks := {}
    var live: Array[Quaternion] = []
    for i in sk.get_bone_count(): live.append(sk.get_bone_pose_rotation(i))
    for track in clip.get_track_count():
        if clip.track_get_type(track)!=Animation.TYPE_ROTATION_3D: continue
        var id := sk.find_bone(str(clip.track_get_path(track).get_concatenated_subnames()))
        if id>=0: tracks[id] = track
    var arms := []
    var times := {}
    for side in ["l","r"]:
        var arm := [sk.find_bone("upperarm_"+side),sk.find_bone("lowerarm_"+side),sk.find_bone("hand_"+side),1.0 if side=="l" else -1.0]
        if arm[0]<0 or arm[1]<0 or arm[2]<0 or not tracks.has(arm[0]) or not tracks.has(arm[1]): continue
        arms.append(arm)
        for bone: int in [arm[0],arm[1]]:
            for key in clip.track_get_key_count(tracks[bone]): times[clip.track_get_key_time(tracks[bone],key)] = {}
    # Pose the rig as the clip has it at each key time, hang the arms, and read the new keys back.
    for time: float in times:
        for id: int in tracks: sk.set_bone_pose_rotation(id,clip.rotation_track_interpolate(tracks[id],time))
        sk.force_update_all_bone_transforms()
        for arm: Array in arms:
            var shoulder := sk.get_bone_global_pose(arm[0]).origin
            var elbow := sk.get_bone_global_pose(arm[1]).origin
            var spread := atan2(absf(elbow.x-shoulder.x),shoulder.y-elbow.y)
            orient(sk,arm[0],Basis(Vector3.BACK,-float(arm[3])*(spread*(1.0-ARM_KEEP)-ARM_HANG))*sk.get_bone_global_pose(arm[0]).basis)
            elbow = sk.get_bone_global_pose(arm[1]).origin
            var along := (elbow-shoulder).normalized()
            var forearm := (sk.get_bone_global_pose(arm[2]).origin-elbow).normalized()
            var hinge := along.cross(forearm)
            if hinge.length()>.001:
                orient(sk,arm[1],Basis(hinge.normalized(),-(along.angle_to(forearm)*(1.0-ELBOW_KEEP)-ELBOW_REST))*sk.get_bone_global_pose(arm[1]).basis)
            times[time][arm[0]] = sk.get_bone_pose_rotation(arm[0])
            times[time][arm[1]] = sk.get_bone_pose_rotation(arm[1])
    for arm: Array in arms:
        for bone: int in [arm[0],arm[1]]:
            for key in clip.track_get_key_count(tracks[bone]):
                clip.track_set_key_value(tracks[bone],key,times[clip.track_get_key_time(tracks[bone],key)][bone])
    for i in live.size(): sk.set_bone_pose_rotation(i,live[i])

## Clips are baked one at a time, the first time a character needs them, so spawning
## never stalls on the whole set. Every instance of that character shares the libraries:
## "life" holds standing gestures built on Idle, "sit" the same gestures built on the seated pose.
func prepare(person: Node3D,name: String,seated := false) -> bool:
    var index: int = person.get_meta("cast_index",-1)
    if not libraries.has(index): return false
    var library: AnimationLibrary = libraries[index]["sit" if seated else LIB]
    if library.has_animation(name): return true
    if name!="Sit" and not clips.has(name): return false
    var player: AnimationPlayer = person.get_meta("player")
    var found := person.find_children("*","Skeleton3D",true,false)
    if found.is_empty() or not player.has_animation("Idle"): return false
    var sk := found[0] as Skeleton3D
    var idle := player.get_animation("Idle")
    var clip: Animation
    if name=="Sit":
        var pose := sit_pose(women[index],index%2==0)
        clip = bake(sk,idle,[idle.length,[[0.0,pose],[idle.length,pose]]],false,true)
    elif seated:
        if not prepare(person,"Sit",true): return false
        clip = bake(sk,library.get_animation("Sit"),clips[name],index%3==1,false)
    else:
        clip = bake(sk,idle,clips[name],index%3==1,false)
    if clip==null: return false
    library.add_animation(name,clip)
    return true

func bake(sk: Skeleton3D,source: Animation,spec: Array,flip: bool,loop: bool) -> Animation:
    var node := skeleton_path(source)
    var ids := {}
    var rest: Array[Quaternion] = []
    var live: Array[Quaternion] = []
    for i in sk.get_bone_count():
        ids[sk.get_bone_name(i)] = i
        rest.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
        live.append(sk.get_bone_pose_rotation(i))
    if node.is_empty(): return null
    for bone in pose_bones+(["pelvis","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"] as Array[String]):
        if not ids.has(bone): return null
    # Bones the source clip does not animate rest where `still` leaves them: relaxed fingers, the rest at rest.
    var base := rest.duplicate()
    var loose: Dictionary = calm(sk)
    for id: int in loose: base[id] = loose[id]
    for track in source.get_track_count():
        if source.track_get_type(track)!=Animation.TYPE_ROTATION_3D or source.track_get_key_count(track)==0: continue
        var bone := str(source.track_get_path(track).get_concatenated_subnames())
        if ids.has(bone): base[ids[bone]] = source.track_get_key_value(track,0)
    var scale: float = sk.get_bone_global_rest(ids["upperarm_l"]).origin.y/REF_SHOULDER
    var lengths := {"ankle":sk.get_bone_global_rest(ids["foot_l"]).origin.y,"hands":Hands.rig(sk)}
    for side in ["l","r"]:
        for limb: Array in [["","upperarm_","lowerarm_","hand_"],["l","thigh_","calf_","foot_"]]:
            var a: Vector3 = sk.get_bone_global_rest(ids[limb[1]+side]).origin
            var b: Vector3 = sk.get_bone_global_rest(ids[limb[2]+side]).origin
            var c: Vector3 = sk.get_bone_global_rest(ids[limb[3]+side]).origin
            lengths[side+limb[0]] = [a.distance_to(b),b.distance_to(c)]
    var poses := []
    for entry: Array in spec[1]: poses.append([entry[0],mirrored(entry[1]) if flip else entry[1]])
    var length: float = spec[0]
    var used := bones_used(poses)
    var clip := Animation.new()
    clip.length = length
    if loop: clip.loop_mode = Animation.LOOP_LINEAR
    for track in source.get_track_count():
        var kind := source.track_get_type(track)
        if kind==Animation.TYPE_ROTATION_3D and used.has(str(source.track_get_path(track).get_concatenated_subnames())): continue
        var copy := clip.add_track(kind)
        clip.track_set_path(copy,source.track_get_path(track))
        clip.track_set_interpolation_type(copy,source.track_get_interpolation_type(track))
        var moved: int = ids.get(str(source.track_get_path(track).get_concatenated_subnames()),-1)
        if loop and kind==Animation.TYPE_POSITION_3D and moved>=0:
            # A seated body rests on the bench: drop the standing sway of the hips.
            clip.position_track_insert_key(copy,0.0,sk.get_bone_rest(moved).origin)
            continue
        var offset := 0.0
        while offset<length:
            for k in source.track_get_key_count(track):
                var time := offset+source.track_get_key_time(track,k)
                if time>length: break
                clip.track_insert_key(copy,time,source.track_get_key_value(track,k))
            offset += maxf(source.length,.1)
    var tracks := {}
    var last := {}
    for bone in used:
        var track := clip.add_track(Animation.TYPE_ROTATION_3D)
        clip.track_set_path(track,NodePath(node+":"+bone))
        clip.track_set_interpolation_type(track,Animation.INTERPOLATION_CUBIC)
        if not loop:
            # A gesture starts from and returns to the pose it was built on.
            clip.rotation_track_insert_key(track,0.0,base[ids[bone]])
            clip.rotation_track_insert_key(track,length,base[ids[bone]])
        tracks[bone] = track
        last[bone] = base[ids[bone]]
    for entry: Array in poses:
        solve(sk,ids,rest,base,lengths,entry[1],scale)
        for bone in used:
            var turn: Quaternion = sk.get_bone_pose_rotation(ids[bone])
            if turn.dot(last[bone])<0.0: turn = -turn
            last[bone] = turn
            clip.rotation_track_insert_key(tracks[bone],entry[0],turn)
    # The rig is live and may be on screen: put back the pose it had.
    for i in live.size(): sk.set_bone_pose_rotation(i,live[i])
    return clip

func orient(sk: Skeleton3D,id: int,basis: Basis) -> void:
    var parent := sk.get_bone_parent(id)
    var frame := sk.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
    sk.set_bone_pose_rotation(id,(frame.inverse()*basis).orthonormalized().get_rotation_quaternion())
    sk.force_update_all_bone_transforms()

func turn_bone(sk: Skeleton3D,id: int,angles: Vector3) -> void:
    var twist := Basis(Vector3.UP,angles.x)*Basis(Vector3.RIGHT,angles.y)*Basis(Vector3.BACK,angles.z)
    orient(sk,id,twist*sk.get_bone_global_pose(id).basis)

func aim(sk: Skeleton3D,id: int,child: int,target: Vector3) -> void:
    var pose := sk.get_bone_global_pose(id)
    var current := (sk.get_bone_global_pose(child).origin-pose.origin).normalized()
    var wanted := (target-pose.origin).normalized()
    orient(sk,id,Basis(Quaternion(current,wanted))*pose.basis)

## Two-bone reach: bends the joint toward `pole` and puts the end bone on `target`.
func reach(sk: Skeleton3D,a: int,b: int,c: int,sizes: Array,target: Vector3,pole: Vector3) -> void:
    var start := sk.get_bone_global_pose(a).origin
    var la: float = sizes[0]
    var lb: float = sizes[1]
    var delta := target-start
    var distance := clampf(delta.length(),absf(la-lb)+.03,(la+lb)*.97)
    var forward := delta.normalized()
    var bend := (pole-forward*pole.dot(forward)).normalized()
    var along := (la*la+distance*distance-lb*lb)/(2.0*distance)
    aim(sk,a,b,start+forward*along+bend*sqrt(maxf(0.0,la*la-along*along)))
    aim(sk,b,c,start+forward*distance)

func solve(sk: Skeleton3D,ids: Dictionary,rest: Array,base: Array,lengths: Dictionary,pose: Dictionary,scale: float) -> void:
    for i in base.size(): sk.set_bone_pose_rotation(i,base[i])
    sk.force_update_all_bone_transforms()
    if pose.has("spine"):
        var lean: Vector3 = pose["spine"]
        turn_bone(sk,ids["spine_02"],lean*.5)
        turn_bone(sk,ids["spine_03"],lean*.5)
    if pose.has("head"):
        var look: Vector3 = pose["head"]
        turn_bone(sk,ids["neck_01"],look*.4)
        turn_bone(sk,ids["head"],look*.6)
    for side: String in ["l","r"]:
        if pose.has(side+"l"):
            # The bench is a fixed height, whatever the body size: feet go to the real floor.
            var step: Array = pose[side+"l"]
            var place: Vector3 = step[1]
            var floor_drop: float = SEAT_TOP-FLOOR+PELVIS_LIFT*scale-lengths["ankle"]
            var ankle := sk.get_bone_global_pose(ids["pelvis"]).origin+Vector3(place.x*scale,place.y*scale-floor_drop,place.z*scale)
            reach(sk,ids["thigh_"+side],ids["calf_"+side],ids["foot_"+side],lengths[side+"l"],ankle,pose.get(side+"lp",Vector3(0,.6,.8)))
        if not pose.has(side): continue
        var upper: int = ids["upperarm_"+side]
        var lower: int = ids["lowerarm_"+side]
        var hand: int = ids["hand_"+side]
        var goal: Array = pose[side]
        var anchor: int = {"head":ids["head"],"chest":ids["spine_03"],"hip":ids["pelvis"]}.get(goal[0],upper)
        var offset: Vector3 = goal[1]
        reach(sk,upper,lower,hand,lengths[side],sk.get_bone_global_pose(anchor).origin+offset*scale,pose.get(side+"p",Vector3(.5 if side=="l" else -.5,-1,-.2)))
        if pose.has(side+"h"):
            var grip: Array = pose[side+"h"]
            var fingers: Vector3 = (grip[0] as Vector3).normalized()
            var forearm := (sk.get_bone_global_pose(hand).origin-sk.get_bone_global_pose(lower).origin).normalized()
            var wrist := forearm.angle_to(fingers)
            # Keep the wrist within a natural bend, whatever direction the pose asks for.
            if wrist>1.05: fingers = forearm.slerp(fingers,1.05/wrist).normalized()
            var palm: Vector3 = grip[1]
            palm = (palm-fingers*palm.dot(fingers)).normalized()
            orient(sk,hand,Basis(fingers.cross(palm),fingers,palm))
        if pose.has(side+"f"):
            var fingers_now: Dictionary = Hands.shape(lengths["hands"],side,pose[side+"f"],pose.get(side+"point",false))
            for id: int in fingers_now: sk.set_bone_pose_rotation(id,fingers_now[id])
    sk.force_update_all_bone_transforms()

# ---------------------------------------------------------------- people

func adopt(person: Node3D) -> void:
    if not person.has_meta("player"): return
    var found := person.find_children("*","Skeleton3D",true,false)
    if found.is_empty(): return
    var sk := found[0] as Skeleton3D
    var player: AnimationPlayer = person.get_meta("player")
    var index: int = person.get_meta("cast_index",-1)
    for clip in ["Idle","Walk"]:
        if player.has_animation(clip): complete(player.get_animation(clip),sk)
    if not libraries.has(index):
        libraries[index] = {LIB:AnimationLibrary.new(),"sit":AnimationLibrary.new()}
        var female := false
        for mesh in person.find_children("*","MeshInstance3D",true,false):
            if "female" in str(mesh.name).to_lower(): female = true
        women[index] = female
    for name: String in libraries[index]:
        if not player.has_animation_library(name): player.add_animation_library(name,libraries[index][name])
    player.playback_default_blend_time = .3
    var head := sk.find_bone("head")
    var shoulder := sk.find_bone("upperarm_l")
    var pelvis := sk.find_bone("pelvis")
    person.set_meta("life_height",sk.get_bone_global_rest(head).origin.y+.21 if head>=0 else 1.75)
    person.set_meta("life_scale",sk.get_bone_global_rest(shoulder).origin.y/REF_SHOULDER if shoulder>=0 else 1.0)
    person.set_meta("life_hip",sk.get_bone_global_rest(pelvis).origin.y if pelvis>=0 else .93)
    person.set_meta("life_female",women[index])
    person.set_meta("life_pitch",.95+float(index*7%5)*.03)
    person.set_meta("life_sway",.8+float(index*5%7)*.07)
    person.set_meta("life_next",clock+randf_range(1.5,9.0))
    still(person)
    var casters: Array[MeshInstance3D] = []
    for mesh: MeshInstance3D in person.find_children("*","MeshInstance3D",true,false):
        var part := str(mesh.name).to_lower()
        # Lashes, brows and eyes are too small to matter in the shadow passes.
        if "eyebrow" in part or "eyelash" in part or "low-poly" in part: mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        else: casters.append(mesh)
    person.set_meta("life_casters",casters)
    # A soft patch of shade under the feet keeps people grounded on overcast days and indoors.
    if blob==null:
        var fade := Gradient.new()
        fade.set_color(0,Color(0,0,0,.46))
        fade.set_color(1,Color(0,0,0,0))
        var disc := GradientTexture2D.new()
        disc.gradient = fade
        disc.fill = GradientTexture2D.FILL_RADIAL
        disc.fill_from = Vector2(.5,.5)
        disc.fill_to = Vector2(1.0,.5)
        disc.width = 64
        disc.height = 64
        var shade := StandardMaterial3D.new()
        shade.albedo_texture = disc
        shade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        shade.render_priority = -1
        blob = PlaneMesh.new()
        blob.size = Vector2(.86,.86)
        blob.material = shade
    var patch := MeshInstance3D.new()
    patch.mesh = blob
    patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    patch.position = Vector3(0,.014,.02)
    person.add_child(patch)

## Far-off pedestrians keep only the soft patch under their feet; full shadows are for those nearby.
func shade(person: Node3D,on: bool) -> void:
    person.set_meta("life_shaded",on)
    for mesh: MeshInstance3D in person.get_meta("life_casters",[]):
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## In the browser, people seen only from a distance go without lashes and brows.
func simplify(person: Node3D) -> void:
    if not OS.has_feature("web"): return
    for mesh: MeshInstance3D in person.find_children("*","MeshInstance3D",true,false):
        var part := str(mesh.name).to_lower()
        if "eyebrow" in part or "eyelash" in part: mesh.hide()

## Recolours the clothes so repeated models on a busy street do not look like twins.
func restyle(person: Node3D,variant: int) -> void:
    var tone: Color = TONES[posmod(variant,TONES.size())]
    if tone==Color.WHITE: return
    var index: int = person.get_meta("cast_index",-1)
    for mesh: MeshInstance3D in person.find_children("*","MeshInstance3D",true,false):
        if not "suit" in str(mesh.name).to_lower() or mesh.mesh==null: continue
        for surface in mesh.mesh.get_surface_count():
            var key := "%d/%s/%d/%d" % [index,mesh.name,surface,posmod(variant,TONES.size())]
            if not outfits.has(key):
                var cloth := mesh.get_active_material(surface)
                if not cloth is StandardMaterial3D: continue
                var dyed := cloth.duplicate() as StandardMaterial3D
                dyed.albedo_color = dyed.albedo_color*tone
                outfits[key] = dyed
            mesh.set_surface_override_material(surface,outfits[key])

## The relaxed finger pose of a rig: bone index -> rotation.
func calm(sk: Skeleton3D) -> Dictionary:
    var hand_rig := Hands.rig(sk)
    var out := {}
    for side in ["l","r"]: out.merge(Hands.shape(hand_rig,side,FINGER_REST))
    return out

## Puts the bones that Idle, Walk and Sit never animate into their resting pose.
func still(person: Node3D) -> void:
    var found := person.find_children("*","Skeleton3D",true,false)
    if found.is_empty(): return
    var sk := found[0] as Skeleton3D
    var player: AnimationPlayer = person.get_meta("player")
    var clip := player.get_animation(player.current_animation) if player.has_animation(player.current_animation) else null
    var node := skeleton_path(clip) if clip!=null else ""
    var loose: Dictionary = calm(sk)
    for bone in ["hand_l","hand_r","spine_03","neck_01"]:
        var id := sk.find_bone(bone)
        if id>=0: loose[id] = sk.get_bone_rest(id).basis.get_rotation_quaternion()
    for id: int in loose:
        # Leave alone what the current clip is animating, such as hands resting on the thighs.
        if clip!=null and clip.find_track(NodePath(node+":"+sk.get_bone_name(id)),Animation.TYPE_ROTATION_3D)>=0: continue
        sk.set_bone_pose_rotation(id,loose[id])

func current(person: Node3D) -> String:
    if not is_instance_valid(person) or not person.has_meta("player"): return "?"
    var player: AnimationPlayer = person.get_meta("player")
    return str(player.current_animation) if player.active else "?"

func gesture(clip: String) -> bool:
    return clip.begins_with(LIB+"/") or (clip.begins_with("sit/") and clip!="sit/Sit")

## Standing or sitting still and not needed by the driver, boarding or an encounter.
func settled(person: Node3D,allow_gesture := false) -> bool:
    var clip := current(person)
    if clip!="Idle" and clip!="sit/Sit" and not (allow_gesture and gesture(clip)): return false
    if person.get_meta("life_seat","") in ["sitting","rising"]: return false
    return not person.get_meta("encounter_busy",false)

func perform(person: Node3D,clip := "",pool: Array[String] = idle_pool) -> float:
    if current(person)=="?": return 0.0
    var state: String = person.get_meta("life_seat","")
    if state=="sitting" or state=="rising": return 0.0
    var seated := state=="seated"
    var player: AnimationPlayer = person.get_meta("player")
    if clip.is_empty():
        clip = pool[randi()%pool.size()]
        if clip==person.get_meta("life_last","") and pool.size()>1: clip = pool[(pool.find(clip)+1+randi()%(pool.size()-1))%pool.size()]
    var full := ("sit/" if seated else LIB+"/")+clip
    if not prepare(person,clip,seated) or not player.has_animation(full): return 0.0
    person.set_meta("life_last",clip)
    player.play(full,.3)
    player.queue("sit/Sit" if seated else "Idle")
    person.set_meta("life_tidy",3) # Scans to wait after the gesture, so the blend out of it has finished.
    if not fidgets.has(person): fidgets.append(person)
    return player.get_animation(full).length/maxf(player.speed_scale,.1)

func idle_round(people: Array,pool: Array[String]) -> void:
    for person: Node3D in people:
        if not settled(person) or person.has_meta("life_talk"): continue
        if clock<person.get_meta("life_next",0.0): continue
        person.set_meta("life_next",clock+perform(person,"",pool)+randf_range(4.0,13.0))

## Someone at the stop waves as the tram pulls in.
func hail() -> void:
    if game.queued.is_empty() or game.doors_open or waved_stop==game.next_stop: return
    var gap: float = game.distance_to_stop()
    if game.velocity<1.5 or gap>48.0 or gap<6.0: return
    for person: Node3D in game.queued:
        if settled(person) and not person.has_meta("life_talk"):
            person.set_meta("life_next",clock+perform(person,"Wave")+randf_range(5.0,11.0))
            waved_stop = game.next_stop
            return

# ---------------------------------------------------------------- seats

## Picks a bench seat the way people do: most leave a gap to strangers, a few sit down
## beside someone, and seats near the door they came in by go first. Falls back to standing in the aisle.
func assign_seat(person: Node3D,riders: Array) -> void:
    var taken := {}
    for rider: Node3D in riders:
        if rider!=person: taken[rider.get_meta("seat_index",-1)] = true
    var index: int = person.get_meta("cast_index",0)
    var scale: float = person.get_meta("life_scale",1.0)
    var door: float = person.get_meta("door_z",0.0)
    var best := -1
    var best_score := -INF
    for i in seats.size():
        if taken.has(i): continue
        var near := 0
        for j in seats.size():
            if taken.has(j) and seats[j].x==seats[i].x and absf(seats[j].y-seats[i].y)<.7: near += 1
        var crowding := -3.2*near
        if index%5==0: crowding = 1.0 if near==1 else -1.5*near
        var score := crowding-absf(seats[i].y-door)*.11+fposmod(float(index*37+i*53)*.618,1.0)*1.1
        if score>best_score:
            best_score = score
            best = i
    if best<0:
        var extra := seats.size()
        while taken.has(extra): extra += 1
        var row := extra-seats.size()
        person.set_meta("seat_index",extra)
        person.set_meta("seat",Vector3(-.2 if row%2==0 else .2,FLOOR,3.9-row*.85))
        return
    var seat := seats[best]
    person.set_meta("seat_index",best)
    person.set_meta("seat",Vector3(seat.x*.42,FLOOR,seat.y))
    person.set_meta("bench",Vector3(seat.x*(BACKREST-.125*scale),SEAT_TOP+PELVIS_LIFT*scale-float(person.get_meta("life_hip",.93)),seat.y))

func travel(person: Node3D,to: Vector3,yaw: float,span: float,state: String,then: String) -> void:
    person.set_meta("life_seat",state)
    person.set_meta("life_move",[person.position,to,person.rotation.y,yaw,0.0,span,then])
    if not movers.has(person): movers.append(person)

## Call when a passenger reaches their place in the saloon: they sit down if they have a seat.
func settle(person: Node3D) -> void:
    var spot: Vector3 = person.get_meta("seat",person.position)
    var yaw := person.rotation.y
    if person.has_meta("bench"): yaw = PI*.5 if spot.x<0.0 else -PI*.5
    person.set_meta("life_yaw",yaw)
    person.set_meta("life_next",clock+randf_range(2.5,9.0))
    if not person.has_meta("bench") or current(person)=="?" or not prepare(person,"Sit",true): return
    var player: AnimationPlayer = person.get_meta("player")
    player.clear_queue()
    player.play("sit/Sit",.6)
    travel(person,person.get_meta("bench"),yaw,.75,"sitting","seated")

func unsettle(person: Node3D) -> void:
    if not person.has_meta("life_yaw"): return
    person.remove_meta("life_yaw")
    if person.has_meta("life_posed"): person.remove_meta("life_posed")
    person.rotation = Vector3(0,person.rotation.y,0)

## True once the passenger is on their feet and free to walk; starts getting up otherwise.
func rise(person: Node3D) -> bool:
    homing.erase(person)
    var state: String = person.get_meta("life_seat","")
    if state=="rising": return false
    if state=="":
        unsettle(person)
        return true
    release(person)
    unsettle(person)
    if current(person)!="?":
        var player: AnimationPlayer = person.get_meta("player")
        player.clear_queue()
        player.play("Idle",.45)
    travel(person,person.get_meta("seat",person.position),person.rotation.y,.6,"rising","")
    return false

## Walk a passenger back to their place after the driver has dealt with them.
func send_home(person: Node3D) -> void:
    if is_instance_valid(person) and person.get_meta("life_seat","")=="" and not homing.has(person): homing.append(person)

func move_people(dt: float) -> void:
    for i in range(movers.size()-1,-1,-1):
        var person = movers[i]
        if not is_instance_valid(person):
            movers.remove_at(i)
            continue
        var move: Array = person.get_meta("life_move")
        move[4] = minf(1.0,move[4]+dt/move[5])
        var eased := smoothstep(0.0,1.0,move[4])
        person.position = (move[0] as Vector3).lerp(move[1],eased)
        person.rotation = Vector3(0,lerp_angle(move[2],move[3],eased),0)
        if move[4]>=1.0:
            movers.remove_at(i)
            person.set_meta("life_seat",move[6])
    for i in range(homing.size()-1,-1,-1):
        var person = homing[i]
        if not is_instance_valid(person) or not game.onboard.has(person) or game.transit.has(person):
            homing.remove_at(i)
        elif game.walk_to(person,person.get_meta("seat",person.position),dt,1.1):
            homing.remove_at(i)
            settle(person)

## Bodies follow the tram: people lean back when it pulls away, forward when it brakes
## and outward in curves; standing passengers more than seated ones.
func posture(dt: float) -> void:
    var along: float = game.acceleration if absf(game.velocity)>.03 and not game.doors_open else 0.0
    var target := (Vector2(-game.dynamics.lateral_accel,-along)*.042).limit_length(.13)
    sway_speed += ((target-sway)*30.0-sway_speed*6.5)*dt
    sway += sway_speed*dt
    for person: Node3D in game.onboard:
        if not person.has_meta("life_yaw"): continue
        var state: String = person.get_meta("life_seat","")
        if state=="sitting" or state=="rising": continue
        if current(person)=="Walk" or person.get_meta("encounter_busy",false):
            unsettle(person)
            continue
        var seated := state=="seated"
        var turn: float = lerpf(person.get_meta("life_turned",0.0),person.get_meta("life_turn",0.0),minf(dt*3.5,1.0))
        person.set_meta("life_turned",turn)
        var lean := Vector3(sway.x,0,sway.y)*(.42 if seated else 1.0)*float(person.get_meta("life_sway",1.0))
        var tilt := Basis(Vector3.UP.cross(lean).normalized(),lean.length()) if lean.length()>.0004 else Basis.IDENTITY
        var stamp := Vector3(lean.x,turn,lean.z)
        if stamp.distance_to(person.get_meta("life_posed",Vector3.INF))<.0003: continue
        person.set_meta("life_posed",stamp)
        person.basis = tilt*Basis(Vector3.UP,float(person.get_meta("life_yaw"))+turn)
        if seated:
            # Lean from the hips, which stay on the bench.
            var hips := Vector3(0,person.get_meta("life_hip",.93),0)
            person.position = (person.get_meta("bench") as Vector3)+hips-tilt*hips

# ---------------------------------------------------------------- small talk

func chatty(person: Node3D) -> bool:
    return is_instance_valid(person) and settled(person,true) and not person.has_meta("life_talk") and clock>=person.get_meta("life_quiet",0.0)

func start_talks() -> void:
    if game.encounters!=null and game.encounters.interacting: return
    var near := false
    var street := 0
    for talk in talks:
        if talk.where=="street": street += 1
        else: near = true
    if not near and clock>=near_next:
        var pairs := []
        var riders: Array[Node3D] = []
        for person: Node3D in game.onboard:
            if chatty(person) and person.has_meta("life_yaw") and not game.outgoing.has(person): riders.append(person)
        for i in riders.size():
            for j in range(i+1,riders.size()):
                if riders[i].position.distance_to(riders[j].position)<2.0: pairs.append([riders[i],riders[j],"ride"])
        if not game.doors_open:
            for i in game.queued.size():
                for j in range(i+1,game.queued.size()):
                    var a: Node3D = game.queued[i]
                    var b: Node3D = game.queued[j]
                    if chatty(a) and chatty(b) and a.global_position.distance_to(b.global_position)<1.7: pairs.append([a,b,"stop"])
        if not pairs.is_empty():
            var pair: Array = pairs[randi()%pairs.size()]
            begin(pair[0],pair[1],pair[2])
    if street<2 and clock>=street_next:
        for pair in game.chatters.size()/2:
            var a: Node3D = game.chatters[pair*2]
            var b: Node3D = game.chatters[pair*2+1]
            if chatty(a) and chatty(b):
                begin(a,b,"street")
                break

func begin(a: Node3D,b: Node3D,where: String) -> void:
    var allowed := {"ride":"*ti","stop":"*tp","street":"*"}[where] as String
    allowed += "r" if game.rain>.45 else "d"
    var options: Array[int] = []
    for i in TALKS.size():
        if not recent.has(i) and allowed.contains(TALKS[i][0]): options.append(i)
    if options.is_empty():
        recent.clear()
        return
    var script: int = options[randi()%options.size()]
    recent.append(script)
    if recent.size()>8: recent.pop_front()
    if randf()<.5:
        var swap := a
        a = b
        b = swap
    for person: Node3D in [a,b]: person.set_meta("life_talk",true)
    if where=="stop":
        var toward := b.global_position-a.global_position
        a.set_meta("life_face",atan2(toward.x,toward.z))
        b.set_meta("life_face",atan2(-toward.x,-toward.z))
    elif where=="ride":
        # Bench neighbours turn a little toward each other; people across the aisle already face.
        var apart := b.position-a.position
        a.set_meta("life_turn",clampf(wrapf(atan2(apart.x,apart.z)-float(a.get_meta("life_yaw",0.0)),-PI,PI),-.5,.5))
        b.set_meta("life_turn",clampf(wrapf(atan2(-apart.x,-apart.z)-float(b.get_meta("life_yaw",0.0)),-PI,PI),-.5,.5))
    var voice := AudioStreamPlayer3D.new()
    voice.unit_size = 2.2
    voice.max_distance = 20.0
    voice.volume_db = voice_db
    voice.stream_paused = hushed
    add_child(voice)
    var bubble := new_bubble(where=="ride")
    bubble.hide()
    a.add_child(bubble)
    talks.append({"a":a,"b":b,"where":where,"script":script,"line":-1,"left":randf_range(.3,.9),"voice":voice,"bubble":bubble})

func new_bubble(inside: bool) -> Label3D:
    var bubble := Label3D.new()
    bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    bubble.fixed_size = true
    bubble.font_size = 32
    bubble.outline_size = 10
    bubble.modulate = Color("#fff5e2")
    bubble.outline_modulate = Color("#1c2431")
    bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    bubble.width = 430
    bubble.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    bubble.visibility_range_end = 17.0
    # Inside the tram the ceiling and lamps sit right above the heads; keep those lines readable.
    bubble.no_depth_test = inside
    # Character materials are alpha-blended; draw the text after them.
    bubble.render_priority = 20
    bubble.outline_render_priority = 19
    var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
    # A fixed-size label keeps a constant angle, so follow the field of view to keep its screen size.
    bubble.pixel_size = .00135*tan(deg_to_rad(camera.fov if camera!=null else 70.0)*.5)
    return bubble

## Someone has just been hit: they recoil and protest, and the people nearby notice.
func flinch(person: Node3D,text: String) -> void:
    release(person)
    if not person.get_meta("encounter_busy",false):
        person.set_meta("life_next",clock+perform(person,"Flinch")+randf_range(4.0,8.0))
    var bubble := new_bubble(true)
    person.add_child(bubble)
    bubble.position = Vector3(0,float(person.get_meta("life_height",1.75))+.10,0)
    bubble.text = text
    bubble.visible = game.preferences!=null and game.preferences.subtitles
    shouts.append({"bubble":bubble,"left":3.2})
    var seen := 0
    for other: Node3D in game.onboard:
        if other==person or seen>=3 or not settled(other) or other.has_meta("life_talk"): continue
        if other.position.distance_to(person.position)<2.8:
            other.set_meta("life_next",clock+perform(other,"HeadShake" if seen%2==0 else "LookAround")+randf_range(3.0,8.0))
            seen += 1

func finish(talk: Dictionary) -> void:
    talks.erase(talk)
    for key in ["voice","bubble"]:
        if is_instance_valid(talk[key]): talk[key].queue_free()
    for key in ["a","b"]:
        if not is_instance_valid(talk[key]): continue
        var person: Node3D = talk[key]
        for tag in ["life_talk","life_face","life_turn"]:
            if person.has_meta(tag): person.remove_meta(tag)
        person.set_meta("life_quiet",clock+randf_range(9.0,24.0))
        person.set_meta("life_next",clock+randf_range(3.0,9.0))
    if talk.where=="street": street_next = clock+randf_range(1.5,4.0)
    else: near_next = clock+randf_range(5.0,12.0)

## Drop a person out of any conversation, for instance when they are moved elsewhere.
func release(person: Node3D) -> void:
    for talk in talks.duplicate():
        if talk.a==person or talk.b==person: finish(talk)

func silence() -> void:
    for talk in talks.duplicate(): finish(talk)

func hush(paused: bool) -> void:
    hushed = paused
    for talk in talks:
        if is_instance_valid(talk.voice): talk.voice.stream_paused = paused

func follow(talk: Dictionary,dt: float) -> void:
    for key in ["a","b"]:
        var person = talk[key]
        if not is_instance_valid(person) or person.is_queued_for_deletion() or current(person)=="Walk" or current(person)=="?" or person.get_meta("encounter_busy",false):
            finish(talk)
            return
    var a: Node3D = talk.a
    var b: Node3D = talk.b
    if a.global_position.distance_to(b.global_position)>3.0:
        finish(talk)
        return
    var speaker: Node3D = a if talk.line%2==0 else b
    var voice: AudioStreamPlayer3D = talk.voice
    var bubble: Label3D = talk.bubble
    voice.global_position = speaker.global_position+Vector3.UP*1.5
    if voice.playing and not game.voice_enabled: voice.stop()
    var captions: bool = game.preferences!=null and game.preferences.subtitles
    bubble.visible = captions and talk.line>=0
    talk.left -= dt
    if talk.left>0.0: return
    talk.line += 1
    var lines: Array = TALKS[talk.script]
    if talk.line>=lines.size()-1:
        finish(talk)
        return
    speaker = a if talk.line%2==0 else b
    var text: String = lines[talk.line+1]
    if bubble.get_parent()!=speaker: bubble.reparent(speaker,false)
    bubble.position = Vector3(0,speaker.get_meta("life_height",1.75)+.10,0)
    bubble.text = text
    bubble.visible = captions
    perform(speaker,"",close_talk_pool if talk.where=="ride" else talk_pool)
    if randf()<.7: perform(b if speaker==a else a,"",listen_pool)
    var seconds := 1.1+text.length()*.058
    if game.voice_enabled:
        var file := "res://assets/voice/chatter/t%02d_%d_%s.mp3" % [talk.script,talk.line,"f" if speaker.get_meta("life_female",false) else "m"]
        if ResourceLoader.exists(file):
            var stream := load(file) as AudioStream
            voice.stream = stream
            voice.pitch_scale = speaker.get_meta("life_pitch",1.0)
            voice.volume_db = voice_db
            voice.global_position = speaker.global_position+Vector3.UP*1.5
            voice.play()
            seconds = stream.get_length()/voice.pitch_scale+.15
    talk.left = seconds+randf_range(.25,.6)

func tick(dt: float) -> void:
    clock += dt
    move_people(dt)
    posture(dt)
    for talk in talks.duplicate(): follow(talk,dt)
    for shout in shouts.duplicate():
        shout.left -= dt
        if shout.left<=0.0 or not is_instance_valid(shout.bubble):
            if is_instance_valid(shout.bubble): shout.bubble.queue_free()
            shouts.erase(shout)
    scan -= dt
    if scan>0.0: return
    scan = .35
    # Once a gesture is over or was cut short, put hands and fingers back to their resting pose.
    for i in range(fidgets.size()-1,-1,-1):
        var person = fidgets[i]
        if not is_instance_valid(person):
            fidgets.remove_at(i)
        elif gesture(current(person)):
            person.set_meta("life_tidy",3)
        else:
            var left: int = int(person.get_meta("life_tidy",0))-1
            person.set_meta("life_tidy",left)
            if left<=0:
                fidgets.remove_at(i)
                still(person)
    idle_round(game.onboard,ride_pool)
    idle_round(game.queued,stop_pool)
    hail()
    start_talks()
