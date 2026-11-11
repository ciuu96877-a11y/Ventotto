shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D scene_color : hint_screen_texture, filter_linear;
uniform sampler2D wiped_mask : filter_linear;
uniform float intensity = 0.0;
uniform float weather_time = 0.0;
uniform vec2 glass_size = vec2(0.8,0.8);
uniform bool wiped = false;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
vec3 droplet(vec2 uv, float scale) {
    vec2 grid=uv*glass_size*scale;
    vec2 cell=floor(grid);
    float seed=hash(cell);
    vec2 p=fract(grid)-vec2(.22+.56*seed,.25+.5*hash(cell+8.7));
    p.y += sin(weather_time*(.18+seed*.25)+seed*6.28)*.08;
    float r=length(p*vec2(1.0,1.2));
    float radius=.075+.11*seed;
    float mask=smoothstep(radius,radius*.65,r)*step(.32,seed);
    return vec3(p*mask,mask);
}
void fragment() {
    float water=intensity;
    if(wiped) water*=texture(wiped_mask,UV).r;
    vec3 small=droplet(UV,43.0);
    vec3 large=droplet(vec2(UV.x,UV.y-weather_time*.028),14.0);
    float drops=clamp(small.z*.65+large.z,0.0,1.0)*water;
    vec2 distortion=(small.xy*.007+large.xy*.022)*water;
    vec3 refracted=texture(scene_color,SCREEN_UV+distortion).rgb;
    ALBEDO=mix(vec3(.53,.65,.66),refracted,.65);
    EMISSION=refracted*drops*.38;
    ROUGHNESS=.055+water*.10;
    METALLIC=.0;
    SPECULAR=.85;
    NORMAL_MAP=normalize(vec3(-(small.xy+large.xy)*water*2.8,1.0))*.5+.5;
    ALPHA=.035+drops*.48;
}
