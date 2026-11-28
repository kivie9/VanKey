// Hero: đám ký tự lộn xộn (bản mã) ráp lại thành logo VanKey khi cuộn.
import {
  BufferAttribute,
  BufferGeometry,
  CanvasTexture,
  Color,
  Group,
  LinearFilter,
  PerspectiveCamera,
  Points,
  Scene,
  ShaderMaterial,
  WebGLRenderer,
} from 'three';
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import points from '../data/hero-points.json';

gsap.registerPlugin(ScrollTrigger);

const CHARS = '0123456789ABCDEF+/=xkQz';
const GRID = 5; // atlas 5x5 ô
const CELL = 64;
const FOV = 35;
const DISTANCE = 4.2;

async function glyphAtlas() {
  const font = `600 ${CELL * 0.8}px 'Geist Mono Variable', monospace`;
  await document.fonts.load(font, CHARS).catch(() => []);
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = GRID * CELL;
  const ctx = canvas.getContext('2d')!;
  ctx.font = font;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = '#fff';
  for (let i = 0; i < GRID * GRID; i++) {
    ctx.fillText(CHARS[i % CHARS.length]!, (i % GRID) * CELL + CELL / 2, Math.floor(i / GRID) * CELL + CELL / 2);
  }
  const texture = new CanvasTexture(canvas);
  texture.flipY = false;
  texture.generateMipmaps = false;
  texture.minFilter = LinearFilter;
  return texture;
}

const vertexShader = /* glsl */ `
  attribute vec3 aScatter;
  attribute vec2 aSeed;
  uniform float uProgress;
  uniform float uTime;
  uniform float uSize;
  uniform float uScale;
  varying float vAlpha;
  varying float vGlyph;
  varying vec2 vScreen;

  void main() {
    // Mỗi hạt khởi hành lệch nhau một chút.
    float t = clamp((uProgress - aSeed.x * 0.35) / 0.65, 0.0, 1.0);
    t = t * t * (3.0 - 2.0 * t);

    vec3 drift = vec3(
      sin(uTime * 0.35 + aSeed.x * 40.0),
      cos(uTime * 0.28 + aSeed.y * 40.0),
      sin(uTime * 0.22 + aSeed.y * 20.0)
    ) * 0.05;
    vec3 target = vec3(position.xy * uScale, 0.0);
    vec3 p = mix(aScatter + drift, target, t);

    vec4 mv = modelViewMatrix * vec4(p, 1.0);
    gl_Position = projectionMatrix * mv;
    gl_PointSize = uSize * mix(1.15 + aSeed.y * 0.7, 1.0, t) * (${DISTANCE.toFixed(1)} / -mv.z);

    vScreen = gl_Position.xy / gl_Position.w;
    vAlpha = mix(0.16 + aSeed.y * 0.42, 0.78 + aSeed.y * 0.22, t);
    // Khi còn lộn xộn thì ký tự đổi liên tục, ráp xong thì đứng yên.
    float tick = floor(uTime * (1.0 + aSeed.x * 3.0)) * (1.0 - step(0.98, t));
    vGlyph = mod(floor(aSeed.y * 997.0) + tick, ${(GRID * GRID).toFixed(1)});
  }
`;

const fragmentShader = /* glsl */ `
  precision mediump float;
  uniform sampler2D uAtlas;
  uniform vec3 uColor;
  varying float vAlpha;
  varying float vGlyph;
  varying vec2 vScreen;

  void main() {
    vec2 cell = vec2(mod(vGlyph, ${GRID.toFixed(1)}), floor((vGlyph + 0.5) / ${GRID.toFixed(1)}));
    float ink = texture2D(uAtlas, (cell + gl_PointCoord) / ${GRID.toFixed(1)}).a;
    // Mờ dần vào nền ở mép khung.
    float edge = (1.0 - smoothstep(0.72, 1.0, abs(vScreen.x))) * (1.0 - smoothstep(0.72, 1.0, abs(vScreen.y)));
    float alpha = ink * vAlpha * edge;
    if (alpha < 0.02) discard;
    gl_FragColor = vec4(uColor, alpha);
  }
`;

