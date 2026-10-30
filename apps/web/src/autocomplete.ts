import { t, type Language } from './i18n';
import type { RecentDestination } from './account';

export type SuggestedPlace = { id: string | number; label: string; name?: string; address?: string; isPoi?: boolean; latitude: number; longitude: number };
export function placeLabel(place: SuggestedPlace): string {
  if (!place.isPoi || !place.name) return place.label;
  const address = place.address || place.label;
  return address.startsWith(place.name) ? address : `${place.name}, ${address}`;
}
type Target = 'origin' | 'destination';

export function initAutocomplete(options: {
  origin: HTMLInputElement;
  destination: HTMLInputElement;
  results: HTMLElement;
  language: () => Language;
  recent: () => RecentDestination[];
  near?: () => [number, number] | null;
  select: (target: Target, place: SuggestedPlace) => void;
}) {
  let timer = 0;
  let pending: AbortController | null = null;
  let configured = true;
  let sequence = 0;

  function render(target: Target, places: SuggestedPlace[], heading?: string) {
    options.results.replaceChildren();
    if (heading) {
      const label = document.createElement('div');
      label.className = 'search-message';
      label.textContent = heading;
      options.results.append(label);
    }
    for (const place of places) {
      const button = document.createElement('button');
      button.className = 'result-item';
      button.type = 'button';
      const pin = document.createElement('span');
      pin.className = 'result-pin';
      pin.textContent = '⌖';
      const label = document.createElement('span');
      label.textContent = placeLabel(place);
      button.append(pin, label);
      button.onclick = () => {
        pending?.abort();
        window.clearTimeout(timer);
        options.results.hidden = true;
        options.select(target, { ...place, label: placeLabel(place) });
      };
      options.results.append(button);
    }
    options.results.hidden = !options.results.childElementCount;
  }

  function showRecent() {
    const recent = options.recent();
    if (recent.length) render('destination', recent.map((place, index) => ({ ...place, id: index })), t(options.language(), 'guestRecent'));
  }

  for (const [target, input] of [['origin', options.origin], ['destination', options.destination]] as const) {
    input.addEventListener('focus', () => {
      if (target === 'destination' && !input.value.trim()) showRecent();
    });
    input.addEventListener('input', () => {
      pending?.abort();
      window.clearTimeout(timer);
      const query = input.value.trim();
      if (query.length < 3) {
        if (target === 'destination' && !query) showRecent();
        else options.results.hidden = true;
        return;
      }
      const requestNumber = ++sequence;
      timer = window.setTimeout(async () => {
        pending = new AbortController();
        try {
          const near = options.near?.();
          const params = new URLSearchParams({ q: query, provider: 'independent', lang: options.language() });
          if (near) params.set('near', near.join(','));
          const searchUrl = `/api/search?${params}`;
          let response = await fetch(configured
            ? `/api/suggest?${params}`
            : searchUrl, { signal: pending.signal });
          if (configured && response.status === 503) {
            configured = false;
            response = await fetch(searchUrl, { signal: pending.signal });
          }
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          const places = await response.json() as SuggestedPlace[];
          if (requestNumber === sequence && input.value.trim() === query) render(target, places);
        } catch (error) {
          if ((error as Error).name !== 'AbortError' && requestNumber === sequence) options.results.hidden = true;
        }
      }, 450);
    });
  }
}
