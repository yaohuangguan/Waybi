export async function saveNavigationFeedback(db, body) {
  if (!body || typeof body.id !== 'string' || !/^[a-f0-9]{32}$/.test(body.id) || ![-1, 1].includes(body.vote)) {
    throw new TypeError('A valid feedback receipt and vote are required');
  }
  // Replayed offline receipts preserve the original vote.
  await db.prepare('INSERT INTO navigation_feedback (id, vote) VALUES (?, ?) ON CONFLICT(id) DO NOTHING')
    .bind(body.id, body.vote).run();
}