export async function initHero(hero: HTMLElement) {
  const host = hero.querySelector<HTMLElement>('[data-hero-visual]');
  if (!host) return;

  const small = window.matchMedia('(max-width: 899px)').matches;
  const total = points.length / 2;
  const count = small ? Math.min(2400, total) : total;

  const atlas = await glyphAtlas();
  const renderer = new WebGLRenderer({ alpha: true, antialias: false, powerPreference: 'low-power' });
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  renderer.setPixelRatio(ratio);

  const position = new Float32Array(count * 3);
  const scatter = new Float32Array(count * 3);
  const seed = new Float32Array(count * 2);
  for (let i = 0; i < count; i++) {
    position[i * 3] = points[i * 2]! / 1000;
    position[i * 3 + 1] = points[i * 2 + 1]! / 1000;
    seed[i * 2] = Math.random();
    seed[i * 2 + 1] = Math.random();
  }
  const geometry = new BufferGeometry();
  geometry.setAttribute('position', new BufferAttribute(position, 3));
  geometry.setAttribute('aScatter', new BufferAttribute(scatter, 3));
  geometry.setAttribute('aSeed', new BufferAttribute(seed, 2));

  const uniforms = {
    uProgress: { value: 0 },
    uTime: { value: 0 },
    uSize: { value: 8 },
    uScale: { value: 1 },
    uColor: { value: new Color() },
    uAtlas: { value: atlas },
  };
  const material = new ShaderMaterial({ uniforms, vertexShader, fragmentShader, transparent: true, depthWrite: false });

  const cloud = new Points(geometry, material);
  cloud.frustumCulled = false;
  const group = new Group();
  group.add(cloud);
  const scene = new Scene();
  scene.add(group);
  const camera = new PerspectiveCamera(FOV, 1, 0.1, 20);
  camera.position.z = DISTANCE;

  const halfHeight = Math.tan((FOV * Math.PI) / 360) * DISTANCE;
  // Vị trí lộn xộn trải theo hình dạng khung, giữ cố định tỉ lệ ngẫu nhiên khi đổi kích thước.
  const spread = Float32Array.from({ length: count * 3 }, () => Math.random() * 2 - 1);

  function resize() {
    const width = host!.clientWidth;
    const height = host!.clientHeight;
    if (!width || !height) return;
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();

    const halfWidth = halfHeight * camera.aspect;
    for (let i = 0; i < count; i++) {
      scatter[i * 3] = spread[i * 3]! * halfWidth * 0.98;
      scatter[i * 3 + 1] = spread[i * 3 + 1]! * halfHeight * 0.98;
      scatter[i * 3 + 2] = spread[i * 3 + 2]! * 0.8;
    }
    geometry.getAttribute('aScatter').needsUpdate = true;

    // Logo cao 2 đơn vị (-1..1), rộng khoảng 1.56. Thu nhỏ cho vừa khung.
    const scale = Math.min((halfHeight * 0.82) / 1, (halfWidth * 0.82) / 0.78);
    uniforms.uScale.value = scale;
    const logoPixels = (scale / halfHeight) * height;
    uniforms.uSize.value = Math.max(3.5, (logoPixels / Math.sqrt(count)) * 1.45) * ratio;
  }

  const scheme = window.matchMedia('(prefers-color-scheme: dark)');
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  function recolor() {
    const accent = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim();
    uniforms.uColor.value.setStyle(accent, 'srgb-linear'); // shader ghi thẳng giá trị sRGB
  }

  resize();
  recolor();
  scheme.addEventListener('change', recolor);
  new ResizeObserver(resize).observe(host);

  // Tiến độ theo cuộn. Hero đứng yên (sticky) thì đo trên cả hero, nếu không thì đo lúc khung đi qua màn hình.
  let targetProgress = 0;
  const stage = hero.firstElementChild as HTMLElement;
  const pinned = () => getComputedStyle(stage).position === 'sticky';
  ScrollTrigger.create({
    trigger: hero,
    start: () => (pinned() ? 'top 64px' : 'top top'),
    end: () => (pinned() ? 'bottom bottom' : `+=${Math.max(240, host.offsetTop + host.offsetHeight * 0.35)}`),
    invalidateOnRefresh: true,
    onUpdate: (self) => {
      // Ráp xong ở 80% quãng cuộn, phần còn lại để người xem nhìn hình.
      targetProgress = Math.min(1, self.progress / 0.8);
    },
    onRefresh: (self) => {
      targetProgress = Math.min(1, self.progress / 0.8);
    },
  });

  const tilt = { x: 0, y: 0 };
  if (window.matchMedia('(pointer: fine)').matches) {
    window.addEventListener(
      'pointermove',
      (e) => {
        tilt.x = (e.clientY / window.innerHeight - 0.5) * 0.18;
        tilt.y = (e.clientX / window.innerWidth - 0.5) * 0.28;
      },
      { passive: true },
    );
  }

  let frame = 0;
  let last = 0;
  let onScreen = true;
  uniforms.uProgress.value = targetProgress;

  function render(now: number) {
    const delta = Math.min(0.05, (now - last) / 1000 || 0.016);
    last = now;
    const ease = 1 - Math.exp(-delta * 9);
    uniforms.uTime.value += delta;
    uniforms.uProgress.value += (targetProgress - uniforms.uProgress.value) * ease;
    group.rotation.x += (tilt.x - group.rotation.x) * ease * 0.5;
    group.rotation.y += (tilt.y - group.rotation.y) * ease * 0.5;
    renderer.render(scene, camera);
    frame = requestAnimationFrame(render);
  }

  // Dừng vẽ khi tab ẩn, hero ra khỏi màn hình, hoặc người xem bật giảm chuyển động.
  function sync() {
    const run = onScreen && !document.hidden && !motion.matches;
    if (run && !frame) {
      last = performance.now();
      frame = requestAnimationFrame(render);
    } else if (!run && frame) {
      cancelAnimationFrame(frame);
      frame = 0;
    }
    hero.classList.toggle('is-live', !motion.matches);
  }

  new IntersectionObserver((entries) => {
    onScreen = entries[entries.length - 1]!.isIntersecting;
    sync();
  }).observe(host);
  document.addEventListener('visibilitychange', sync);
  motion.addEventListener('change', sync);

  renderer.domElement.addEventListener('webglcontextlost', () => {
    cancelAnimationFrame(frame);
    frame = 0;
    onScreen = false;
    hero.classList.remove('is-live');
    hero.classList.add('is-static');
  });

  renderer.domElement.setAttribute('aria-hidden', 'true');
  host.append(renderer.domElement);
  // Biên dịch shader không chặn luồng chính (nếu trình duyệt hỗ trợ) rồi mới vẽ.
  await renderer.compileAsync(scene, camera);
  renderer.render(scene, camera);
  sync();
}
