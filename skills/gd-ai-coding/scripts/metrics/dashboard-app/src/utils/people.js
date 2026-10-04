export function nameForEmail(email, committers) {
  const byEmail = new Map((committers || []).map(c => [c.committer, c.committer_name || c.committer]))
  return byEmail.get(email) || (email || '').split('@')[0]
}
