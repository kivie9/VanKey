// Điểm vào duy nhất. Phần nặng (GSAP, Three.js) tải muộn, sau khi trang đã hiện.
import { startTotpDemo } from './totp-demo';

const motion = window.matchMedia('(prefers-reduced-motion: no-preference)');

const totpRoot = document.querySelector<HTMLElement>('[data-totp]');
if (totpRoot) startTotpDemo(totpRoot);

function whenIdle(run: () => void) {
  const schedule = () =>
    'requestIdleCallback' in window ? requestIdleCallback(run, { timeout: 1500 }) : setTimeout(run, 200);
  if (document.readyState === 'complete') schedule();
  else window.addEventListener('load', schedule, { once: true });
}

let started = false;
function startMotion() {
  if (started || !motion.matches) return;
  started = true;

  whenIdle(() => {
    void import('./scroll').then((m) => m.initScroll());

    const hero = document.querySelector<HTMLElement>('[data-hero]');
    if (!hero) return;
    // Giữ ảnh tĩnh nếu không dựng được cảnh 3D (không có WebGL, tải lỗi...).
    const fail = () => hero.classList.add('is-static');

    const observer = new IntersectionObserver((entries) => {
      if (!entries.some((e) => e.isIntersecting)) return;
      observer.disconnect();
      import('./hero-scene').then((m) => m.initHero(hero)).catch(fail);
    });
    observer.observe(hero);
  });
}

startMotion();
motion.addEventListener('change', startMotion);
