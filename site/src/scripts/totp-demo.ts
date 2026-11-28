import { base32Decode, secondsLeft, totp } from './totp';

export function startTotpDemo(root: HTMLElement) {
  const codeEl = root.querySelector<HTMLElement>('[data-code]');
  const statusEl = root.querySelector<HTMLElement>('[data-status]');
  const ticks = [...root.querySelectorAll('[data-tick]')];
  if (!codeEl || !statusEl) return;

  // Web Crypto chỉ có trong ngữ cảnh an toàn (HTTPS hoặc localhost).
  if (!globalThis.crypto?.subtle) {
    statusEl.textContent = root.dataset.unsupported ?? '';
    return;
  }

  const secret = base32Decode(root.dataset.secret ?? '');
  const label = root.dataset.remaining ?? '{s}';
  let step = -1;

  async function render() {
    const now = Date.now() / 1000;
    const left = secondsLeft(now);
    statusEl!.textContent = label.replace('{s}', String(left));
    ticks.forEach((tick, i) => tick.classList.toggle('spent', i < 30 - left));
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
