import { beforeEach, expect, it, vi } from 'vitest';
import type { AccountProfile } from '../src/account';
let account: typeof import('../src/account');
let renderProfileView: typeof import('../src/profile-view').renderProfileView;
beforeEach(async () => {
  vi.resetModules();
  account = await import('../src/account');
  renderProfileView = (await import('../src/profile-view')).renderProfileView;
});

const profile = {user:{id:'u',email:'driver@example.test'},language:'zh',voiceEnabled:false,recentDestinations:[],savedPlaces:[],routeHistory:[],reviews:[]} as AccountProfile;
async function guest() {
  const fetcher=vi.fn().mockResolvedValue(new Response('{}',{status:401}));
  vi.stubGlobal('fetch',fetcher);
  const root=document.createElement('div');
  document.body.append(root);
  const loaded=vi.fn();
  await account.initAccount(root,()=> 'en',()=>true,loaded);
  return {root,fetcher,loaded};
}
it('keeps guest navigation available and requires sign-in for saved data', async () => {
  const {root,fetcher}=await guest();
  expect(account.isSignedIn()).toBe(false);
  expect(root.textContent).toContain('Guest mode');
  await account.rememberPreferences('zh',false);
  await account.rememberDestination({label:'Airport',latitude:-37,longitude:174});
  await account.rememberRoute({destinationName:'Airport',latitude:-37,longitude:174,mode:'drive',distanceMeters:1,durationSeconds:1});
  expect(fetcher).toHaveBeenCalledTimes(1);
  await expect(account.savePlace({} as any)).rejects.toThrow('Sign in');
  await expect(account.saveOwnReview({} as any)).rejects.toThrow('Sign in');
  const open=vi.fn();renderProfileView(root,'zh',open);
  root.querySelector('button')!.click();
  expect(open).toHaveBeenCalledOnce();
});
it('registers, displays errors, recovers and clears the session on failed logout', async () => {
  const {root,fetcher,loaded}=await guest();
  (root.querySelector('.account-link') as HTMLElement).click();
  const password=root.querySelector<HTMLInputElement>('input[type=password]')!;
  expect(password.minLength).toBe(12);
  root.querySelector<HTMLInputElement>('input[type=email]')!.value='driver@example.test';
  password.value='test-only-long-password';
  fetcher.mockResolvedValueOnce(Response.json({error:'Try later'},{status:503}));
  const submit=()=>root.querySelector('form')!.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));
  submit(); await vi.waitFor(()=>expect(root.textContent).toContain('Try later'));
  expect(root.querySelector<HTMLButtonElement>('button[type=submit]')!.disabled).toBe(false);
  fetcher.mockResolvedValueOnce(Response.json(profile));
  submit();await vi.waitFor(()=>expect(account.isSignedIn()).toBe(true));
  expect(loaded).toHaveBeenCalledWith(profile);
  const request=fetcher.mock.calls.at(-1)!;
  expect(request[0]).toBe('/api/auth/register');
  expect(request[1]).toMatchObject({credentials:'same-origin',headers:expect.objectContaining({'x-waybi-client':'web'})});
  fetcher.mockRejectedValueOnce(new Error('offline'));
  (root.querySelector('button')!).click();
  await vi.waitFor(()=>expect(account.isSignedIn()).toBe(false));
});
it('syncs profile features and treats user text as plain text', async () => {
  const populated={...profile,recentDestinations:[{label:'Home',latitude:-37,longitude:174}],savedPlaces:[{placeId:'p',name:'<script>bad()</script>',address:'CBD',latitude:-37,longitude:174,isFavorite:true,note:'<img src=x>',updatedAt:1}],routeHistory:[{id:'r',destinationName:'Airport',latitude:-37,longitude:174,mode:'drive',distanceMeters:1500,durationSeconds:60,startedAt:1}],reviews:[{placeId:'p',placeName:'Cafe',rating:4,comment:'Nice',updatedAt:1}]};
  const fetcher=vi.fn().mockImplementation(()=>Promise.resolve(Response.json(populated)));
  vi.stubGlobal('fetch',fetcher);
  const root=document.createElement('div');
  await account.initAccount(root,()=> 'zh',()=>false,vi.fn());
  expect(account.currentAccountEmail()).toBe(profile.user.email);
  expect(account.recentDestinations()).toHaveLength(1);
  expect(account.savedPlace('missing')).toBeNull();
  expect(account.ownReview('missing')).toBeNull();
  await account.rememberPreferences('en',true);
  await account.rememberDestination(populated.recentDestinations[0]);
  expect(await account.savePlace(populated.savedPlaces[0])).toEqual(populated.savedPlaces[0]);
  await account.rememberRoute(populated.routeHistory[0]);
  expect(await account.saveOwnReview(populated.reviews[0])).toEqual(populated.reviews[0]);
  renderProfileView(root,'zh',vi.fn());
  expect(root.textContent).toContain('1.5 km');
  expect(root.textContent).toContain('★★★★');
  expect(root.querySelector('script')).toBeNull();
  expect(root.querySelector('img')).toBeNull();
});
