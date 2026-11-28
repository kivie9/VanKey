// Chuyển động theo cuộn. Chỉ đổi transform/opacity. HTML gốc đã ở trạng thái cuối,
// nên không có JS hoặc bật giảm chuyển động thì mọi nội dung vẫn đọc được.
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

const GLYPHS = '0123456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ+/';

/** Chuỗi đầu vào xáo ký tự rồi dừng dần thành kết quả, từ trái sang phải. */
function scramble(el: HTMLElement) {
  const from = [...(el.dataset.from ?? '')];
  const to = [...(el.dataset.to ?? '')];
  const state = { p: 0 };
  return gsap.to(state, {
    p: 1,
    duration: 0.9,
    ease: 'none',
    onUpdate: () => {
      const length = Math.round(from.length + (to.length - from.length) * state.p);
      const settled = Math.floor(to.length * state.p);
      let text = '';
      for (let i = 0; i < length; i++) {
        if (i < settled) text += to[i] ?? '';
        else if (to[i] === ' ') text += ' ';
        else text += GLYPHS[Math.floor(Math.random() * GLYPHS.length)];
      }
      el.textContent = text;
    },
    onComplete: () => {
      el.textContent = el.dataset.to ?? '';
    },
  });
}

export function initScroll() {
  const media = gsap.matchMedia();

  media.add('(prefers-reduced-motion: no-preference)', () => {
    // Hiện dần: chỉ giấu những khối còn nằm dưới màn hình để không bị nháy.
    for (const el of document.querySelectorAll<HTMLElement>('[data-reveal]')) {
      if (el.getBoundingClientRect().top < window.innerHeight) continue;
      gsap.set(el, { opacity: 0, y: 16 });
      ScrollTrigger.create({
        trigger: el,
        start: 'top 92%',
        once: true,
        onEnter: () => void gsap.to(el, { opacity: 1, y: 0, duration: 0.6, ease: 'power2.out', clearProps: 'transform' }),
      });
    }

    const flow = document.querySelector<HTMLElement>('[data-flow]');
    if (!flow) return;

    const fill = flow.querySelector('[data-flow-fill]');
    if (fill) {
      gsap.fromTo(
        fill,
        { scaleY: 0 },
        { scaleY: 1, ease: 'none', scrollTrigger: { trigger: flow, start: 'top 65%', end: 'bottom 65%', scrub: true } },
      );
    }

    const steps = [...flow.querySelectorAll<HTMLElement>('[data-flow-step]')];
    for (const step of steps) {
      if (step.getBoundingClientRect().top < window.innerHeight * 0.7) continue;
      step.classList.add('is-waiting');
      ScrollTrigger.create({
        trigger: step,
        start: 'top 70%',
        once: true,
        onEnter: () => {
          step.classList.remove('is-waiting');
          const target = step.querySelector<HTMLElement>('[data-scramble]');
          if (target) scramble(target);
        },
      });
    }

    // Người xem bật giảm chuyển động giữa chừng: trả mọi thứ về trạng thái cuối.
    return () => {
      for (const step of steps) {
        step.classList.remove('is-waiting');
        const target = step.querySelector<HTMLElement>('[data-scramble]');
        if (target) target.textContent = target.dataset.to ?? '';
      }
    };
  });

  // Phông tải muộn làm lệch vị trí các mốc cuộn. Đã tải xong thì không cần đo lại.
  if (document.fonts.status !== 'loaded') void document.fonts.ready.then(() => ScrollTrigger.refresh());
}
