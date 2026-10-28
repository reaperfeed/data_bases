--активные чаты, в которых есть активные участники, сообщения и хотя бы какие-то реакции или жалобы
SELECT
    c.chat_id,
    c.c_type,
    c.chat_name,
    COUNT(DISTINCT cm.user_id) AS active_members_count,
    COUNT(DISTINCT m.message_id) AS messages_count,
    COUNT(DISTINCT r.message_id) AS messages_with_reactions_count,
    COUNT(DISTINCT comp.complaint_id) AS complaints_count
FROM chats c
JOIN chat_memberships cm
    ON cm.chat_id = c.chat_id
    AND cm.m_status = 'active'
JOIN messages m
    ON m.chat_id = c.chat_id
    AND NOT m.m_status = 'deleted'
LEFT JOIN reactions r  -- нарисовать как работает
    ON r.message_id = m.message_id
LEFT JOIN complaints comp
    ON comp.object_id = m.message_id
WHERE c.c_status = 'active'
GROUP BY
    c.chat_id,
    c.c_type,
    c.chat_name
HAVING
    COUNT(DISTINCT cm.user_id) >= 1
    AND COUNT(DISTINCT m.message_id) >= 1
    AND (COUNT(DISTINCT comp.complaint_id) >= 1 OR COUNT(DISTINCT r.message_id) >= 1)
ORDER BY
    complaints_count DESC,
    messages_count DESC;


    --A что-то
    --B null
    --C null
