# Website Analytics

Website events use a separate web_events table and POST /v1/web-events.
Only the production https://ar-asia.luopeike.com origin is allowed.
The endpoint accepts fixed model/theme identifiers, locale, coarse device
class, print count/layout, and bounded load duration. It rejects search
text, URLs, referrers, and arbitrary properties. Random tab-session UUIDs
are hashed with a separate web: prefix before storage. There is no
persistent browser identity. A daily task deletes web events older than
90 days.

Run checks and apply the migration before deploying:

~~~sh
npm run typecheck
npm test
npm run db:migrate:remote
npm run deploy
~~~

Localhost, automated browser tests, GPC, and DNT do not send events.
The aggregate queries in web_usage.sql summarize live website usage:

~~~sh
npx wrangler d1 execute little-nature-analytics --remote --file web_usage.sql
~~~

Tab sessions do not measure people or cross-session retention. App Store
link clicks are not downloads. Installation attribution requires an ASC
campaign provider token configured when generating the website.
