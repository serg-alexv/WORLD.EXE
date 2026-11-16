import { fields, identifier, integer, requireThat } from './contracts.mjs';

/** A synthetic event adapter, NOT a Hornet API client or a private-feed deidentifier. */
export class SignalPipe {
  #seen = new Map();
  constructor(config) { this.enabled = config.sources.synthetic; }
  ingest(input, now = Date.now()) {
    fields(input, ['schemaVersion','eventID','source','observedAt','expiresAt','kind','intensity']);
    requireThat(input.schemaVersion === 1 && identifier(input.eventID), 'invalid_event');
    requireThat(this.enabled && input.source === 'synthetic', 'source_not_admitted', 403);
    requireThat(integer(input.observedAt, 0, Number.MAX_SAFE_INTEGER) && integer(input.expiresAt, 0, Number.MAX_SAFE_INTEGER), 'invalid_event_time');
    requireThat(input.observedAt <= now + 1000 && input.observedAt >= now - 60000 && input.expiresAt > now && input.expiresAt > input.observedAt && input.expiresAt <= input.observedAt + 60000, 'expired_or_future_event');
    requireThat(['supply','pressure'].includes(input.kind) && integer(input.intensity, 0, 3), 'invalid_signal');
    for (const [id, until] of this.#seen) if (until <= now) this.#seen.delete(id);
    requireThat(!this.#seen.has(input.eventID), 'duplicate_event', 409);
    requireThat(this.#seen.size < 1024, 'signal_capacity', 429);
    this.#seen.set(input.eventID, input.expiresAt);
    // Construct a fresh capability-reduced object; never forward the provider's record.
    return Object.freeze({ kind: input.kind, intensity: input.intensity, expiresAt: input.expiresAt });
  }
}
