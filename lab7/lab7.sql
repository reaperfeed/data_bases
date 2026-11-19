/* ================================================================
   ЗАПРОС 1. Последняя версия каждого сообщения
   ================================================================ */

DROP INDEX IF EXISTS idx_versions_message_latest;
DROP INDEX IF EXISTS idx_messages_not_deleted;

ANALYZE version_of_messages;
ANALYZE messages;

EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
SELECT m.message_id,
       m.chat_id,
       v.content,
       v.created_at
FROM messages AS m
JOIN version_of_messages AS v
  ON v.message_id = m.message_id
WHERE m.m_status <> 'deleted'
  AND v.version_number = (
      SELECT MAX(v2.version_number)
      FROM version_of_messages AS v2
      WHERE v2.message_id = v.message_id
  )
ORDER BY v.created_at DESC,
         m.message_id
LIMIT 1000;

/*
  Индексы для оптимизации
*/

CREATE INDEX IF NOT EXISTS idx_versions_message_latest
ON version_of_messages (message_id, version_number DESC)
INCLUDE (content, created_at);

CREATE INDEX IF NOT EXISTS idx_messages_not_deleted
ON messages (message_id, chat_id)
WHERE m_status <> 'deleted';

ANALYZE version_of_messages;
ANALYZE messages;


EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
SELECT message_id,
       chat_id,
       content,
       created_at
FROM (
    SELECT DISTINCT ON (m.message_id)
           m.message_id,
           m.chat_id,
           v.content,
           v.created_at
    FROM messages AS m
    JOIN version_of_messages AS v
      ON v.message_id = m.message_id
    WHERE m.m_status <> 'deleted'
      AND v.version_number IS NOT NULL
    ORDER BY m.message_id,
             v.version_number DESC
) AS latest
ORDER BY created_at DESC,
         message_id
LIMIT 1000;


/* ================================================================
   ЗАПРОС 2. Доставленные, но непрочитанные сообщения
   ================================================================ */

DROP INDEX IF EXISTS idx_delivery_delivered_pair;
DROP INDEX IF EXISTS idx_delivery_read_pair;
DROP INDEX IF EXISTS idx_devices_user_device;

ANALYZE delivery_events;
ANALYZE devices;
ANALYZE users;

EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
SELECT u.user_id,
       u.u_login,
       COUNT(*) AS unread_count,
       MAX(d.sent_at) AS last_unread
FROM users AS u
JOIN devices AS dv
  ON dv.user_id = u.user_id
JOIN delivery_events AS d
  ON d.device_id = dv.device_id
WHERE u.a_status = 'active'
  AND d.d_type = 'delivered'
  AND NOT EXISTS (
      SELECT 1
      FROM delivery_events AS r
      WHERE r.device_id = d.device_id
        AND r.message_id = d.message_id
        AND r.d_type = 'read'
  )
GROUP BY u.user_id,
         u.u_login
HAVING COUNT(*) >= 20
ORDER BY unread_count DESC;

/*
  Индексы для отбора событий
*/

CREATE INDEX IF NOT EXISTS idx_delivery_delivered_pair
ON delivery_events (device_id, message_id)
INCLUDE (sent_at)
WHERE d_type = 'delivered';

CREATE INDEX IF NOT EXISTS idx_delivery_read_pair
ON delivery_events (device_id, message_id)
WHERE d_type = 'read';

CREATE INDEX IF NOT EXISTS idx_devices_user_device
ON devices (user_id, device_id);

ANALYZE delivery_events;
ANALYZE devices;
ANALYZE users;

EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
WITH delivered AS MATERIALIZED (
    SELECT d.device_id,
           d.message_id,
           d.sent_at
    FROM delivery_events AS d
    WHERE d.d_type = 'delivered'
),
read_pairs AS MATERIALIZED (
    SELECT DISTINCT
           r.device_id,
           r.message_id
    FROM delivery_events AS r
    WHERE r.d_type = 'read'
),
unread_by_user AS (
    SELECT dv.user_id,
           COUNT(*) AS unread_count,
           MAX(d.sent_at) AS last_unread
    FROM devices AS dv
    JOIN delivered AS d
      ON d.device_id = dv.device_id
    LEFT JOIN read_pairs AS r
      ON r.device_id = d.device_id
     AND r.message_id = d.message_id
    WHERE r.message_id IS NULL
    GROUP BY dv.user_id
    HAVING COUNT(*) >= 20
)
SELECT u.user_id,
       u.u_login,
       x.unread_count,
       x.last_unread
FROM unread_by_user AS x
JOIN users AS u
  ON u.user_id = x.user_id
WHERE u.a_status = 'active'
ORDER BY x.unread_count DESC;

/* ================================================================
   Доп, где индекс может не использоваться
   ================================================================ */

/*
  Индекс по d_type не гарантирует Index Scan.
  Если условие выбирает большую часть таблицы, Seq Scan может быть дешевле.
*/

CREATE INDEX IF NOT EXISTS idx_delivery_type_only
ON delivery_events (d_type);

ANALYZE delivery_events;

EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
SELECT *
FROM delivery_events
WHERE d_type = 'delivered';