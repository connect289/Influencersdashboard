import { NOISE } from "./common";

/**
 * Concept B atmosphere: daylight through a prism. Slow diagonal light beams with a slight chromatic split, a pointer
 * highlight, and calm drift. Designed light-first; works on the dark theme through u_dark.
 */
export const PRISM_FRAG = `uniform vec3 u_c1,u_c2,u_c3,u_base;uniform vec2 u_pointer;uniform float u_scroll,u_energy,u_dark;${NOISE}
void main(){vec2 uv=gl_FragCoord.xy/u_res;float t=u_time*.05;float w=fbm(uv*2.+t)*.25;
float a=uv.x*.82+uv.y*.58+w-u_scroll*.15;
float b1=pow(.5+.5*sin(a*8.8-t*2.),9.);float b2=pow(.5+.5*sin(a*5.6+t*1.4+1.3),11.);
vec3 disp=vec3(pow(.5+.5*sin((a+.014)*8.8-t*2.),9.),b1,pow(.5+.5*sin((a-.014)*8.8-t*2.),9.));
vec2 d=uv-u_pointer;float g=exp(-dot(d,d)*5.);
vec3 c=u_base;c=lay(c,u_c1,b1*.34,u_dark);c=lay(c,u_c2,b2*.28,u_dark);c+=(disp-vec3(b1))*.09;
c=lay(c,u_c3,g*.22*(1.+u_energy),u_dark);
float v=smoothstep(1.45,.2,length(uv-vec2(.72,.62)));
gl_FragColor=vec4(mix(u_base,c,v),1.);}`;
