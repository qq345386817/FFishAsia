# Little Nature Analytics

First-party Cloudflare Worker and D1 backend for privacy-scoped product analytics.

The endpoint accepts only allowlisted events and fixed model properties. Installation and session UUIDs are HMAC-hashed before storage. Search text, camera content, model files, account details, free-form text, and request IP addresses are not stored.

```bash
npm install
npx wrangler secret put INSTALLATION_HASH_KEY
npm run db:migrate:remote
npm run deploy
curl --noproxy '*' https://littlenature-api.luopeike.com/health
```
