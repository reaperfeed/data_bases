-- Тест 1. Триггер 1: успешная блокировка владельца двух чатов
-- готовим два чата с двумя администраторами и сессии владельца
BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO objects (object_id, o_type) VALUES
    ('68000000-0000-0000-0000-000000000001', 'user'),
    ('68000000-0000-0000-0000-000000000002', 'user'),
    ('68000000-0000-0000-0000-000000000100', 'chat'),
    ('68000000-0000-0000-0000-000000000101', 'chat');

INSERT INTO users (user_id, u_login, first_name, last_name, registration_date) VALUES
    ('68000000-0000-0000-0000-000000000001', 'lab6_min_1', 'Тест', '1', CURRENT_TIMESTAMP - INTERVAL '3 days'),
    ('68000000-0000-0000-0000-000000000002', 'lab6_min_2', 'Тест', '2', CURRENT_TIMESTAMP - INTERVAL '3 days');

INSERT INTO chats (chat_id, c_type, chat_name, creation_date) VALUES
    ('68000000-0000-0000-0000-000000000100', 'group', 'Тест: группа', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('68000000-0000-0000-0000-000000000101', 'channel', 'Тест: канал', CURRENT_TIMESTAMP - INTERVAL '2 days');

INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date) VALUES
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000002', 'admin', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000101', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000101', '68000000-0000-0000-0000-000000000002', 'admin', CURRENT_TIMESTAMP - INTERVAL '1 day');

-- добавляем завершённое членство для проверки учёта истории
INSERT INTO chat_memberships (chat_id, user_id, m_role, m_status, join_date, leave_date)
VALUES ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', 'admin', 'inactive',
        CURRENT_TIMESTAMP - INTERVAL '2 days', CURRENT_TIMESTAMP - INTERVAL '1 day');

INSERT INTO devices
    (device_id, user_id, d_type, p_type, os_version, registration_date, last_activity_date)
VALUES
    ('68000000-0000-0000-0000-000000000150', '68000000-0000-0000-0000-000000000001', 'phone_tablet', 'android', '15',
     CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP - INTERVAL '1 hour'),
    ('68000000-0000-0000-0000-000000000151', '68000000-0000-0000-0000-000000000001', 'computer_laptop', 'linux', '6',
     CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP - INTERVAL '30 minutes');

INSERT INTO sessions (session_id, user_id, device_id, s_status, start_time, end_time) VALUES
    ('68000000-0000-0000-0000-000000000400', '68000000-0000-0000-0000-000000000001', '68000000-0000-0000-0000-000000000150', 'active', CURRENT_TIMESTAMP - INTERVAL '1 hour', NULL),
    ('68000000-0000-0000-0000-000000000401', '68000000-0000-0000-0000-000000000001', '68000000-0000-0000-0000-000000000151', 'active', CURRENT_TIMESTAMP - INTERVAL '30 minutes', NULL),
    ('68000000-0000-0000-0000-000000000402', '68000000-0000-0000-0000-000000000001', '68000000-0000-0000-0000-000000000150', 'inactive',
     CURRENT_TIMESTAMP - INTERVAL '23 hours', CURRENT_TIMESTAMP - INTERVAL '22 hours');

-- блокируем владельца; в каждом чате остаётся второй администратор
UPDATE users
SET a_status = 'blocked'
WHERE user_id = '68000000-0000-0000-0000-000000000001';

-- проверяем статусы: первый blocked, второй active
SELECT u_login, a_status
FROM users
WHERE user_id IN ('68000000-0000-0000-0000-000000000001', '68000000-0000-0000-0000-000000000002')
ORDER BY user_id;

-- проверяем: две сессии закрыты, старая завершённая не изменилась
SELECT session_id, s_status, start_time, end_time
FROM sessions
WHERE user_id = '68000000-0000-0000-0000-000000000001'
ORDER BY session_id;

-- проверяем, что история активности устройств сохранена
SELECT device_id, last_activity_date
FROM devices
WHERE user_id = '68000000-0000-0000-0000-000000000001'
ORDER BY device_id;

-- проверяем три записи аудита: блокировка и два принудительных выхода
SELECT additional_info
FROM audits
WHERE object_id = '68000000-0000-0000-0000-000000000001'
ORDER BY additional_info;

