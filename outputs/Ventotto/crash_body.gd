extends RigidBody3D
## The renderer/cab becomes a child of this body at rail contact loss.
## No scripted displacement or cancellation of speed is applied after handover.
var route: Node3D
var retained_bogie := -1
var rail_s := 0.0
var wet := false
var elapsed := 0.0
var contact_peak := 0.0
var rail_force := 0.0

func configure(line: Node3D, dynamics: RefCounted, at: float, speed: float, rain: bool) -> void:
    route = line
    mass = dynamics.mass
    wet = rain
    retained_bogie = 1 - dynamics.failed_bogie
    rail_s = at + (3.85 if retained_bogie == 0 else -3.85)
    center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
    center_of_mass = Vector3(0, 1.38, 0)
    inertia = Vector3(mass * 17.1, mass * 16.7, mass * 1.22)
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 24
    collision_layer = 2
    collision_mask = 1
    linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
    angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
    linear_damp = 0.003
    angular_damp = 0.035
    var material := PhysicsMaterial.new()
    material.friction = 0.16 if wet else 0.27
    material.bounce = 0.015
    physics_material_override = material
    var shell := BoxShape3D.new()
    shell.size = Vector3(2.35, 2.35, 13.35)
    shape_at(shell, Vector3(0, 1.92, 0))
    for z in [-4.78, -3.16, 3.16, 4.78]:
        for x in [-0.755, 0.755]:
            var wheel := SphereShape3D.new()
            wheel.radius = 0.399
            shape_at(wheel, Vector3(x, 0.410, z))
    var frame: Transform3D = line.frame(at)
    linear_velocity = frame.basis.z * speed
    angular_velocity = Vector3.UP * speed * line.curvature(at) + frame.basis.z * dynamics.roll_rate + frame.basis.x * dynamics.pitch_rate
    # The engine integrates velocity at the COM, including its rotational component.
    linear_velocity += angular_velocity.cross(global_basis * center_of_mass)

func shape_at(shape: Shape3D, at: Vector3) -> void:
    var node := CollisionShape3D.new()
    node.shape = shape
    node.position = at
    add_child(node)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    elapsed += state.step
    contact_peak = 0.0
    for i in state.get_contact_count():
        contact_peak = maxf(contact_peak, state.get_contact_impulse(i).length() / maxf(mass, 1.0))
    if retained_bogie < 0:
        return
    var z := 3.85 if retained_bogie == 0 else -3.85
    var point := state.transform * Vector3(0, 0.405, z)
    rail_s = route.project_distance(point, rail_s)
    var frame: Transform3D = route.frame(rail_s)
    var target := frame * Vector3(0, 0.405, 0)
    var offset := point - target
    var arm := point - state.transform.origin - state.center_of_mass
    var point_velocity := state.linear_velocity + state.angular_velocity.cross(arm)
    var lateral := offset.dot(frame.basis.x)
    var attack := absf(asin(clampf(state.transform.basis.z.cross(frame.basis.z).y, -1.0, 1.0)))
    if absf(lateral) > 0.145 or absf(offset.y) > 0.17 or attack > 0.16:
        retained_bogie = -1
        return
    var along := point_velocity.dot(frame.basis.z)
    var requested: float = mass * 0.5 * along * along * route.curvature(rail_s) - lateral * 850000.0 - point_velocity.dot(frame.basis.x) * 62000.0
    var limit := mass * 9.81 * 0.60
    rail_force = clampf(requested, -limit, limit)
    var force := frame.basis.x * rail_force
    # The remaining bogie supports weight but cannot pull a wheel down onto a rail.
    force.y = clampf(mass * 9.81 * 0.5 - offset.y * 950000.0 - point_velocity.y * 65000.0, 0.0, mass * 9.81)
    state.apply_force(force, point - state.transform.origin)
