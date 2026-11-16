// Configuration gate only. It never submits an inquiry or claims live delivery.
// Keys are deliberately never printed, including on validation failure.
const mode = process.env.PUBLIC_INQUIRY_MODE || 'email';
if (!['email', 'online'].includes(mode)) {
  console.error('PUBLIC_INQUIRY_MODE must be email or online.');
  process.exit(1);
}
if (mode === 'email') {
  console.log('Email-first publication: families review and send a draft in their email app. Online saves and live availability are disabled.');
  process.exit(0);
}
const problems = [];
const url = process.env.PUBLIC_SUPABASE_URL ?? '';
const key = process.env.PUBLIC_SUPABASE_ANON_KEY ?? '';
try {
  const parsed = new URL(url);
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password || /localhost|YOUR_PROJECT|example/i.test(parsed.hostname)) {
    problems.push('PUBLIC_SUPABASE_URL must be the real HTTPS project endpoint.');
  }
} catch {
  problems.push('PUBLIC_SUPABASE_URL is missing or invalid.');
}
let publicKey = /^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(key);
if (!publicKey && key.split('.').length === 3) {
  try {
    const claims = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString());
    publicKey = claims.role === 'anon' && (!claims.exp || claims.exp > Date.now() / 1000);
  } catch { /* Invalid or private keys fail closed. */ }
}
if (!publicKey) problems.push('PUBLIC_SUPABASE_ANON_KEY must be a publishable key or an unexpired legacy anon key. Never use a secret/service-role key.');
if (problems.length) {
  console.error('Publication configuration is not ready:');
  problems.forEach((problem) => console.error(`- ${problem}`));
  console.error('Local builds still work. Set the public configuration in the production build environment before publishing.');
  process.exitCode = 1;
} else if (process.argv.includes('--verify-api')) {
  try {
    const headers = { apikey: key, Accept: 'application/openapi+json' };
    if (key.startsWith('eyJ')) headers.Authorization = `Bearer ${key}`;
    const response = await fetch(`${url.replace(/\/$/, '')}/rest/v1/`, {
      method: 'GET', headers, signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error('unavailable');
    const schema = await response.json();
    if (!schema.paths?.['/rpc/sl_create_consultation_inquiry']) throw new Error('missing_rpc');
    console.log('Public API is reachable and exposes the inquiry endpoint. A real saved inquiry and owner email still require launch verification.');
  } catch {
    console.error('Publication blocked: the public API or consultation endpoint could not be verified. Check the active project, public key, API access and inquiry migration. No inquiry was submitted.');
    process.exitCode = 1;
  }
} else {
  console.log('Public contact configuration has valid syntax. Run with --verify-api to check the read-only API schema; still verify a saved inquiry and owner notification before launch.');
}
