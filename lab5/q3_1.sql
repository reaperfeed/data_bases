-- сбор статистики по сообщениям
WITH message_stats AS (
    SELECT
        m.chat_id,
        COUNT(*) AS message_count,
        COUNT(DISTINCT m.author_id) AS author_count
    FROM messages m
    WHERE m.sent_at >= TIMESTAMPTZ '2026-08-01 00:00:00+03'
        AND m.sent_at <  TIMESTAMPTZ '2026-09-01 00:00:00+03'
    GROUP BY m.chat_id
),
-- Выбираем жалобы, имеющие решения по ним
complaint_flags AS (
    SELECT
        m.chat_id,
        c.complaint_id,
        EXISTS (
            SELECT 1
            FROM decisions AS d
            WHERE d.complaint_id = c.complaint_id
            	AND d.d_status = 'executed'
            	AND d.d_type IN (
                  'restrict_message',
                  'temporarily_restrict_user'
              	)
        ) AS restrictive_action
    FROM complaints AS c
    JOIN objects o ON o.object_id = c.object_id
		AND o.o_type = 'message'
    JOIN messages m ON m.message_id = c.object_id
    WHERE c.filed_at >= TIMESTAMPTZ '2026-08-01 00:00:00+03'
      	AND c.filed_at <  TIMESTAMPTZ '2026-09-01 00:00:00+03'
),
-- Собираем статистику по жалобам: все и которые имеют решения
complaint_stats AS (
    SELECT
        chat_id,
        COUNT(*) AS complaint_count,
        COUNT(*) FILTER (
            WHERE restrictive_action
        ) AS restricted_complaint_count
    FROM complaint_flags
    GROUP BY chat_id
),
-- объединяем сведения о чатах со статистикой сообщений и жалоб
eligible_chats AS (
    SELECT
        ch.chat_id,
        ch.chat_name,
        ms.message_count,
        ms.author_count,
        cs.complaint_count,
        cs.restricted_complaint_count,
        cs.restricted_complaint_count::numeric
            / cs.complaint_count AS restrictive_share
    FROM chats ch
    JOIN message_stats ms ON ms.chat_id = ch.chat_id
    JOIN complaint_stats cs ON cs.chat_id = ch.chat_id
    WHERE ms.message_count >= 20
      	AND cs.complaint_count >= 5
)
-- выводим чаты с максимальным числом жалоб
SELECT
    chat_id,
    chat_name,
    message_count,
    author_count,
    complaint_count,
    restrictive_share
FROM eligible_chats
WHERE complaint_count = (
    SELECT MAX(complaint_count)
    FROM eligible_chats
)
ORDER BY restrictive_share DESC;