-- выводим сведения об устройствах и их владельцах
SELECT
    u.user_id,
    u.u_login,
    d.device_id,
    d.d_type,
    d.p_type,
    d.registration_date,
    d.last_activity_date,
    -- считаем полные сутки с момента последней активности
    FLOOR(
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - d.last_activity_date))
        / 86400
    )::integer AS days_since_last_use
FROM devices AS d
JOIN users AS u ON u.user_id = d.user_id
WHERE u.a_status <> 'blocked'
  -- проверяем отсутствие входов с этого устройства за последние 30 дней
  AND NOT EXISTS (
      SELECT 1
      FROM sessions AS s
      WHERE s.user_id = u.user_id
      	AND s.device_id = d.device_id
      	AND s.start_time >= CURRENT_TIMESTAMP - INTERVAL '30 days'
  )
  -- проверяем наличие входа того же пользователя с другого устройства
  AND EXISTS (
      SELECT 1
      FROM sessions AS s
      WHERE s.user_id = u.user_id
        AND s.device_id <> d.device_id
        AND s.start_time >= CURRENT_TIMESTAMP - INTERVAL '30 days'
  )
ORDER BY u.user_id, d.device_id;