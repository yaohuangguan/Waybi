import test from 'node:test';
import assert from 'node:assert/strict';
import { pbkdf2Sync } from 'node:crypto';
import { hashPassword, quickLocationsFromBookmarks, subscriptionForUser, userHasPlus, verifyPassword } from '../src/auth.mjs';

const salt = '00112233445566778899aabbccddeeff';

test('new password hashes are versioned scrypt values', async () => {
  const stored = await hashPassword('long-secret-password', salt);
  assert.match(stored, /^scrypt-v1\$[0-9a-f]{64}$/);
  assert.equal(await verifyPassword('long-secret-password', salt, stored), true);
  assert.equal(await verifyPassword('wrong-password', salt, stored), false);
});

test('existing PBKDF2 hashes remain valid', async () => {
  const stored = pbkdf2Sync('long-secret-password', Buffer.from(salt, 'hex'), 210_000, 32, 'sha256').toString('hex');
  assert.equal(await verifyPassword('long-secret-password', salt, stored), true);
  assert.equal(await verifyPassword('wrong-password', salt, stored), false);
});


function subscriptionDb(row) {
  return {
    prepare() {
      return {
        bind() {
          return {
            async first() {
              return row;
            }
          };
        }
      };
    }
  };
}

test('active Plus subscription is returned as an entitlement', async () => {
  const now = Date.now();
  const db = subscriptionDb({
    plan: 'plus',
    source: 'manual',
    expiresAt: now + 60_000,
  });
  assert.deepEqual(await subscriptionForUser(db, 'user-1', now), {
    plan: 'plus',
    source: 'manual',
    expiresAt: now + 60_000,
  });
  assert.equal(await userHasPlus(db, 'user-1', now), true);
});

test('expired or missing subscription falls back to free', async () => {
  const now = Date.now();
  const expired = subscriptionDb({
    plan: 'plus',
    source: 'manual',
    expiresAt: now - 1,
  });
  assert.deepEqual(await subscriptionForUser(expired, 'user-1', now), {
    plan: 'free',
    source: null,
    expiresAt: null,
  });
  assert.equal(await userHasPlus(subscriptionDb(null), 'user-1', now), false);
});


test('quick locations preserve account label and map provider', () => {
  assert.deepEqual(quickLocationsFromBookmarks([
    { placeId: 'waybi:quick:home', name: 'My Home', address: '1 Queen St', latitude: -36.85, longitude: 174.76, note: 'independent', updatedAt: 10 },
    { placeId: 'waybi:quick:work', name: 'Office', address: '2 Albert St', latitude: -36.84, longitude: 174.77, note: 'google', updatedAt: 20 },
    { placeId: 'google:other', name: 'Other', address: '', latitude: 0, longitude: 0, note: 'independent', updatedAt: 30 },
  ]), [
    { label: 'Home', name: 'My Home', address: '1 Queen St', latitude: -36.85, longitude: 174.76, provider: 'independent', updatedAt: 10 },
    { label: 'Work', name: 'Office', address: '2 Albert St', latitude: -36.84, longitude: 174.77, provider: 'google', updatedAt: 20 },
  ]);
});
