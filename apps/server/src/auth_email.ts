import { Buffer } from 'node:buffer';

export function emailDeliveryReady(env) {
  return Boolean(env.SENDPULSE_API_KEY || env.WAYBI_RESEND_API_KEY) &&
    typeof env.AUTH_EMAIL_FROM === 'string' && /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(env.AUTH_EMAIL_FROM);
}

async function reserveBudget(db, provider: string, now: number) {
  // Persist across Worker instances. Count uncertain/failed submissions conservatively.
  const hourly = provider === 'sendpulse' ? 50 : 100;
  const daily = provider === 'sendpulse' ? 400 : 100;
  return db.prepare(`INSERT INTO auth_email_budgets VALUES (?, ?, 1, ?, 1)
    ON CONFLICT(provider) DO UPDATE SET
      hour_count = CASE WHEN ? - hour_start >= 3600000 THEN 1 ELSE hour_count + 1 END,
      hour_start = CASE WHEN ? - hour_start >= 3600000 THEN ? ELSE hour_start END,
      day_count = CASE WHEN ? - day_start >= 86400000 THEN 1 ELSE day_count + 1 END,
      day_start = CASE WHEN ? - day_start >= 86400000 THEN ? ELSE day_start END
    WHERE (? - hour_start >= 3600000 OR hour_count < ?)
      AND (? - day_start >= 86400000 OR day_count < ?)
    RETURNING provider`).bind(provider, now, now, now, now, now, now, now, now, now, hourly, now, daily).first();
}

export async function sendSignInEmail(db, env, recipient: string, code: string, language: string) {
  const zh = language === 'zh';
  const subject = zh ? `${code} 是你的 Waybi 验证码` : `${code} is your Waybi sign-in code`;
  const text = zh
    ? `你的 Waybi 验证码是 ${code}。\n\n10 分钟内有效，只能使用一次。请勿将验证码告诉他人。\n如果你没有请求登录，请忽略这封邮件。`
    : `Your Waybi sign-in code is ${code}.\n\nIt expires in 10 minutes and can only be used once. Never share this code.\nIf you did not request it, you can ignore this email.`;
  const html = `<div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;padding:32px;color:#123c4a"><h1>Waybi</h1><p>${zh ? '登录或创建你的账号' : 'Sign in or create your account'}</p><p style="font-size:36px;font-weight:700;letter-spacing:8px">${code}</p><p>${zh ? '验证码 10 分钟内有效，请勿向他人透露。' : 'Valid for 10 minutes. Never share your code.'}</p><p style="color:#68777b;font-size:12px">${zh ? '如果不是你本人操作，请忽略此邮件。' : 'If you did not request this, you can ignore this email.'}</p></div>`;
  for (const provider of ['sendpulse', 'resend']) {
    const apiKey = provider === 'sendpulse' ? env.SENDPULSE_API_KEY : env.WAYBI_RESEND_API_KEY;
    if (!apiKey || !await reserveBudget(db, provider, Date.now())) continue;
    const pulse = provider === 'sendpulse';
    const body = pulse ? { email: { subject, text, html: Buffer.from(html).toString('base64'),
      from: { name: 'Waybi', email: env.AUTH_EMAIL_FROM }, to: [{ email: recipient }] } }
      : { from: `Waybi <${env.AUTH_EMAIL_FROM}>`, to: [recipient], subject, text, html };
    const result = await fetch(pulse ? 'https://api.sendpulse.com/smtp/emails' : 'https://api.resend.com/emails', {
      method: 'POST', headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify(body), signal: AbortSignal.timeout(4_000),
    });
    // A quota rejection is explicit non-acceptance. Never fail over after a timeout
    // or 5xx: the provider may already have accepted this same message.
    if (result.status === 429) continue;
    if (pulse && result.status === 422) {
      // SendPulse's SMTP schema distinguishes quota rejection from other 422s.
      const rejection = await result.json().catch(() => null) as {message?: string; error_code?: number} | null;
      if (rejection?.error_code === 422 && rejection.message === 'Sending quota or bandwidth exceeded') continue;
      throw new Error('Email delivery unavailable');
    }
    if (!result.ok) throw new Error('Email delivery unavailable');
    const receipt = await result.json() as { result?: boolean; id?: string };
    if (typeof receipt.id !== 'string' || !receipt.id || (pulse && receipt.result !== true)) throw new Error('Email delivery unavailable');
    return true;
  }
  return false;
}
