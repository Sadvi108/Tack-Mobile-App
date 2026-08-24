const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });
const U = process.env.SUPABASE_URL, S = process.env.SUPABASE_SERVICE_ROLE_KEY;
(async () => {
  const list = await fetch(`${U}/auth/v1/admin/users?per_page=200`, { headers: { apikey: S, Authorization: `Bearer ${S}` } }).then(r => r.json());
  const targets = (list.users || []).filter(u => u.email && u.email.endsWith('@tack.test'));
  console.log('test users found:', targets.length);
  for (const u of targets) {
    const r = await fetch(`${U}/auth/v1/admin/users/${u.id}`, {
      method: 'DELETE', headers: { apikey: S, Authorization: `Bearer ${S}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ should_soft_delete: false })
    });
    console.log(' ', u.email, r.status, (await r.text()).slice(0, 160));
  }
})();
