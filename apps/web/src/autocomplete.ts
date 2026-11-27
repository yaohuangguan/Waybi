import { plural, t, type Language } from './i18n';
import type { RecentDestination } from './account';
import { apiFetch, describeError, isAbortError } from './api';

export type SuggestedPlace = { id: string | number; label: string; name?: string; address?: string; isPoi?: boolean; latitude: number; longitude: number };
export function placeLabel(place: SuggestedPlace): string {
  if (!place.isPoi || !place.name) return place.label;
  const address = place.address || place.label;
  return address.startsWith(place.name) ? address : `${place.name}, ${address}`;
}
type Target = 'origin' | 'destination';

export const SUGGEST_DEBOUNCE_MS = 450;
/** Fallback full searches are heavier, so they wait a little longer between keystrokes. */
export const SEARCH_FALLBACK_DEBOUNCE_MS = 800;
/** After /api/suggest says it is unavailable, use full search for a while, then try suggest again. */
export const SUGGEST_COOLDOWN_MS = 60_000;

export type AutocompleteHandle = {
  /** Cancels the pending debounce and request and invalidates anything still in flight. */
  cancel(): void;
  /** Claims the results panel for a new request; returns a token for `isCurrent`. */
  begin(input: HTMLInputElement): number;
  isCurrent(token: number): boolean;
  renderPlaces(input: HTMLInputElement, places: SuggestedPlace[], onSelect: (place: SuggestedPlace) => void, heading?: string): void;
  showMessage(input: HTMLInputElement, message: string, retry?: () => void): void;
  close(): void;
};

/**
 * Wires the search inputs as ARIA 1.2 comboboxes sharing one listbox:
 * typing shows debounced suggestions, ArrowUp/ArrowDown move the active
 * option, Enter picks it, Escape and blur close the list. Every request
 * (suggestion or full search) claims the panel, so a late response can never
 * replace newer results.
 */
