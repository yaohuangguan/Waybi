/**
 * The Waybi lockup as inline SVG, so the word mark can follow the light/dark
 * theme (including a theme forced in Settings, which an <img> cannot see).
 */
export function lockupSvg(label = 'Waybi', className = '', width = 171) {
  const height = Math.round(width * 84 / 268);
  return `<svg class="waybi-lockup ${className}" width="${width}" height="${height}" viewBox="0 0 268 84" role="img" aria-label="${label}"><circle cx="42" cy="42" r="39" fill="#d0f58a"/><ellipse cx="36" cy="49" rx="23" ry="18" fill="#29441f"/><circle cx="54" cy="30" r="14" fill="#29441f"/><path d="M64 29 82 36 64 36Z" fill="#e4a850"/><path d="m29 62-2 11h7m12-11-2 11h7" fill="none" stroke="#e4a850" stroke-width="3.5" stroke-linecap="round"/><circle cx="58" cy="26" r="4.5" fill="#fff"/><circle cx="59" cy="26" r="2" fill="#152510"/><ellipse cx="57" cy="34" rx="4" ry="2.5" fill="#edb7a3"/><ellipse cx="34" cy="46" rx="10" ry="6" fill="#729f36"/><text class="lockup-word" x="96" y="44" font-family="system-ui,sans-serif" font-size="36" font-weight="850" letter-spacing="-1.4">Waybi</text><text class="lockup-tag" x="98" y="64" font-family="system-ui,sans-serif" font-size="11" letter-spacing="1.5">A CLEARER JOURNEY</text></svg>`;
}
