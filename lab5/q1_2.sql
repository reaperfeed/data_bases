-- топ-10 активных пользователей по устройствам, сессиям и сообщениям за 30 дней, с разбивкой по типу устройства и операционной системе
SELECT
    u.user_id,
    u.a_status,
    d.device_id,
    d.d_type,
    d.p_type,
	d.os_version,
    COUNT(DISTINCT s.session_id) AS sessions_count,
    COUNT(DISTINCT m.message_id) AS messages_count
FROM users u
JOIN devices d
    ON d.user_id = u.user_id
    AND d.d_status = 'connected'
LEFT JOIN sessions s
    ON s.user_id = u.user_id
	AND s.device_id = d.device_id
    AND s.s_status = 'active'
LEFT JOIN messages m
    ON m.author_id = u.user_id
    AND m.m_status <> 'deleted'
    AND m.sent_at >= now() - INTERVAL '30 days'
WHERE u.a_status = 'active'
GROUP BY
    u.user_id,
    u.a_status,
	d.device_id,
    d.d_type,
    d.p_type,
	d.os_version
HAVING
    COUNT(DISTINCT s.session_id) >= 1
    OR COUNT(DISTINCT m.message_id) >= 1
ORDER BY
    sessions_count DESC,
    messages_count DESC
FETCH FIRST 10 ROWS ONLY;