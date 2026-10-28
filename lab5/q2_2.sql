--вложения, у которых нет готовых представлений
SELECT
    a.attachment_id,
	m.message_id,
    a.a_type,
	a.a_status,
	ar.attachment_id
FROM attachments a
JOIN messages m
    ON a.message_id = m.message_id
	AND a.a_status = 'uploaded'
	AND m.m_status <> 'deleted'
LEFT JOIN attachment_representations ar
    ON ar.attachment_id = a.attachment_id
	AND ar.r_status = 'ready'
WHERE ar.attachment_id IS NULL
ORDER BY
    a.attachment_id,
	m.message_id;
	