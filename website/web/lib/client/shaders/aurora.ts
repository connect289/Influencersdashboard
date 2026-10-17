import { NOISE } from "./common";

/**
 * Concept A hero atmosphere: a living aurora. Domain-warped fbm drives two light ribbons; the pointer adds a soft glow;
 * u_energy (Witty's activity) brightens the ribbons; u_scroll drifts them. u_dark blends additive light (dark theme) and
 * pastel mixing (light theme).
 */
export const AURORA_FRAG = `uniform vec3 u_c1,u_c2,u_c3,u_base;uniform vec2 u_pointer;uniform float u_scroll,u_energy,u_dark;${NOISE}
void main(){vec2 uv=gl_FragCoord.xy/u_res;vec2 p=uv;p.x*=u_res.x/u_res.y;float t=u_time*.045;
vec2 q=vec2(fbm(p*1.3+vec2(0.,t)),fbm(p*1.3+vec2(5.2,-t)));
vec2 r=vec2(fbm(p*1.7+q*1.8+vec2(1.7,9.2)+t*.6),fbm(p*1.7+q*1.8+vec2(8.3,2.8)-t*.4));
float f=fbm(p*1.2+r*1.6);
float b1=smoothstep(.16,0.,abs(uv.y-.64-(f-.5)*.6-u_scroll*.18));
float b2=smoothstep(.13,0.,abs(uv.y-.36-(r.x-.5)*.55+u_scroll*.1));
vec2 d=uv-u_pointer;float g=exp(-dot(d,d)*7.)*(.25+u_energy*.6);
vec3 c=mix(u_base,u_c3,smoothstep(.25,.95,f)*.6);
c=lay(c,u_c2,b2*(.32+.2*u_dark),u_dark);
c=lay(c,u_c1,b1*(.42+.3*u_energy),u_dark);
c=lay(c,u_c1,g*.3,u_dark);
float v=smoothstep(1.3,.25,length((uv-.5)*vec2(1.15,1.)));
gl_FragColor=vec4(mix(u_base,c,v),1.);}`;
