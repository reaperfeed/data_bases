BEGIN;
SET LOCAL search_path = public, pg_temp; -- Указываем в каких схемах Постгрес будет искать таблицы

DROP TRIGGER IF EXISTS lab6_guard ON objects; -- Убираем guard для вставки служебного чата и создания функций
DROP TRIGGER IF EXISTS lab6_guard ON chats;

-- проверяем, что UUID служебного чата не занят
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM objects o
        LEFT JOIN chats ch ON ch.chat_id = o.object_id
        WHERE o.object_id = '60000000-0000-0000-0000-000000000006'
          AND (
              o.o_type <> 'chat'
              OR ch.chat_id IS NULL
              OR ch.c_type <> 'group'
              OR ch.chat_name IS NULL
              OR ch.chat_name <> 'superusers'
              OR ch.c_status <> 'archived'
          )
    ) THEN
        RAISE EXCEPTION
            'UUID служебного чата занят другим объектом или чат имеет неверные параметры';
    END IF;
END;
$$;

-- Создаем служебный чат модераторов системы (условная группа sudo)
-- Служебный чат: admin = модератор, owner = старший модератор.
-- Эта же строка служит общим местом захвата блокировки FOR UPDATE.
INSERT INTO objects (object_id, o_type)
SELECT '60000000-0000-0000-0000-000000000006'::uuid, 'chat'::object_type
WHERE NOT EXISTS (
    SELECT 1 FROM objects
    WHERE object_id = '60000000-0000-0000-0000-000000000006'
);
INSERT INTO chats (chat_id, c_type, chat_name, c_status)
SELECT '60000000-0000-0000-0000-000000000006'::uuid,
       'group'::chat_type, 'superusers', 'archived'::chat_status
WHERE NOT EXISTS (
    SELECT 1 FROM chats
    WHERE chat_id = '60000000-0000-0000-0000-000000000006'
);

-- Порядок захвата: сначала служебный чат, затем строки операции.
-- READ COMMITTED нужен, чтобы после ожидания видеть зафиксированные изменения.
CREATE OR REPLACE FUNCTION lab6_lock() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Требуется поддержка уровня READ COMMITTED';
    END IF;
    PERFORM 1
    FROM chats
    WHERE chat_id = '60000000-0000-0000-0000-000000000006'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Не найден служебный чат: выполните 00_support.sql';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION lab6_staff_role(p_user uuid, p_at timestamptz)
RETURNS member_role LANGUAGE sql AS $$
    SELECT cm.m_role
    FROM chat_memberships cm
    JOIN users u ON u.user_id = cm.user_id
    WHERE cm.chat_id = '60000000-0000-0000-0000-000000000006'
      	AND cm.user_id = p_user
      	AND u.a_status = 'active'
      	AND cm.m_role IN ('admin', 'owner')
      	AND cm.m_status = 'active'
      	AND cm.join_date <= p_at
      	AND (cm.leave_date IS NULL OR p_at < cm.leave_date)
    ORDER BY CASE cm.m_role WHEN 'owner' THEN 0 ELSE 1 END
    LIMIT 1
$$;

-- В лабе ограничение сообщения бессрочно; отмена санкции не входит в задание.
CREATE OR REPLACE FUNCTION lab6_message_restricted(p_message uuid, p_at timestamptz)
RETURNS boolean LANGUAGE sql AS $$
    SELECT EXISTS (
        SELECT 1
        FROM decisions d
        WHERE d.object_id = p_message
          	AND d.d_type = 'restrict_message'
          	AND d.d_status = 'executed'
          	AND d.executed_at <= p_at
    )
$$;

-- Временное ограничение пользователя запрещает публикацию и редактирование.
-- a_status не меняется: иначе после истечения срока нужна была бы разблокировка.
CREATE OR REPLACE FUNCTION lab6_user_restricted(p_user uuid, p_at timestamptz)
RETURNS boolean LANGUAGE sql AS $$
    SELECT EXISTS (
        SELECT 1
        FROM admin_actions a
        JOIN decisions d ON d.decision_id = a.decision_id
        WHERE a.object_id = p_user
          	AND a.action_type = 'restrict'
          	AND d.d_type = 'temporarily_restrict_user'
          	AND d.d_status = 'executed'
          	AND a.executed_at <= p_at
          	AND p_at < a.executed_at + a.duration
    )
$$;

-- При чтении приложение использует эти представления; история не удаляется.
CREATE OR REPLACE VIEW lab6_visible_versions AS
SELECT v.*
FROM version_of_messages v
WHERE NOT lab6_message_restricted(v.message_id, clock_timestamp());

CREATE OR REPLACE VIEW lab6_visible_attachments AS
SELECT a.*
FROM attachments a
WHERE NOT lab6_message_restricted(a.message_id, clock_timestamp());

CREATE OR REPLACE VIEW lab6_visible_representations AS
SELECT r.*
FROM attachment_representations r
JOIN attachments a ON a.attachment_id = r.attachment_id
WHERE NOT lab6_message_restricted(a.message_id, clock_timestamp());

-- Возвращаем защиту после подготовки всех её зависимостей.
CREATE OR REPLACE FUNCTION lab6_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM lab6_lock();
    RETURN NULL;
END;
$$;

CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON objects
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON chats
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();

COMMIT;
