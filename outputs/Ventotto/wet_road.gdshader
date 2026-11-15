shader_type spatial;
// Road and paving in the rain: a damp sheen everywhere, and puddles that collect in the
// low spots, grow while it rains and mirror the sky.
uniform sampler2D road_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(.32,.33,.33,1.0);
uniform float wetness = 0.0; // Damp surface, 0..1.
uniform float puddles = 0.0; // Standing water level, 0..1.
uniform float rain = 0.0; // Falling now: drives the ripples.
uniform float weather_time = 0.0;
varying vec3 world_position;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
    vec2 p=world_position.xz;
    // The ground is not flat: broad dips with smaller unevenness on top.
    float height=noise(p*.19)*.58+noise(p*.47+17.3)*.30+noise(p*1.7+4.1)*.12;
    float fill=puddles*.47;
    float water=1.0-smoothstep(fill-.03,fill+.012,height);
    float rim=(1.0-smoothstep(fill,fill+.13,height))*puddles;
    float damp=max(wetness,rim);
    vec3 road=texture(road_texture,p*.48).rgb*tint.rgb;
    ALBEDO=road*mix(1.0,.60,damp)*mix(1.0,.42,water);
    ROUGHNESS=mix(mix(.89,.46,damp),.035,water);
    SPECULAR=mix(mix(.35,.5,damp),.75,water);
    // Raindrops: sparse short-lived rings on the water, filtered at distance.
    vec2 cell=floor(p*1.8);
    float seed=hash(cell);
    vec2 center=vec2(hash(cell+vec2(3.1,9.4)),hash(cell+vec2(8.7,1.2)))*.5+.25;
    vec2 offset=(fract(p*1.8)-center)/1.8;
    float radius=length(offset);
    float age=fract(weather_time*1.1+seed*6.0);
    float width=max(.016,fwidth(radius)*1.5);
    float ring=exp(-pow((radius-age*.23)/width,2.0));
    float fade=(1.0-age)*smoothstep(.0,.12,age)*step(.5,seed);
    vec2 ripple=offset/max(radius,.001)*ring*fade*.03*water*rain;
    NORMAL_MAP=normalize(vec3(ripple,1.0))*.5+.5;
}
