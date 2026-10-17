import { NOISE } from "./common";

/**
 * Witty's presence: a breathing sphere of moving light. u_energy rises while the student types (ripple rings) and while
 * Witty is thinking; u_pulse spikes on every streamed token. Output is premultiplied alpha (transparent around the orb).
 */
export const ORB_FRAG = `uniform vec3 u_c1,u_c2,u_c3;uniform float u_energy,u_pulse,u_dark;${NOISE}
void main(){vec2 uv=(gl_FragCoord.xy-.5*u_res)/min(u_res.x,u_res.y)*2.;float r=length(uv);
float R=.7+.025*sin(u_time*1.3)+.05*u_pulse+.035*u_energy;float e=smoothstep(R,R-.025,r);
vec2 p=uv*1.7;float t=u_time*.22*(1.+u_energy*2.2);float f=fbm(p+vec2(fbm(p+t),fbm(p-t*.7)));
vec3 c=mix(u_c2,u_c1,smoothstep(.28,.82,f+uv.y*.3));c=mix(c,u_c3,smoothstep(.55,.95,f)*.55);
float z=sqrt(max(0.,1.-pow(r/R,2.)));c*=.5+.65*z;c+=pow(z,10.)*.22;
c+=u_c1*smoothstep(R-.14,R,r)*e*.55;
float halo=exp(-max(0.,r-R)*8.)*(1.-e)*(.3+.45*u_energy+.6*u_pulse);
float ring=(.5+.5*sin(r*26.-u_time*7.))*(1.-e)*smoothstep(R+.4,R,r)*u_energy*.3;
vec3 o=c*e+u_c1*halo+u_c2*ring;gl_FragColor=vec4(o,clamp(e+halo+ring,0.,1.));}`;
