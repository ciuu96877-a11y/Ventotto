shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, world_vertex_coords;
uniform float weather_time = 0.0;
uniform float intensity = 0.0;
uniform vec3 origin;
uniform mat4 tram_inverse;
varying float age;
varying float visible_splash;
void vertex() {
    age = fract(weather_time*1.65+INSTANCE_CUSTOM.w);
    vec3 p=origin+vec3((INSTANCE_CUSTOM.x-.5)*38.0,0.044,(INSTANCE_CUSTOM.z-.5)*38.0);
    vec3 local=(tram_inverse*vec4(p,1.0)).xyz;
    visible_splash=1.0-step(abs(local.x),1.35)*step(abs(local.z),7.15);
    VERTEX=p+vec3(VERTEX.x,0.0,VERTEX.y)*(0.35+age*1.6);
}
void fragment() {
    float r=length(UV-vec2(.5));
    float ring=smoothstep(.028,0.0,abs(r-.37));
    ALBEDO=vec3(.51,.62,.68);
    ALPHA=ring*(1.0-age)*.30*intensity*visible_splash;
}
