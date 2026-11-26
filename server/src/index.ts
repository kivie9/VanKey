import { D1Store } from './d1_store.ts';
import type { D1Like } from './d1_store.ts';
import { createHandler } from './handler.ts';

interface Env {
  DB: D1Like;
  /** Biến thường: số tài khoản tối đa (mặc định 200). */
  MAX_USERS?: string;
  /** Bí mật (`wrangler secret put TOKEN_SECRET`). */
  TOKEN_SECRET: string;
  /** Bí mật tùy chọn (`wrangler secret put REGISTER_CODE`, từ 12 ký tự): đã đặt thì tạo tài khoản phải nhập mã mời này. */
  REGISTER_CODE?: string;
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (!env.TOKEN_SECRET || env.TOKEN_SECRET.length < 32) {
      return new Response(JSON.stringify({ error: 'misconfigured', message: 'TOKEN_SECRET chưa đặt hoặc quá ngắn (cần ≥ 32 ký tự)' }), {
        status: 500,
        headers: { 'content-type': 'application/json' },
      });
    }
    const handler = createHandler({
      store: new D1Store(env.DB),
      config: { tokenSecret: env.TOKEN_SECRET, registerCode: env.REGISTER_CODE, maxUsers: Number(env.MAX_USERS) || undefined },
    });
    return handler(req);
  },
};
