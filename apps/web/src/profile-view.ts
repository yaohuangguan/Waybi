import { currentProfile, type Language } from './account';
import { formatDistance } from '@waybi/core';
import { localeFor, t, type MessageKey } from './i18n';

const MODE_KEYS: Record<string, MessageKey> = { drive: 'modeNameDrive', transit: 'modeNameTransit', walk: 'modeNameWalk', bicycle: 'modeNameBicycle' };

function element(tag: string, className: string, content?: string) {
  const node = document.createElement(tag);
  node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
}

export function renderProfileView(root: HTMLElement, language: Language, openSignIn: () => void) {
  root.replaceChildren();
  const profile = currentProfile();
  if (!profile) {
    root.append(element('p', 'profile-empty', t(language, 'profileGuest')));
    const button = element('button', 'account-button', t(language, 'profileSignIn'));
    button.onclick = openSignIn;
    root.append(button);
    return;
  }

  root.append(element('p', 'profile-email', profile.user.email));
  const stats = element('div', 'profile-stats');
  for (const [number, label] of [
    [profile.routeHistory?.length || 0, t(language, 'profileTrips')],
    [profile.savedPlaces?.filter((place) => place.isFavorite).length || 0, t(language, 'profileFavorites')],
    [profile.reviews?.length || 0, t(language, 'profileReviews')]
  ] as const) {
    const stat = element('div', 'profile-stat');
    stat.append(element('strong', '', String(number)), element('span', '', label));
    stats.append(stat);
  }
  root.append(stats);

  const section = (title: string, empty: string) => {
    const block = element('section', 'profile-section');
    block.append(element('h3', '', title));
    root.append(block);
    return { block, empty: () => block.append(element('p', 'profile-empty', empty)) };
  };
  const trips = section(t(language, 'profileRecent'), t(language, 'profileNoTrips'));
  if (!profile.routeHistory?.length) trips.empty();
  for (const trip of profile.routeHistory || []) {
    const row = element('article', 'profile-item');
    row.append(element('strong', '', trip.destinationName));
    const distance = trip.distanceMeters == null ? '' : ` · ${formatDistance(trip.distanceMeters, language)}`;
    const mode = MODE_KEYS[trip.mode] ? t(language, MODE_KEYS[trip.mode]!) : trip.mode;
    row.append(element('small', '', `${mode}${distance} · ${new Date(trip.startedAt).toLocaleString(localeFor(language))}`));
    trips.block.append(row);
  }

  const favorites = section(t(language, 'profileFavoritePlaces'), t(language, 'profileNoPlaces'));
  if (!profile.savedPlaces?.length) favorites.empty();
  for (const place of profile.savedPlaces || []) {
    const row = element('article', 'profile-item');
    row.append(element('strong', '', `${place.isFavorite ? '♥ ' : ''}${place.name}`));
    if (place.address) row.append(element('small', '', place.address));
    if (place.note) row.append(element('p', '', place.note));
    favorites.block.append(row);
  }

  const reviews = section(t(language, 'profileMyReviews'), t(language, 'profileNoReviews'));
  if (!profile.reviews?.length) reviews.empty();
  for (const review of profile.reviews || []) {
    const row = element('article', 'profile-item');
    row.append(element('strong', '', `${review.placeName} · ${'★'.repeat(review.rating)}`));
    if (review.comment) row.append(element('p', '', review.comment));
    row.append(element('small', '', new Date(review.updatedAt).toLocaleDateString(localeFor(language))));
    reviews.block.append(row);
  }
}
