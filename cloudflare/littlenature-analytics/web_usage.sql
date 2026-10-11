-- Website events are separate from native app events. Sessions are browser
-- tab sessions, not installations or identified people.
SELECT date(occurred_at / 1000, 'unixepoch') AS day,
       locale, device_class, event_name,
       count(*) AS events,
       count(DISTINCT session_id_hash) AS tab_sessions
FROM web_events
WHERE occurred_at >= (unixepoch() - 28 * 86400) * 1000
GROUP BY day, locale, device_class, event_name
ORDER BY day DESC, locale, event_name;

SELECT json_extract(properties_json, '$.model_id') AS model_id,
       sum(event_name = 'viewer_start') AS starts,
       sum(event_name = 'viewer_ready') AS ready,
       sum(event_name = 'viewer_error') AS errors,
       sum(event_name = 'model_interaction') AS interactions,
       sum(event_name = 'animation_play') AS animation_plays
FROM web_events
WHERE occurred_at >= (unixepoch() - 28 * 86400) * 1000
  AND json_extract(properties_json, '$.model_id') IS NOT NULL
GROUP BY model_id
ORDER BY ready DESC;