-- отменяем изменения и тестовые данные
ROLLBACK;


-- Тест 2. Триггер 1: запрет блокировки обоих администраторов
-- готовим чат с двумя действующими администраторами
BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO objects (object_id, o_type) VALUES
    ('68000000-0000-0000-0000-000000000001', 'user'),
    ('68000000-0000-0000-0000-000000000002', 'user'),
    ('68000000-0000-0000-0000-000000000100', 'chat');

INSERT INTO users (user_id, u_login, first_name, last_name, registration_date) VALUES
    ('68000000-0000-0000-0000-000000000001', 'lab6_min_1', 'Тест', '1', CURRENT_TIMESTAMP - INTERVAL '3 days'),
    ('68000000-0000-0000-0000-000000000002', 'lab6_min_2', 'Тест', '2', CURRENT_TIMESTAMP - INTERVAL '3 days');

INSERT INTO chats (chat_id, c_type, chat_name, creation_date) VALUES
    ('68000000-0000-0000-0000-000000000100', 'group', 'Тест: два администратора', CURRENT_TIMESTAMP - INTERVAL '2 days');

INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date) VALUES
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000002', 'admin', CURRENT_TIMESTAMP - INTERVAL '1 day');

-- пытаемся заблокировать обоих администраторов одним UPDATE
UPDATE users
SET a_status = 'blocked'
WHERE user_id IN ('68000000-0000-0000-0000-000000000001', '68000000-0000-0000-0000-000000000002');

-- ожидаем ошибку: чат останется без администратора
-- после ошибки выполняем откат отдельной командой
ROLLBACK;


-- Тест 3. Триггер 2: правильная последовательность доставки
-- готовим сообщение, членство получателя и его устройство
BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO objects (object_id, o_type) VALUES
    ('68000000-0000-0000-0000-000000000001', 'user'),
    ('68000000-0000-0000-0000-000000000002', 'user'),
    ('68000000-0000-0000-0000-000000000100', 'chat'),
    ('68000000-0000-0000-0000-000000000200', 'message');

INSERT INTO users (user_id, u_login, first_name, last_name, registration_date) VALUES
    ('68000000-0000-0000-0000-000000000001', 'lab6_min_1', 'Тест', '1', CURRENT_TIMESTAMP - INTERVAL '3 days'),
    ('68000000-0000-0000-0000-000000000002', 'lab6_min_2', 'Тест', '2', CURRENT_TIMESTAMP - INTERVAL '3 days');

INSERT INTO chats (chat_id, c_type, chat_name, creation_date) VALUES
    ('68000000-0000-0000-0000-000000000100', 'group', 'Тест: доставка', CURRENT_TIMESTAMP - INTERVAL '2 days');

INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date) VALUES
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000002', 'member', CURRENT_TIMESTAMP - INTERVAL '1 day');

INSERT INTO devices (device_id, user_id, d_type, p_type, os_version, registration_date)
VALUES ('68000000-0000-0000-0000-000000000150', '68000000-0000-0000-0000-000000000002', 'phone_tablet', 'android', '15',
        CURRENT_TIMESTAMP - INTERVAL '8 minutes');

