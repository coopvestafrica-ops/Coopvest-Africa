/**
 * Runs migrations/019_loan_policy_enforcement.sql via the Supabase Management
 * API (database query endpoint) — no DB password required, only the
 * SUPABASE_ACCESS_TOKEN (sbp_...) and the project ref.
 *
 * Usage: SUPABASE_ACCESS_TOKEN=sbp_... node run-migration-019.js
 */

const fs = require('fs');
const path = require('path');

const PROJECT_REF = 'nyoauzqezpxeonmrxxgi';
const token = process.env.SUPABASE_ACCESS_TOKEN;

if (!token) {
  console.error('❌ SUPABASE_ACCESS_TOKEN not set');
  process.exit(1);
}

const sql = fs.readFileSync(path.join(__dirname, 'migrations', '019_loan_policy_enforcement.sql'), 'utf8');

async function run() {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query: sql }),
  });

  const body = await res.text();
  if (!res.ok) {
    console.error(`❌ Migration failed (HTTP ${res.status}):`);
    console.error(body);
    process.exit(1);
  }
  console.log('✅ Migration 019 applied successfully');
  if (body && body !== '[]') console.log(body);
}

run().catch((err) => {
  console.error('❌', err.message);
  process.exit(1);
});