export function initAutocomplete(options: {
  origin: HTMLInputElement;
  destination: HTMLInputElement;
  extraInputs?: HTMLInputElement[];
  results: HTMLElement;
  language: () => Language;
  recent: () => RecentDestination[];
  near?: () => [number, number] | null;
  select: (target: Target, place: SuggestedPlace) => void;
  now?: () => number;
}): AutocompleteHandle {
  const now = options.now || Date.now;
  const panel = options.results;
  let timer = 0;
  let pending: AbortController | null = null;
  let sequence = 0;
  let suggestCooldownUntil = 0;
  let owner: HTMLInputElement | null = null;
  let activeIndex = -1;
  let optionSelectors: (() => void)[] = [];

  // Panel structure: a polite status line and the listbox itself.
  panel.replaceChildren();
  const status = document.createElement('div');
  status.className = 'search-message';
  status.id = `${panel.id || 'search-results'}-status`;
  status.setAttribute('role', 'status');
  status.hidden = true;
  const listbox = document.createElement('div');
  listbox.id = `${panel.id || 'search-results'}-listbox`;
  listbox.className = 'search-listbox';
  listbox.setAttribute('role', 'listbox');
  panel.append(status, listbox);
  // Keep focus in the input while choosing with a pointer.
  panel.addEventListener('pointerdown', (event) => { if ((event.target as HTMLElement).closest('[role="option"], .search-retry')) event.preventDefault(); });
  const inputs = [options.origin, options.destination, ...(options.extraInputs || [])];

  for (const input of inputs) {
    input.setAttribute('role', 'combobox');
    input.setAttribute('aria-autocomplete', 'list');
    input.setAttribute('aria-expanded', 'false');
    input.setAttribute('aria-controls', listbox.id);
    input.setAttribute('aria-describedby', status.id);
  }

  function setExpanded(input: HTMLInputElement | null) {
    for (const node of inputs) {
      node.setAttribute('aria-expanded', String(node === input && !panel.hidden && listbox.childElementCount > 0));
      if (node !== input) node.removeAttribute('aria-activedescendant');
    }
  }

  function close() {
    panel.hidden = true;
    activeIndex = -1;
    owner?.removeAttribute('aria-activedescendant');
    setExpanded(null);
  }

  function cancel() {
    window.clearTimeout(timer);
    timer = 0;
    pending?.abort();
    pending = null;
    sequence += 1;
  }

  function begin(input: HTMLInputElement) {
    cancel();
    owner = input;
    return sequence;
  }

  const isCurrent = (token: number) => token === sequence;

  function setActive(index: number) {
    const items = Array.from(listbox.querySelectorAll<HTMLElement>('[role="option"]'));
    if (!items.length || !owner) { activeIndex = -1; return; }
    activeIndex = (index + items.length) % items.length;
    items.forEach((item, i) => item.setAttribute('aria-selected', String(i === activeIndex)));
    const active = items[activeIndex]!;
    owner.setAttribute('aria-activedescendant', active.id);
    active.scrollIntoView?.({ block: 'nearest' });
  }

  function showMessage(input: HTMLInputElement, message: string, retry?: () => void) {
    owner = input;
    listbox.replaceChildren();
    optionSelectors = [];
    activeIndex = -1;
    status.replaceChildren(document.createTextNode(message));
    if (retry) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'search-retry';
      button.textContent = t(options.language(), 'retry');
      button.onclick = retry;
      status.append(' ', button);
    }
    status.hidden = false;
    panel.hidden = false;
    setExpanded(input);
  }

  function renderPlaces(input: HTMLInputElement, places: SuggestedPlace[], onSelect: (place: SuggestedPlace) => void, heading?: string) {
    owner = input;
    listbox.replaceChildren();
    optionSelectors = [];
    activeIndex = -1;
    input.removeAttribute('aria-activedescendant');
    listbox.setAttribute('aria-label', heading || t(options.language(), 'suggestionsLabel'));
    places.forEach((place, index) => {
      const option = document.createElement('button');
      option.type = 'button';
      option.className = 'result-item';
      option.id = `${listbox.id}-option-${index}`;
      option.setAttribute('role', 'option');
      option.setAttribute('aria-selected', 'false');
      option.tabIndex = -1;
      const pin = document.createElement('span');
      pin.className = 'result-pin';
      pin.setAttribute('aria-hidden', 'true');
      pin.textContent = '⌖';
      const label = document.createElement('span');
      label.textContent = placeLabel(place);
      option.append(pin, label);
      const choose = () => {
        cancel();
        close();
        onSelect({ ...place, label: placeLabel(place) });
      };
      option.onclick = choose;
      optionSelectors.push(choose);
      listbox.append(option);
    });
    if (heading) { status.textContent = heading; status.hidden = false; }
    else if (places.length) {
      // Announce the count without showing an extra line.
      status.textContent = plural(options.language(), places.length, 'suggestionsCountOne', 'suggestionsCount');
      status.hidden = true;
    } else status.hidden = true;
    panel.hidden = !places.length && status.hidden;
    setExpanded(input);
  }

  function showRecent(input: HTMLInputElement) {
    const recent = options.recent();
    if (!recent.length) return;
    begin(input);
    renderPlaces(input, recent.map((place, index) => ({ ...place, id: index })), (place) => options.select('destination', place),
      t(options.language(), 'guestRecent'));
  }

  async function suggest(target: Target, input: HTMLInputElement, query: string, token: number) {
    const near = options.near?.();
    const params = new URLSearchParams({ q: query, provider: 'independent', lang: options.language() });
    if (near) params.set('near', near.join(','));
    pending = new AbortController();
    const signal = pending.signal;
    try {
      let places: SuggestedPlace[];
      if (now() >= suggestCooldownUntil) {
        try {
          places = await apiFetch<SuggestedPlace[]>(`/api/suggest?${params}`, { signal });
        } catch (error) {
          const failure = describeError(error);
          if (isAbortError(error) || failure.offline || failure.rateLimited || failure.status !== 503) throw error;
          // One unavailable answer pauses suggestions for a while, not forever.
          suggestCooldownUntil = now() + SUGGEST_COOLDOWN_MS;
          places = await apiFetch<SuggestedPlace[]>(`/api/search?${params}`, { signal });
        }
      } else places = await apiFetch<SuggestedPlace[]>(`/api/search?${params}`, { signal });
      if (!isCurrent(token) || input.value.trim() !== query) return;
      if (places.length) renderPlaces(input, places, (place) => options.select(target, place));
      else close();
    } catch (error) {
      if (isAbortError(error) || !isCurrent(token)) return;
      const failure = describeError(error);
      // Tell the user why nothing appears instead of silently hiding the list.
      if (failure.offline) showMessage(input, t(options.language(), 'suggestionsOffline'));
      else if (failure.busy) showMessage(input, t(options.language(), 'suggestionsBusy'));
      else close();
    } finally {
      if (isCurrent(token)) pending = null;
    }
  }

  for (const [target, input] of [['origin', options.origin], ['destination', options.destination]] as const) {
    input.addEventListener('focus', () => {
      if (target === 'destination' && !input.value.trim()) showRecent(input);
    });
    input.addEventListener('input', () => {
      const token = begin(input);
      const query = input.value.trim();
      if (query.length < 3) {
        if (target === 'destination' && !query) showRecent(input);
        else close();
        return;
      }
      const delay = now() >= suggestCooldownUntil ? SUGGEST_DEBOUNCE_MS : SEARCH_FALLBACK_DEBOUNCE_MS;
      timer = window.setTimeout(() => { timer = 0; void suggest(target, input, query, token); }, delay);
    });
  }

  for (const input of inputs) {
    input.addEventListener('keydown', (event) => {
      const open = !panel.hidden && owner === input && listbox.childElementCount > 0;
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        if (!open) return;
        event.preventDefault();
        const down = event.key === 'ArrowDown';
        setActive(activeIndex === -1 ? (down ? 0 : -1) : activeIndex + (down ? 1 : -1));
      } else if (event.key === 'Enter' && open && activeIndex >= 0) {
        // Choosing the highlighted option; the caller's Enter-to-search must not run.
        event.preventDefault();
        event.stopImmediatePropagation();
        optionSelectors[activeIndex]?.();
      } else if (event.key === 'Escape') {
        if (!panel.hidden) { event.preventDefault(); cancel(); close(); }
      }
    });
    input.addEventListener('blur', () => {
      // Let a click on an option land first.
      window.setTimeout(() => {
        if (owner === input && document.activeElement !== input && !panel.contains(document.activeElement)) close();
      }, 150);
    });
  }

  return { cancel, begin, isCurrent, renderPlaces, showMessage, close };
}
