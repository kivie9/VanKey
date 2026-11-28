import { base32Decode, secondsLeft, totp } from './totp';

// Chu vi của vòng tròn r = 6 trong SVG viewBox 24x24 (xem TotpDemo.astro).
const CIRCUMFERENCE = 2 * Math.PI * 6;

export function startTotpDemo(root: HTMLElement) {
  const codeEl = root.querySelector<HTMLElement>('[data-code]');
  const statusEl = root.querySelector<HTMLElement>('[data-status]');
  const noteEl = root.querySelector<HTMLElement>('[data-note]');
  const fillEl = root.querySelector<SVGCircleElement>('[data-fill]');
  if (!codeEl || !statusEl || !noteEl || !fillEl) return;

  // Bỏ dòng "cần bật JavaScript" khi JS đã chạy.
  noteEl.textContent = '';

  // Web Crypto chỉ có trong ngữ cảnh an toàn (HTTPS hoặc localhost).
  if (!globalThis.crypto?.subtle) {
    noteEl.textContent = root.dataset.unsupported ?? '';
    return;
  }

  const secret = base32Decode(root.dataset.secret ?? '');
  const label = root.dataset.remaining ?? '{s}';
  let step = -1;

  async function render() {
    const now = Date.now() / 1000;
    const left = secondsLeft(now);
    // Vòng đếm còn lại như trong app; dưới 6 giây thì đổi màu cảnh báo.
    fillEl!.style.strokeDasharray = `${(left / 30) * CIRCUMFERENCE} ${CIRCUMFERENCE}`;
    root.classList.toggle('is-urgent', left <= 5);
    statusEl!.textContent = label.replace('{s}', String(left));
    const current = Math.floor(now / 30);
    if (current !== step) {
      step = current;
      const code = await totp(secret, now);
      codeEl!.textContent = `${code.slice(0, 3)} ${code.slice(3)}`;
    }
  }

  // Hẹn đúng đầu mỗi giây để đồng hồ không trôi.
  async function loop() {
    await render();
    setTimeout(loop, 1000 - (Date.now() % 1000) + 10);
  }
  void loop();
}
