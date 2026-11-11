shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, world_vertex_coords;
uniform float weather_time = 0.0;
uniform float intensity = 0.0;
uniform vec3 origin = vec3(0.0);
uniform mat4 tram_inverse;
varying float sheltered;
void vertex() {
    vec3 seed = INSTANCE_CUSTOM.xyz;
    vec3 wind = vec3(1.45,-10.0,0.65);
    vec3 p = mod(seed*vec3(54.0,14.0,54.0)+wind*weather_time,vec3(54.0,14.0,54.0));
    p += origin + vec3(-27.0,0.06,-27.0);
    vec3 local = (tram_inverse*vec4(p,1.0)).xyz;
    sheltered = step(abs(local.x),1.27)*step(abs(local.z),7.10)*step(local.y,3.23);
    vec3 axis = normalize(wind);
    vec3 right = normalize(cross(axis,normalize(INV_VIEW_MATRIX[3].xyz-p)));
    VERTEX = p + right*VERTEX.x + axis*VERTEX.y*(0.65+seed.x);
}
void fragment() {
    float line = pow(max(0.0,1.0-abs(UV.x*2.0-1.0)),1.8);
    float ends = sin(UV.y*3.14159);
    ALBEDO = vec3(0.56,0.65,0.73);
    ALPHA = line*ends*0.58*intensity*(1.0-sheltered);
}
