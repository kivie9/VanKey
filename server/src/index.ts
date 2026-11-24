import { D1Store } from './d1_store.ts';
import type { D1Like } from './d1_store.ts';
import { createHandler } from './handler.ts';

interface Env {
  DB: D1Like;
  /** Biến thường: email được phép, ngăn cách bằng dấu phẩy. */
  ALLOWED_EMAILS: string;
  /** Biến thường: Google OAuth client ID (tùy chọn). */
  GOOGLE_CLIENT_IDS?: string;
  /** Bí mật (`wrangler secret put TOKEN_SECRET`). */
  TOKEN_SECRET: string;
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
      config: { allowedEmails: env.ALLOWED_EMAILS ?? '', tokenSecret: env.TOKEN_SECRET, googleClientIds: env.GOOGLE_CLIENT_IDS },
    });
    return handler(req);
  },
};
