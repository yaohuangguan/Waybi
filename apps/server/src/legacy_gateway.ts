// Temporary address compatibility for already-installed clients. All data and
// credentials live in the renamed Waybi Worker; this gateway stores nothing.
export default {
  fetch(request: Request, env) { return env.WAYBI.fetch(request); },
};
