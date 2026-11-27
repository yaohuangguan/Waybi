/** Coordinates are longitude first on Worker APIs and GeoJSON. */
export type LonLat = [longitude: number, latitude: number];
export interface GeoPoint { latitude: number; longitude: number }
export type UsageRecorder = (provider: string, sku: string, units: number) => void;
/** Compatibility boundary for provider JSON whose fields are checked at use.
 * Narrow individual provider schemas as adapters acquire their own contracts.
 */
export type ProviderPayload = Record<string, any>;
export interface RouteRequestOptions {
  forceIndependent?: boolean;
  exclusions?: import('./routing_closures.ts').ClosureLocation[];
  alternatives?: boolean;
  headingDegrees?: number;
  language?: string;
  /** Internal fallback strategy for incident-heavy detours, not a public route preference. */
  detourLocalRoads?: boolean;
  /** Pseudonymous caller key for the per-client NZ routing share. */
  routingClientKey?: string;
  /** Reserve paid Google units before calling Google; false falls back to independent routing. */
  reserveGoogle?: (sku: string, units: number) => Promise<boolean>;
  /** Internal: modes Amap could not answer are retried on the existing engines. */
  skipAmap?: boolean;
}
export interface PlacePhoto {
  url: string;
  attribution: string;
  sourceUrl?: string;
  licenseUrl?: string;
}
export interface PlacePhotoCandidate {
  placeId: string;
  name: string;
  latitude: number;
  longitude: number;
  photoUrl?: string;
  photoAttribution?: string;
  photoCredit?: { sourceUrl?: string; licenseUrl?: string };
}
export interface CameraRow {
  id: string;
  region: string;
  suburb: string;
  location: string;
  type: string;
  latitude: number;
  longitude: number;
  [field: string]: unknown;
}
export type OfficialRoadEventType = 'roadClosure' | 'roadworks' | 'incident' | 'flooding' | 'slip';
export interface OfficialRoadEvent {
  id: string;
  type: OfficialRoadEventType;
  location: GeoPoint;
  geometry: GeoPoint[];
  roadName: string | null;
  headingDegrees: number | null;
  severity: 'critical' | 'warning' | 'advisory';
  observation: 'official';
  confidence: number;
  validFrom: string | null;
  validUntil: string | null;
  source: {
    provider: string;
    country: string;
    region: string | null;
    sourceId: string;
    updatedAt: string | null;
  };
  metadata: Record<string, string | boolean | null>;
}
export interface RoadEventState {
  events: OfficialRoadEvent[];
  source: string;
  checkedAt: string;
  retrievedAt: string | null;
  syncStatus: 'live' | 'stale' | 'unavailable';
  syncError: string | null;
  /** Events starting within this many hours are included with validFrom set. */
  scheduledWindowHours?: number;
  /** Source feeds that failed in the latest refresh (their last events are retained). */
  failedFeeds?: string[];
}
