/**
 * Everything a client calls, behind one Function.
 *
 * ## Why this exists
 *
 * The design has three client-facing Functions — `write`, `auth` and
 * `operation` — and the Cloud plan allows **two in total** against the
 * seven this backend needs (3 October 2026; see
 * `docs/CLOUD-VERIFICATION.md`). So the three collapse here and the
 * four server-side ones collapse into `worker.js`.
 *
 * Nothing about their behaviour changes. Each of the three is already
 * `handler(fn)` — a complete handler that writes its own response — so
 * this routes to one and gets out of the way. That composability is
 * what makes the consolidation a dispatcher rather than a rewrite, and
 * it is why the three modules, their tests and their refusals are
 * untouched.
 *
 * ## Routing
 *
 * On the execution's **path**, which Appwrite passes through from
 * `createExecution({ path })` and exposes as `req.path`:
 *
 *   /write      → write.js
 *   /auth       → auth.js
 *   /operation  → operation.js
 *
 * A path rather than a field in the body, because the body already
 * belongs to each sub-handler and giving the router a share of it
 * would mean every caller sends a discriminator the handler then has
 * to ignore.
 *
 * ## The permission this widens, and why it is still safe
 *
 * `auth` must be callable by a guest — registration and recovery
 * happen before there is a session — so the merged Function is
 * `execute: ['any']`, where `write` and `operation` were `['users']`.
 *
 * That is not a hole: both call `callerId(req)` before they do
 * anything, and that reads `x-appwrite-user-id`, a header Appwrite
 * sets only for an authenticated execution and a client cannot forge.
 * A guest reaching `/write` gets the same 401 it always got; what
 * changes is that the refusal now comes from this code rather than
 * from the platform, which costs one execution and no access.
 */
import auth from './auth.js';
import operation from './operation.js';
import write from './write.js';

/** The three, by the path each is reached on. */
const ROUTES = {
  '/write': write,
  '/auth': auth,
  '/operation': operation,
};

export function routeFor(path) {
  const clean = `/${String(path ?? '').trim().replace(/^\/+|\/+$/g, '')}`;
  return ROUTES[clean] ?? null;
}

export default async (context) => {
  const route = routeFor(context.req.path);
  if (!route) {
    // Named, because the alternative is a client that silently calls
    // nothing: a wrong path used to be a 404 from Appwrite naming the
    // Function, and now it has to name itself.
    return context.res.json(
      {
        message:
          `Unknown path: ${context.req.path}. ` +
          `Expected one of ${Object.keys(ROUTES).join(', ')}.`,
        type: 'general_route_not_found',
      },
      404,
    );
  }
  return route(context);
};
