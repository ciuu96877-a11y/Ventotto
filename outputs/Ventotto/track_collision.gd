extends Node3D
## Static collision cells are shared by the crash body and the exterior camera.
const CELL := 64.0
var boxes := {}
var active := {}
var last_cell := Vector2i(999999, 999999)

func setup(line: Node3D) -> void:
    var ground := StaticBody3D.new()
    ground.collision_layer = 1
    var plane := WorldBoundaryShape3D.new()
    plane.plane = Plane(Vector3.UP, 0.035)
    var collision := CollisionShape3D.new()
    collision.shape = plane
    ground.add_child(collision)
    add_child(ground)
    for transform: Transform3D in line.collision_boxes:
        var key := cell_at(transform.origin)
        if not boxes.has(key): boxes[key] = []
        boxes[key].append(transform)

func cell_at(point: Vector3) -> Vector2i:
    return Vector2i(floori(point.x / CELL), floori(point.z / CELL))

func update_near(point: Vector3) -> void:
    var center := cell_at(point)
    if center == last_cell: return
    last_cell = center
    for key in active.keys():
        if abs(key.x - center.x) > 2 or abs(key.y - center.y) > 2:
            active[key].queue_free()
            active.erase(key)
    for x in range(center.x - 2, center.x + 3):
        for z in range(center.y - 2, center.y + 3):
            var key := Vector2i(x, z)
            if active.has(key) or not boxes.has(key): continue
            var body := StaticBody3D.new()
            body.collision_layer = 1
            body.position = Vector3(x * CELL, 0, z * CELL)
            add_child(body)
            for transform: Transform3D in boxes[key]:
                var shape := BoxShape3D.new()
                shape.size = transform.basis.get_scale()
                var collider := CollisionShape3D.new()
                collider.shape = shape
                body.add_child(collider)
                collider.global_transform = Transform3D(transform.basis.orthonormalized(), transform.origin)
            active[key] = body
