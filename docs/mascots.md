# Waybi companions

The existing Waybi bird is unchanged. The logo lockup retains its original SVG
bird paths and replaces the old wordmark with Waybi. Serialized marker choices
remain `kiwi`, `cat`, and `dog` for preference compatibility.

Caity and Sett were generated with the built-in image generation tool, using the
existing bird as a style reference. Both PNGs retain transparent backgrounds.
The same cached 96 px render is used by Google and Waybi Map location markers;
settings use the source PNGs directly.

Final prompt set:

- Caity: a polished, colorful orange-and-cream calico cat navigation companion,
  sitting facing forward, large expressive eyes, soft blush, lime bandana,
  cream/lime circular badge, crisp readable silhouette at map-marker size.
  Match the warm friendly Waybi bird style; no words, preserve transparency
  outside the badge, keep the reference bird unchanged.
- Sett: a polished, colorful golden-tan-and-cream floppy-eared dog navigation
  companion, sitting facing forward, large expressive eyes, soft blush, teal
  bandana, cream/lime circular badge, crisp readable silhouette at map-marker
  size. Match the warm friendly Waybi bird style; no words, preserve transparency
  outside the badge, keep the reference bird unchanged.

Saved assets: `apps/mobile/assets/markers/caity.png` and
`apps/mobile/assets/markers/sett.png`. No fallback CLI was used.
