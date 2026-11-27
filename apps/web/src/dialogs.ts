/**
 * Modal dialogs built on <dialog>.showModal(): the browser moves focus into
 * the dialog, keeps it there, makes the page behind it inert and closes it on
 * Escape. We add closing on a backdrop click and returning focus to whatever
 * opened the dialog.
 */
const openers = new WeakMap<HTMLDialogElement, HTMLElement | null>();
const wired = new WeakSet<HTMLDialogElement>();

function wire(dialog: HTMLDialogElement) {
  if (wired.has(dialog)) return;
  wired.add(dialog);
  dialog.addEventListener('click', (event) => {
    // A click on the ::backdrop is reported on the dialog itself, outside its box.
    if (event.target !== dialog) return;
    const rect = dialog.getBoundingClientRect();
    const { clientX: x, clientY: y } = event as MouseEvent;
    const inside = rect.width > 0 && x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
    if (!inside || (x === 0 && y === 0)) closeDialog(dialog);
  });
  dialog.addEventListener('close', () => {
    const opener = openers.get(dialog);
    openers.delete(dialog);
    if (opener && opener.isConnected && !opener.closest('[hidden], [inert]')) opener.focus({ preventScroll: true });
  });
}

export function openDialog(dialog: HTMLDialogElement, opener: Element | null = document.activeElement) {
  wire(dialog);
  if (dialog.open) return;
  openers.set(dialog, opener instanceof HTMLElement && opener !== document.body ? opener : null);
  if (typeof dialog.showModal === 'function') dialog.showModal();
  else dialog.setAttribute('open', '');
  // Prefer the dialog's own initial focus target when it has one.
  const initial = dialog.querySelector<HTMLElement>('[autofocus], [data-initial-focus]');
  initial?.focus();
}

export function closeDialog(dialog: HTMLDialogElement) {
  if (!dialog.open) return;
  if (typeof dialog.close === 'function') dialog.close();
  else { dialog.removeAttribute('open'); dialog.dispatchEvent(new Event('close')); }
}

export function isDialogOpen(dialog: HTMLDialogElement) { return dialog.open; }
