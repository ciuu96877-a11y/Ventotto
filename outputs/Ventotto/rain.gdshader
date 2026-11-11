shader_type canvas_item;
render_mode unshaded;

uniform float clear_windscreen = 0.0;

float noise(float p) { return fract(sin(p*73.21)*43758.5453); }

void fragment() {
    vec2 uv = UV;
    float drops = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float rate = float(layer);
        vec2 p = vec2((uv.x + uv.y*.17)*134.0,uv.y*11.0-TIME*(12.0+rate*5.0));
        p.x += rate*.57;
        float column = floor(p.x);
        p.y += noise(column+rate*70.0)*17.0;
        float line = 1.0-smoothstep(.035,.14,abs(fract(p.x)-.5));
        float trail = smoothstep(.68,.98,fract(p.y));
        drops += line*trail*noise(column+floor(p.y)*41.0)*(.23-rate*.055);
    }
    vec2 g = uv*vec2(49.0,31.0);
    vec2 id = floor(g);
    float seed = noise(id.x*13.0+id.y*37.0);
    vec2 f = fract(g)-vec2(.42+.23*seed,.46);
    float bead = 1.0-smoothstep(.075,.136,length(f*vec2(1.35,.64)));
    float windscreen = smoothstep(.06,.19,uv.y)*(1.0-smoothstep(.49,.56,uv.y));
    float droplets = bead*step(.91,seed)*.21*windscreen*(1.0-clear_windscreen*.88);
    float frame = smoothstep(.16,.24,uv.x)*(1.0-smoothstep(.76,.86,uv.x));
    COLOR = vec4(.79,.87,.94,clamp((drops+droplets)*windscreen*frame,0.0,.45));
}


