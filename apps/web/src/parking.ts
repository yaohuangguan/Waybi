import type { Coordinate } from '@waybi/core';

export type ParkingPlace = {
  id: string;
  source: 'at' | 'independent';
  name: string;
  address: string;
  coordinate: Coordinate;
  distanceMeters: number;
  sourceUrl?: string;
  totalSpaces: number | null;
  mobilitySpaces: number | null;
  clearanceMeters: number | null;
};
