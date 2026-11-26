import type { MessageKey } from './i18n';

export type Platform = 'ios' | 'android' | 'desktop';

/** Coarse platform detection, only used to word location-permission help. */
export function detectPlatform(userAgent = '', maxTouchPoints = 0): Platform {
  if (/iPhone|iPad|iPod/i.test(userAgent)) return 'ios';
  // iPadOS reports a desktop Safari user agent but has a touch screen.
  if (/Macintosh/i.test(userAgent) && maxTouchPoints > 1) return 'ios';
  if (/Android/i.test(userAgent)) return 'android';
  return 'desktop';
}

export function currentPlatform(): Platform {
  try { return detectPlatform(navigator.userAgent, navigator.maxTouchPoints || 0); } catch { return 'desktop'; }
}

export function isStandalone() {
  try {
    return window.matchMedia('(display-mode: standalone)').matches || Boolean((navigator as Navigator & { standalone?: boolean }).standalone);
  } catch { return false; }
}

/** The help text shown after location permission was denied, worded for the user's device. */
export function permissionHelpKey(platform: Platform, standalone: boolean): MessageKey {
  if (platform === 'ios') return standalone ? 'permissionHelpIosApp' : 'permissionHelpIos';
  if (platform === 'android') return 'permissionHelpAndroid';
  return 'permissionHelpDesktop';
}
