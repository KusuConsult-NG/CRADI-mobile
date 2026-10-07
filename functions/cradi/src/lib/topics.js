/**
 * Push topic subscriptions: who is subscribed to what, and keeping it true.
 *
 * Phase 3 mapped OneSignal's tag targeting onto Appwrite topics, and the
 * sending half of that landed — `alertTopics` decides which topics an
 * admin alert or an approved report is addressed to. The receiving half
 * had nothing at all: no device was ever registered as a push target and
 * no target was ever subscribed to a topic. Appwrite accepts a message to
 * a topic with no subscribers and reports it sent, so the failure was
 * silent in the worst way for an early-warning system.
 *
 * ## The subscribed set is derived from the sender, not copied
 *
 * `desiredTopics` does not slug a state and an LGA of its own. It asks
 * `alertTopics` what an alert aimed at this profile's own location would
 * be addressed to, because that is the only definition that matters: a
 * subscription whose id differs by one character from what the sender
 * writes is a subscription to nothing, and nothing would ever say so.
 *
 * Three bugs in this migration came from a fake built out of the code it
 * tests agreeing with itself. A second slug here would have been the
 * fourth, and the one with no test that could catch it — both sides would
 * have been wrong together and the suite would have been green.
 *
 * ## Why the profile remembers its own topics
 *
 * Appwrite's event payload is the row with no "before" — the same problem
 * `previousStatus` solves for reports — and no endpoint lists one user's
 * subscriptions, only one topic's subscribers. So a user moved from Benue
 * to Nasarawa would go on receiving Benue's alerts with nothing able to
 * tell that the old subscription is stale.
 *
 * `profiles.pushTopics` is what the server last subscribed this user's
 * devices to. Reconciling is the difference between that and the current
 * desire, and writing it back is the last step.
 */
import {
  ApiError,
  api,
  apiOrThrow,
  fnv1a64,
  updateRow,
} from './appwrite.js';
import { ALL_USERS_TOPIC, alertTopics } from './notifications.js';

/** The column `plan.mjs` adds for the memory described above. */
export const TOPICS_COLUMN = 'pushTopics';

/**
 * Every topic a profile's devices belong in.
 *
 * Three audiences, each read back from the sender rather than rebuilt:
 * everyone, everyone in the state, and everyone in the LGA. The LGA topic
 * is the state-scoped one — Obi exists in Benue and in Nasarawa — which
 * is exactly why this asks `alertTopics` instead of composing the id.
 *
 * A profile with an LGA and no state is malformed (the alerts table has a
 * check constraint for it) but reachable in `profiles`, and the report
 * broadcast path degrades to a name-only topic for it. This degrades the
 * same way, so the two sides stay addressable to each other even when
 * the data is wrong.
 */
export function desiredTopics(profile) {
  const state = String(profile?.state ?? '').trim();
  const lga = String(profile?.lga ?? '').trim();
  // `all-users` is how the sender addresses everyone, so everyone is in
  // it — including a profile with no location at all.
  const topics = [ALL_USERS_TOPIC];
  if (state) topics.push(...alertTopics({ targetState: state, targetLga: 'All' }).topics);
  if (lga) topics.push(...alertTopics({ targetState: state, targetLga: lga }).topics);
  // `alertTopics` can only return `all` for the no-location case, which
  // `all-users` above already covers; `.topics` is empty there.
  return [...new Set(topics)];
}

/**
 * A subscriber id, from the target and the topic.
 *
 * Deterministic, so subscribing twice is a 409 rather than a duplicate
 * and unsubscribing needs no stored id — the same property the outbox
 * and the message id lean on.
 *
 * Not `${targetId}-${topic}`: both can be long, Appwrite's limit is 36,
 * and a trimmed composite collides across topics in exactly the places
 * that matter (`lga-benue-…` and `lga-benue-…` share a prefix).
 */
export function subscriberId(targetId, topic) {
  return `sub-${fnv1a64(`${targetId}|${topic}`)}`;
}

/** Creates the topic if it is not there, as `ensureWardTeam` does for teams. */
export async function ensureTopic(topic) {
  const existing = await api(`/messaging/topics/${encodeURIComponent(topic)}`);
  if (existing.ok) return;
  const created = await api('/messaging/topics', {
    method: 'POST',
    body: { topicId: topic, name: topic },
  });
  // A concurrent reconcile may have created it between the two calls.
  if (!created.ok && created.status !== 409) throw new ApiError(created);
}

/**
 * This user's live push targets.
 *
 * `expired` targets are left out: Appwrite marks a target whose token the
 * provider has rejected, and subscribing one is how a topic's subscriber
 * count grows while its delivery does not.
 */
export async function listPushTargets(userId) {
  const listed = await apiOrThrow(`/users/${encodeURIComponent(userId)}/targets`);
  return (listed.targets ?? []).filter(
    (target) => target.providerType === 'push' && target.expired !== true,
  );
}

/**
 * Brings this user's subscriptions in line with their profile.
 *
 * Every target is subscribed to every desired topic — 409 means it
 * already was, which is the cheap half — and the topics in `pushTopics`
 * that are no longer desired are unsubscribed. A user with no registered
 * device is subscribed to nothing, so `pushTopics` becomes empty for
 * them rather than claiming subscriptions that do not exist.
 *
 * The write back is skipped when the set has not changed. That is not
 * only an economy: writing `profiles` raises another
 * `profiles.rows.*.update`, and while the event key makes the resulting
 * outbox row a duplicate of the one being handled (see `on-write.js`),
 * not writing at all is one less round of proving it.
 */
export async function reconcileSubscriptions({ userId, profile, log = () => {} }) {
  const desired = desiredTopics(profile);
  const stored = Array.isArray(profile?.[TOPICS_COLUMN]) ? profile[TOPICS_COLUMN] : [];
  const targets = await listPushTargets(userId);

  let subscribed = 0;
  if (targets.length > 0) {
    for (const topic of desired) {
      // Only ever created for a user who has a device in it. A topic per
      // LGA in the country, provisioned up front, is 770 rows against a
      // quota nobody has measured — and 769 of them would have no
      // subscribers.
      await ensureTopic(topic);
      for (const target of targets) {
        const made = await api(`/messaging/topics/${encodeURIComponent(topic)}/subscribers`, {
          method: 'POST',
          body: { subscriberId: subscriberId(target.$id, topic), targetId: target.$id },
        });
        if (made.ok) subscribed += 1;
        else if (made.status !== 409) throw new ApiError(made);
      }
    }
  }

  let removed = 0;
  for (const topic of stored) {
    if (desired.includes(topic)) continue;
    for (const target of targets) {
      const gone = await api(
        `/messaging/topics/${encodeURIComponent(topic)}/subscribers/${subscriberId(target.$id, topic)}`,
        { method: 'DELETE' },
      );
      if (gone.ok) removed += 1;
      // 404 is the state we wanted: either never subscribed, or the
      // target was deleted and took its subscriptions with it.
      else if (gone.status !== 404) throw new ApiError(gone);
    }
  }

  const next = targets.length > 0 ? desired : [];
  const changed =
    next.length !== stored.length || next.some((topic, at) => topic !== stored[at]);
  if (changed) {
    const written = await updateRow('profiles', userId, { [TOPICS_COLUMN]: next });
    if (!written.ok) throw new ApiError(written);
  }

  log(
    `push topics ${userId}: targets=${targets.length} +${subscribed} -${removed} ` +
      `now=[${next.join(' ')}]`,
  );
  return { topics: next, targets: targets.length, subscribed, removed, changed };
}
