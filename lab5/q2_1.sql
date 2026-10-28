--сообщения, которые не были доставлены в течение 30 дней после отправки
SELECT
    m.message_id,
    m.chat_id,
    m.author_id,
    m.sent_at,
    m.m_status,
    c.c_type,
    c.chat_name
FROM messages m
JOIN chats c
    ON c.chat_id = m.chat_id
LEFT JOIN delivery_events de
    ON de.message_id = m.message_id
    AND de.d_type = 'delivered'
WHERE de.event_id IS NULL
    AND m.m_status <> 'deleted'
    AND c.c_status = 'active'
    AND m.sent_at >= now() - INTERVAL '30 days'
ORDER BY
    m.sent_at DESC;