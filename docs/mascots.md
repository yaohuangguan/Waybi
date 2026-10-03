# Waybi companions

Waybi's bird artwork remains unchanged. Clover is the gray tabby cat and Sett
is the orange-and-white corgi from the supplied character artwork. The former
Caity display name is now Clover. Serialized marker preferences remain `kiwi`,
`cat`, and `dog`, so existing selections survive the update.

The built-in image generation tool extracted each character separately with
actual transparency. App settings and the website use these cutouts. The
shared Google/Waybi map renderer adds a soft pink or blue circular base with a
white rim when rasterizing the cached 96 px location puck. No background circle
or text is baked into the source character.

The home search prompt follows the marker selection, greeting the user as
Waybi, Clover, or Sett. Its small motion finishes after 2.4 seconds. System
Reduce Motion disables the animation; other marker styles greet as Waybi.

Final prompt set (built-in tool; no fallback CLI):

- Clover: extract only the left gray tabby cat; preserve the sitting pose,
  curled striped tail, gray stripes, white muzzle/chest/paws, pink nose and
  ears, dark green eyes, original illustration style and colors. Remove the
  pink circle, background, text, slogan and dog. Center the complete cat on a
  square transparent canvas, with clean alpha edges and no added decorations.
- Sett: extract only the right orange-and-white corgi; preserve the standing
  pose, short legs, upright pink-lined ears, curled white-tipped tail, white
  forehead stripe/muzzle/chest/paws, dark green eyes, happy mouth and pink
  tongue, original illustration style and colors. Remove the blue circle,
  background, text, slogan and cat. Center the complete dog on a square
  transparent canvas, with clean alpha edges and no added decorations.

App assets: `apps/mobile/assets/markers/clover.png` and
`apps/mobile/assets/markers/sett.png`. Matching website assets live under
`apps/web/public/brand/` with the same filenames.
