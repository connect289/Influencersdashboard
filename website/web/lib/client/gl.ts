/**
 * Minimal WebGL runner for full-surface fragment shaders (spec 10.4: no Three.js-scale library; < 30 KB gz budget for
 * hero shader + Witty orb together). One full-screen triangle, a handful of uniforms, frame-rate cap, resolution
 * scale, pause when off-screen or the tab is hidden, and a single static frame for reduced motion.
 */

export type Uniforms = Record<string, number | [number, number] | [number, number, number]>;

export interface ShaderRunnerOptions {
  canvas: HTMLCanvasElement;
  fragment: string;
  /** Fraction of device pixels to render (0.35–1). */
  resolution?: number;
  /** Frames per second cap. */
  fps?: number;
  /** Render a single frame and stop (reduced motion / low tier). */
  still?: boolean;
  /** Called every frame to supply dynamic uniforms. */
  uniforms?: (t: number) => Uniforms;
}

const VERTEX = `attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}`;

function compile(gl: WebGLRenderingContext, type: number, src: string): WebGLShader | null {
  const s = gl.createShader(type);
  if (!s) return null;
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    console.warn("shader compile failed", gl.getShaderInfoLog(s));
    gl.deleteShader(s);
    return null;
  }
  return s;
}

export function runShader(opts: ShaderRunnerOptions): () => void {
  const { canvas, fragment } = opts;
  const gl = canvas.getContext("webgl", {
    antialias: false,
    alpha: true,
    premultipliedAlpha: true,
    powerPreference: "low-power",
  });
  if (!gl) return () => {};
  const vs = compile(gl, gl.VERTEX_SHADER, VERTEX);
  const fs = compile(
    gl,
    gl.FRAGMENT_SHADER,
    `precision mediump float;uniform vec2 u_res;uniform float u_time;${fragment}`,
  );
  if (!vs || !fs) return () => {};
  const prog = gl.createProgram();
  if (!prog) return () => {};
  gl.attachShader(prog, vs);
  gl.attachShader(prog, fs);
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return () => {};
  gl.useProgram(prog);

  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(prog, "p");
  gl.enableVertexAttribArray(loc);
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

  const cache = new Map<string, WebGLUniformLocation | null>();
  const uni = (name: string) => {
    if (!cache.has(name)) cache.set(name, gl.getUniformLocation(prog, name));
    return cache.get(name) ?? null;
  };
  const set = (name: string, v: Uniforms[string]) => {
    const l = uni(name);
    if (!l) return;
    if (typeof v === "number") gl.uniform1f(l, v);
    else if (v.length === 2) gl.uniform2f(l, v[0], v[1]);
    else gl.uniform3f(l, v[0], v[1], v[2]);
  };

  const scale = Math.min(1, Math.max(0.35, opts.resolution ?? 0.6));
  const frameMs = 1000 / (opts.fps ?? 30);
  let raf = 0;
  let last = 0;
  let visible = true;
  let running = false;
  const start = performance.now();

  const resize = () => {
    const dpr = Math.min(window.devicePixelRatio || 1, 2) * scale;
    const w = Math.max(1, Math.round(canvas.clientWidth * dpr));
    const h = Math.max(1, Math.round(canvas.clientHeight * dpr));
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
      gl.viewport(0, 0, w, h);
    }
  };

  const draw = (now: number) => {
    resize();
    const t = (now - start) / 1000;
    set("u_res", [canvas.width, canvas.height]);
    set("u_time", t);
    const extra = opts.uniforms?.(t);
    if (extra) for (const k in extra) set(k, extra[k] as Uniforms[string]);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  };

  const loop = (now: number) => {
    raf = requestAnimationFrame(loop);
    if (now - last < frameMs) return;
    last = now;
    draw(now);
  };

  const play = () => {
    if (running || opts.still) return;
    running = true;
    raf = requestAnimationFrame(loop);
  };
  const pause = () => {
    running = false;
    cancelAnimationFrame(raf);
  };

  const io = new IntersectionObserver(([e]) => {
    visible = !!e?.isIntersecting;
    if (visible && !document.hidden) play();
    else pause();
  });
  io.observe(canvas);
  const onVis = () => (document.hidden || !visible ? pause() : play());
  document.addEventListener("visibilitychange", onVis);
  const ro = new ResizeObserver(() => opts.still && draw(performance.now()));
  ro.observe(canvas);
  const onLost = (e: Event) => {
    e.preventDefault();
    pause();
  };
  canvas.addEventListener("webglcontextlost", onLost);

  draw(performance.now() + 12000); // a pleasant first frame (also the reduced-motion still)
  canvas.dataset.ready = "1";
  play();

  return () => {
    pause();
    io.disconnect();
    ro.disconnect();
    document.removeEventListener("visibilitychange", onVis);
    canvas.removeEventListener("webglcontextlost", onLost);
    gl.getExtension("WEBGL_lose_context")?.loseContext();
  };
}

/** Parse a CSS colour token (#rrggbb) into 0–1 RGB for shader uniforms. */
export function cssColor(el: Element, name: string, fallback: [number, number, number]): [number, number, number] {
  const v = getComputedStyle(el).getPropertyValue(name).trim();
  const m = /^#([0-9a-f]{6})$/i.exec(v);
  if (!m || !m[1]) return fallback;
  const n = parseInt(m[1], 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}
