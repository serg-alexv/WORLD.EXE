/** All network records are untrusted. Fail on unknown fields rather than forwarding them. */
export class GateError extends Error {
  constructor(code, status = 400) { super(code); this.name = 'GateError'; this.code = code; this.status = status; }
}
export function requireThat(ok, code, status = 400) { if (!ok) throw new GateError(code, status); }
export function fields(value, required, optional = []) {
  requireThat(value !== null && typeof value === 'object' && !Array.isArray(value), 'invalid_object');
  const allowed = new Set([...required, ...optional]);
  requireThat(required.every(k => Object.hasOwn(value, k)) && Object.keys(value).every(k => allowed.has(k)), 'unexpected_fields');
  return value;
}
export function integer(value, min, max) { return Number.isSafeInteger(value) && value >= min && value <= max; }
export function finite(value, min, max) { return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max; }
export function identifier(value) { return typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value); }
export function vector(value) { return Array.isArray(value) && value.length === 3 && value.every(v => finite(v, -1, 1)); }
export function deepFreeze(value) {
  for (const child of Object.values(value)) if (child && typeof child === 'object') deepFreeze(child);
  return Object.freeze(value);
}
export function validateConfig(input) {
  const c = structuredClone(input);
  fields(c, ['schemaVersion','project','environment','transport','simulation','sources','ai','safety']);
  requireThat(c.schemaVersion === 1 && c.environment === 'local', 'production_not_qualified');
  fields(c.project, ['repository','appleApp','bundle','baselineVersion','baselineBuild','baselineBuildID']);
  const target = { repository:'serg-alexv/WORLD.EXE', appleApp:'6834963735', bundle:'org.worldexe.prototype', baselineVersion:'0.4.0', baselineBuild:'8.1', baselineBuildID:'e4e8f63b-4341-4657-b586-bc35d43d6400' };
  requireThat(Object.entries(target).every(([k,v]) => c.project[k] === v), 'wrong_project_or_baseline');
  fields(c.transport, ['host','port','bodyLimitBytes']);
  requireThat(c.transport.host === '127.0.0.1' && integer(c.transport.port, 0, 65535) && integer(c.transport.bodyLimitBytes, 512, 16384), 'unsafe_transport');
  fields(c.simulation, ['tickHz','maxRooms','maxPlayers','botsPerRoom','roomTTLSeconds','sessionTTLSeconds']);
  const ranges = { tickHz:[10,60], maxRooms:[1,256], maxPlayers:[2,32], botsPerRoom:[0,8], roomTTLSeconds:[60,3600], sessionTTLSeconds:[30,1800] };
  requireThat(Object.entries(ranges).every(([k,r]) => integer(c.simulation[k], ...r)), 'simulation_bounds');
  fields(c.sources, ['synthetic','hornet','grindr','privateVault']);
  requireThat(typeof c.sources.synthetic === 'boolean' && ['hornet','grindr','privateVault'].every(k => c.sources[k] === false), 'provider_access_not_authorized');
  fields(c.ai, ['policy','cloudRequestsAllowed']);
  requireThat(c.ai.policy === 'deterministic' && c.ai.cloudRequestsAllowed === 0, 'unqualified_ai_provider');
  fields(c.safety, ['rawMeshUpload','geographicCoordinates','nonPlayerTargets','autoDeploy']);
  requireThat(Object.values(c.safety).every(v => v === false), 'unsafe_capability');
  return deepFreeze(c);
}
