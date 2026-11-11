extends RefCounted
## Reduced-order rail vehicle model. SI units; advisory speeds never cause a derailment.
## Tare/body mass: Museo Nazionale Scienza e Tecnologia, ATM series 1500.
## Contact criterion: Nadal Y/Q, supplemented by inner-wheel unloading.
const GRAVITY := 9.81
const TARE_MASS := 15500.0
const BODY_MASS := 8500.0
const GAUGE := 1.51 # Matches the existing rails at x = +/-0.755 m.
const BOGIE_HALF := 3.85
const AXLE_SPACING := 1.625
const CG_HEIGHT := 1.38
const FLANGE_HEIGHT := 0.028
const FLANGE_ANGLE := deg_to_rad(68.0)
const ROLL_STIFFNESS := 320000.0
const ROLL_DAMPING := 55000.0

var mass := TARE_MASS
var roll := 0.0
var roll_rate := 0.0
var pitch := 0.0
var pitch_rate := 0.0
var lateral_accel := 0.0
var wheel_unload := 0.0
var flange_ratio := 0.0
var climb := [0.0, 0.0]
var failed_bogie := -1
var slip := 0.0

func adhesion(wet: bool) -> float:
    return 0.105 if wet else 0.24

func longitudinal(speed: float, notch: int, active: bool, direction: int, pressure: float, emergency: bool, wet: bool, riders: int, governor: float) -> float:
    mass = TARE_MASS + 75.0 * riders
    var grip := adhesion(wet) * mass * GRAVITY
    var requested := 0.0
    if active and notch > 0 and absf(speed) < governor:
        requested = minf(25000.0, 112000.0 / maxf(absf(speed), 3.0)) * float(notch) / 5.0
    slip = maxf(requested - grip, 0.0) / maxf(grip, 1.0)
    var traction := minf(requested, grip) * direction
    var brake_force := minf((35000.0 if emergency else 28500.0) * pressure, grip)
    var drag := 210.0 + 8.0 * absf(speed) + 2.8 * speed * speed
    if absf(speed) < 0.025 and absf(traction) <= brake_force + drag:
        return -speed * 120.0
    return (traction - signf(speed if absf(speed) > 0.025 else traction) * (brake_force + drag)) / mass

func step(route: Node3D, s: float, speed: float, acceleration: float, riders: int, wet: bool, dt: float) -> void:
    mass = TARE_MASS + 75.0 * riders
    var remaining := minf(dt, 0.25)
    while remaining > 0.000001:
        var h := minf(remaining, 1.0 / 120.0)
        remaining -= h
        var a: float = speed * speed * route.curvature(s)
        lateral_accel = a
        var sprung := BODY_MASS + 75.0 * riders
        var inertia := sprung * 1.25
        var moment := sprung * 1.05 * a
        # Progressive suspension bump stops, rather than a hard angular clamp.
        var bump := signf(roll) * maxf(absf(roll) - 0.105, 0.0) * 2300000.0
        roll_rate += (moment - ROLL_STIFFNESS * roll - ROLL_DAMPING * roll_rate - bump) / inertia * h
        roll += roll_rate * h
        pitch_rate += (-acceleration * 0.018 - pitch) * 22.0 * h - pitch_rate * 7.0 * h
        pitch += pitch_rate * h
        flange_ratio = 0.0
        wheel_unload = 0.0
        var mu_flange := 0.17 if wet else 0.30
        var nadal := (tan(FLANGE_ANGLE) - mu_flange) / (1.0 + mu_flange * tan(FLANGE_ANGLE))
        for bogie in range(2):
            var at := s + (BOGIE_HALF if bogie == 0 else -BOGIE_HALF)
            var k: float = route.curvature(at)
            var local_a := speed * speed * k
            var transfer := absf(2.0 * (local_a * CG_HEIGHT + GRAVITY * 0.65 * sin(roll)) / (GRAVITY * GAUGE))
            wheel_unload = maxf(wheel_unload, transfer)
            var bogie_load := mass * GRAVITY * 0.5
            var outer_q := bogie_load * 0.25 * (1.0 + minf(transfer, 1.0))
            # Leading axle flange force includes the bogie's finite angle of attack.
            var attack := absf(k) * AXLE_SPACING * 0.5
            var creep := minf(420000.0 * attack, bogie_load * 0.35) * clampf(absf(speed) / 4.0, 0.0, 1.0)
            var lateral_force := mass * 0.5 * absf(local_a) * 0.70 + creep
            var ratio := lateral_force / maxf(outer_q, 1.0)
            flange_ratio = maxf(flange_ratio, ratio / nadal)
            var excess := maxf(ratio / nadal - 1.0, transfer - 1.0)
            if excess > 0.0:
                climb[bogie] += excess * absf(speed) * h * 0.055
            else:
                climb[bogie] = maxf(0.0, climb[bogie] - absf(speed) * h * 0.018 - h * 0.003)
            if failed_bogie < 0 and climb[bogie] >= FLANGE_HEIGHT:
                failed_bogie = bogie

func body_frame(track: Transform3D) -> Transform3D:
    var basis := track.basis * Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, pitch)
    var pivot := Vector3(0, 0.45, 0)
    return Transform3D(basis, track.origin + track.basis * pivot - basis * pivot)
