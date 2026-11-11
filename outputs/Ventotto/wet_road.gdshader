shader_type spatial;
uniform sampler2D road_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(.32,.33,.33,1.0);
uniform float wetness = 0.0;
uniform float weather_time = 0.0;
varying vec3 world_position;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
    vec2 p=world_position.xz;
    float pools=smoothstep(.48,.68,noise(p*.31)*.7+noise(p*.82)*.3)*wetness;
    vec3 road=texture(road_texture,p*.48).rgb*tint.rgb;
    ALBEDO=road*mix(1.0,.59,wetness)*mix(1.0,.71,pools);
    ROUGHNESS=mix(.89,.43,wetness)*(1.0-pools)+pools*.23;
    SPECULAR=mix(.35,.5,wetness);
    // Sparse short-lived rings, filtered at distance instead of repeating waves.
    vec2 cell=floor(p*1.8);
    float seed=hash(cell);
    vec2 center=vec2(hash(cell+vec2(3.1,9.4)),hash(cell+vec2(8.7,1.2)))*.5+.25;
    vec2 offset=(fract(p*1.8)-center)/1.8;
    float radius=length(offset);
    float age=fract(weather_time*1.1+seed*6.0);
    float width=max(.016,fwidth(radius)*1.5);
    float ring=exp(-pow((radius-age*.23)/width,2.0));
    float fade=(1.0-age)*smoothstep(.0,.12,age)*step(.58,seed);
    vec2 ripple=offset/max(radius,.001)*ring*fade*.009*pools;
    NORMAL_MAP=normalize(vec3(ripple,1.0))*.5+.5;
}