INSERT INTO messages (message_id, chat_id, author_id, sent_at) VALUES
    ('68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP - INTERVAL '10 minutes');

-- добавляем три стадии одним INSERT в обратном порядке
INSERT INTO delivery_events
    (event_id, message_id, device_id, previous_event_id, sent_at, d_type)
VALUES
    ('68000000-0000-0000-0000-000000000712', '68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000150', '68000000-0000-0000-0000-000000000711',
     CURRENT_TIMESTAMP - INTERVAL '3 minutes', 'read'),
    ('68000000-0000-0000-0000-000000000710', '68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000150', NULL,
     CURRENT_TIMESTAMP - INTERVAL '5 minutes', 'received_by_server'),
    ('68000000-0000-0000-0000-000000000711', '68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000150', '68000000-0000-0000-0000-000000000710',
     CURRENT_TIMESTAMP - INTERVAL '4 minutes', 'delivered');

-- проверяем три стадии по времени: приём, доставка, чтение
-- у первой стадии ссылка NULL, у остальных - на предыдущую стадию
SELECT d_type, sent_at, previous_event_id
FROM delivery_events
WHERE message_id = '68000000-0000-0000-0000-000000000200'
  AND device_id = '68000000-0000-0000-0000-000000000150'
ORDER BY sent_at;

-- отменяем изменения и тестовые данные
ROLLBACK;


-- Тест 4. Триггер 2: чтение без предыдущих стадий
-- готовим два сообщения и устройство получателя
BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO objects (object_id, o_type) VALUES
    ('68000000-0000-0000-0000-000000000001', 'user'),
    ('68000000-0000-0000-0000-000000000002', 'user'),
    ('68000000-0000-0000-0000-000000000100', 'chat'),
    ('68000000-0000-0000-0000-000000000200', 'message'),
    ('68000000-0000-0000-0000-000000000201', 'message');

INSERT INTO users (user_id, u_login, first_name, last_name, registration_date) VALUES
    ('68000000-0000-0000-0000-000000000001', 'lab6_min_1', 'Тест', '1', CURRENT_TIMESTAMP - INTERVAL '3 days'),
    ('68000000-0000-0000-0000-000000000002', 'lab6_min_2', 'Тест', '2', CURRENT_TIMESTAMP - INTERVAL '3 days');

INSERT INTO chats (chat_id, c_type, chat_name, creation_date) VALUES
    ('68000000-0000-0000-0000-000000000100', 'group', 'Тест: доставка', CURRENT_TIMESTAMP - INTERVAL '2 days');

INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date) VALUES
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000002', 'member', CURRENT_TIMESTAMP - INTERVAL '1 day');

INSERT INTO devices (device_id, user_id, d_type, p_type, os_version, registration_date)
VALUES ('68000000-0000-0000-0000-000000000150', '68000000-0000-0000-0000-000000000002', 'phone_tablet', 'android', '15',
        CURRENT_TIMESTAMP - INTERVAL '8 minutes');

INSERT INTO messages (message_id, chat_id, author_id, sent_at) VALUES
    ('68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP - INTERVAL '10 minutes'),
    ('68000000-0000-0000-0000-000000000201', '68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP - INTERVAL '10 minutes');

-- добавляем корректный приём и чтение другого сообщения без предыдущих стадий
INSERT INTO delivery_events (event_id, message_id, device_id, sent_at, d_type)
VALUES
    ('68000000-0000-0000-0000-000000000720', '68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000150',
     CURRENT_TIMESTAMP - INTERVAL '5 minutes', 'received_by_server'),
    ('68000000-0000-0000-0000-000000000721', '68000000-0000-0000-0000-000000000201', '68000000-0000-0000-0000-000000000150',
     CURRENT_TIMESTAMP - INTERVAL '4 minutes', 'read');

-- ожидаем ошибку последовательности; весь INSERT отменяется
-- после ошибки выполняем откат отдельной командой
ROLLBACK;


-- Тест 5. Процедура 1: пакетное редактирование сообщений
-- готовим сообщения группы и канала, их автора и исходные версии
BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO objects (object_id, o_type) VALUES
    ('68000000-0000-0000-0000-000000000001', 'user'),
    ('68000000-0000-0000-0000-000000000100', 'chat'),
    ('68000000-0000-0000-0000-000000000101', 'chat'),
    ('68000000-0000-0000-0000-000000000200', 'message'),
    ('68000000-0000-0000-0000-000000000201', 'message');

INSERT INTO users (user_id, u_login, first_name, last_name, registration_date) VALUES
    ('68000000-0000-0000-0000-000000000001', 'lab6_min_1', 'Тест', '1', CURRENT_TIMESTAMP - INTERVAL '3 days');

INSERT INTO chats (chat_id, c_type, chat_name, creation_date) VALUES
    ('68000000-0000-0000-0000-000000000100', 'group', 'Тест: группа', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('68000000-0000-0000-0000-000000000101', 'channel', 'Тест: канал', CURRENT_TIMESTAMP - INTERVAL '2 days');

INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date) VALUES
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000101', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day');

INSERT INTO messages (message_id, chat_id, author_id, sent_at) VALUES
    ('68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP - INTERVAL '10 minutes'),
    ('68000000-0000-0000-0000-000000000201', '68000000-0000-0000-0000-000000000101', '68000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP - INTERVAL '10 minutes');

INSERT INTO version_of_messages
    (message_id, version_number, content, created_at, editor_id)
VALUES
    ('68000000-0000-0000-0000-000000000200', 0, 'Первоначальный текст группы', CURRENT_TIMESTAMP - INTERVAL '10 minutes', '68000000-0000-0000-0000-000000000001'),
    ('68000000-0000-0000-0000-000000000201', 0, 'Первоначальный текст канала', CURRENT_TIMESTAMP - INTERVAL '10 minutes', '68000000-0000-0000-0000-000000000001');

-- изменяем два сообщения от имени автора
CALL edit_messages_batch(
    '68000000-0000-0000-0000-000000000001',
    ARRAY['68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000201']::uuid[],
    ARRAY[0, 0]::bigint[],
    ARRAY['Исправленный текст группы', 'Исправленный текст канала']
);

-- проверяем четыре редакции: версии 0 и 1 для каждого сообщения
SELECT message_id, version_number, content
FROM version_of_messages
WHERE message_id IN ('68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000201')
ORDER BY message_id, version_number;

-- проверяем статус edited у обоих сообщений
SELECT message_id, m_status
FROM messages
WHERE message_id IN ('68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000201')
ORDER BY message_id;

-- проверяем две записи аудита о создании версии 1
SELECT object_id, additional_info
FROM audits
WHERE object_id IN ('68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000201')
ORDER BY object_id;

-- отменяем изменения и тестовые данные
ROLLBACK;


-- Тест 6. Процедура 1: устаревшая версия второго сообщения
-- готовим сообщения группы и канала, их автора и исходные версии
BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO objects (object_id, o_type) VALUES
    ('68000000-0000-0000-0000-000000000001', 'user'),
    ('68000000-0000-0000-0000-000000000100', 'chat'),
    ('68000000-0000-0000-0000-000000000101', 'chat'),
    ('68000000-0000-0000-0000-000000000200', 'message'),
    ('68000000-0000-0000-0000-000000000201', 'message');

INSERT INTO users (user_id, u_login, first_name, last_name, registration_date) VALUES
    ('68000000-0000-0000-0000-000000000001', 'lab6_min_1', 'Тест', '1', CURRENT_TIMESTAMP - INTERVAL '3 days');

INSERT INTO chats (chat_id, c_type, chat_name, creation_date) VALUES
    ('68000000-0000-0000-0000-000000000100', 'group', 'Тест: группа', CURRENT_TIMESTAMP - INTERVAL '2 days'),
    ('68000000-0000-0000-0000-000000000101', 'channel', 'Тест: канал', CURRENT_TIMESTAMP - INTERVAL '2 days');

INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date) VALUES
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000101', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day');

INSERT INTO messages (message_id, chat_id, author_id, sent_at) VALUES
    ('68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP - INTERVAL '10 minutes'),
    ('68000000-0000-0000-0000-000000000201', '68000000-0000-0000-0000-000000000101', '68000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP - INTERVAL '10 minutes');

INSERT INTO version_of_messages
    (message_id, version_number, content, created_at, editor_id)
VALUES
    ('68000000-0000-0000-0000-000000000200', 0, 'Первоначальный текст группы', CURRENT_TIMESTAMP - INTERVAL '10 minutes', '68000000-0000-0000-0000-000000000001'),
    ('68000000-0000-0000-0000-000000000201', 0, 'Первоначальный текст канала', CURRENT_TIMESTAMP - INTERVAL '10 minutes', '68000000-0000-0000-0000-000000000001');

-- передаём неверный ожидаемый номер 99 для второго сообщения
CALL edit_messages_batch(
    '68000000-0000-0000-0000-000000000001',
    ARRAY['68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000201']::uuid[],
    ARRAY[0, 99]::bigint[],
    ARRAY['Первая правка тоже должна отмениться', 'Неверный номер версии']
);

-- ожидаем ошибку версии; весь CALL отменяется
-- после ошибки выполняем откат отдельной командой
ROLLBACK;


-- Тест 7. Процедура 2: общая санкция по двум жалобам
-- готовим сообщение, модератора и две жалобы
BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO objects (object_id, o_type) VALUES
    ('68000000-0000-0000-0000-000000000001', 'user'),
    ('68000000-0000-0000-0000-000000000002', 'user'),
    ('68000000-0000-0000-0000-000000000003', 'user'),
    ('68000000-0000-0000-0000-000000000100', 'chat'),
    ('68000000-0000-0000-0000-000000000200', 'message');

INSERT INTO users (user_id, u_login, first_name, last_name, registration_date) VALUES
    ('68000000-0000-0000-0000-000000000001', 'lab6_min_1', 'Тест', '1', CURRENT_TIMESTAMP - INTERVAL '3 days'),
    ('68000000-0000-0000-0000-000000000002', 'lab6_min_2', 'Тест', '2', CURRENT_TIMESTAMP - INTERVAL '3 days'),
    ('68000000-0000-0000-0000-000000000003', 'lab6_min_3', 'Тест', '3', CURRENT_TIMESTAMP - INTERVAL '3 days');

INSERT INTO chats (chat_id, c_type, chat_name, creation_date) VALUES
    ('68000000-0000-0000-0000-000000000100', 'group', 'Тест: жалобы', CURRENT_TIMESTAMP - INTERVAL '2 days');

INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date) VALUES
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000002', 'member', CURRENT_TIMESTAMP - INTERVAL '1 day');

-- назначаем пользователя 3 модератором служебного чата
INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date)
VALUES ('60000000-0000-0000-0000-000000000006', '68000000-0000-0000-0000-000000000003', 'admin', CURRENT_TIMESTAMP);

INSERT INTO messages (message_id, chat_id, author_id, sent_at) VALUES
    ('68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP - INTERVAL '10 minutes');

INSERT INTO version_of_messages
    (message_id, version_number, content, created_at, editor_id)
VALUES
    ('68000000-0000-0000-0000-000000000200', 0, 'Исходный текст сообщения', CURRENT_TIMESTAMP - INTERVAL '10 minutes', '68000000-0000-0000-0000-000000000001');

INSERT INTO complaints (complaint_id, object_id, complainant_id, description) VALUES
    ('68000000-0000-0000-0000-000000000300', '68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000002', 'Первая жалоба на сообщение'),
    ('68000000-0000-0000-0000-000000000301', '68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000002', 'Вторая жалоба на сообщение');

-- рассматриваем обе жалобы и ограничиваем сообщение
CALL review_complaints_batch(
    '68000000-0000-0000-0000-000000000003',
    ARRAY['68000000-0000-0000-0000-000000000300', '68000000-0000-0000-0000-000000000301']::uuid[],
    'restrict_message',
    'Жалобы подтверждены: ограничить доступ к сообщению'
);

-- проверяем статус reviewed у обеих жалоб
SELECT complaint_id, c_status
FROM complaints
WHERE complaint_id IN ('68000000-0000-0000-0000-000000000300', '68000000-0000-0000-0000-000000000301')
ORDER BY complaint_id;

-- проверяем два выполненных решения restrict_message
SELECT complaint_id, d_type, d_status
FROM decisions
WHERE complaint_id IN ('68000000-0000-0000-0000-000000000300', '68000000-0000-0000-0000-000000000301')
ORDER BY complaint_id;

-- проверяем одну общую санкцию на сообщение
SELECT COUNT(*) AS action_count
FROM admin_actions
WHERE object_id = '68000000-0000-0000-0000-000000000200';

-- проверяем сохранение исходной версии: одна запись
SELECT COUNT(*) AS stored_version_count
FROM version_of_messages
WHERE message_id = '68000000-0000-0000-0000-000000000200';

-- проверяем скрытие текста: ноль записей в представлении
SELECT COUNT(*) AS visible_version_count
FROM lab6_visible_versions
WHERE message_id = '68000000-0000-0000-0000-000000000200';

-- отменяем изменения и тестовые данные
ROLLBACK;


-- Тест 8. Процедура 2: конфликт интересов модератора
-- готовим модератора и жалобы на его административное действие
BEGIN ISOLATION LEVEL READ COMMITTED;

INSERT INTO objects (object_id, o_type) VALUES
    ('68000000-0000-0000-0000-000000000001', 'user'),
    ('68000000-0000-0000-0000-000000000002', 'user'),
    ('68000000-0000-0000-0000-000000000003', 'user'),
    ('68000000-0000-0000-0000-000000000100', 'chat'),
    ('68000000-0000-0000-0000-000000000200', 'message'),
    ('68000000-0000-0000-0000-000000000600', 'admin_action');

INSERT INTO users (user_id, u_login, first_name, last_name, registration_date) VALUES
    ('68000000-0000-0000-0000-000000000001', 'lab6_min_1', 'Тест', '1', CURRENT_TIMESTAMP - INTERVAL '3 days'),
    ('68000000-0000-0000-0000-000000000002', 'lab6_min_2', 'Тест', '2', CURRENT_TIMESTAMP - INTERVAL '3 days'),
    ('68000000-0000-0000-0000-000000000003', 'lab6_min_3', 'Тест', '3', CURRENT_TIMESTAMP - INTERVAL '3 days');

INSERT INTO chats (chat_id, c_type, chat_name, creation_date) VALUES
    ('68000000-0000-0000-0000-000000000100', 'group', 'Тест: жалобы', CURRENT_TIMESTAMP - INTERVAL '2 days');

INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date) VALUES
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', 'owner', CURRENT_TIMESTAMP - INTERVAL '1 day'),
    ('68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000002', 'member', CURRENT_TIMESTAMP - INTERVAL '1 day');

-- назначаем пользователя 3 модератором служебного чата
INSERT INTO chat_memberships (chat_id, user_id, m_role, join_date)
VALUES ('60000000-0000-0000-0000-000000000006', '68000000-0000-0000-0000-000000000003', 'admin', CURRENT_TIMESTAMP);

INSERT INTO messages (message_id, chat_id, author_id, sent_at) VALUES
    ('68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000100', '68000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP - INTERVAL '10 minutes');

INSERT INTO version_of_messages
    (message_id, version_number, content, created_at, editor_id)
VALUES
    ('68000000-0000-0000-0000-000000000200', 0, 'Исходный текст сообщения', CURRENT_TIMESTAMP - INTERVAL '10 minutes', '68000000-0000-0000-0000-000000000001');

-- создаём административное действие модератора 3
INSERT INTO complaints (complaint_id, object_id, complainant_id, description, c_status)
VALUES ('68000000-0000-0000-0000-000000000300', '68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000002', 'Первоначальная жалоба', 'reviewed');

INSERT INTO decisions (decision_id, object_id, user_id, complaint_id, d_type, d_status)
VALUES ('68000000-0000-0000-0000-000000000601', '68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000003', '68000000-0000-0000-0000-000000000300',
        'reject_complaint', 'executed');

INSERT INTO admin_actions (action_id, object_id, user_id, decision_id, action_type, reason)
VALUES ('68000000-0000-0000-0000-000000000600', '68000000-0000-0000-0000-000000000200', '68000000-0000-0000-0000-000000000003', '68000000-0000-0000-0000-000000000601',
        'change_access', 'Существующее действие модератора 3');

-- добавляем две жалобы на это действие
INSERT INTO complaints (complaint_id, object_id, complainant_id, description) VALUES
    ('68000000-0000-0000-0000-000000000301', '68000000-0000-0000-0000-000000000600', '68000000-0000-0000-0000-000000000001', 'Первая жалоба на действие'),
    ('68000000-0000-0000-0000-000000000302', '68000000-0000-0000-0000-000000000600', '68000000-0000-0000-0000-000000000002', 'Вторая жалоба на действие');

-- пытаемся отклонить жалобы от имени исполнителя действия
CALL review_complaints_batch(
    '68000000-0000-0000-0000-000000000003',
    ARRAY['68000000-0000-0000-0000-000000000301', '68000000-0000-0000-0000-000000000302']::uuid[],
    'reject_complaint',
    'Попытка отклонить жалобы на своё действие'
);

-- ожидаем ошибку конфликта интересов
-- после ошибки выполняем откат отдельной командой
ROLLBACK;
