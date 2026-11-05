BEGIN;
SET LOCAL search_path = public, pg_temp;

DROP TRIGGER IF EXISTS lab6_guard ON objects;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON objects
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON users;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON users
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON devices;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON devices
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON sessions;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON sessions
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON chats;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON chats
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON chat_memberships;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON chat_memberships
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON messages;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON messages
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON version_of_messages;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON version_of_messages
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON attachments;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON attachments
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON attachment_representations;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON attachment_representations
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON delivery_events;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON delivery_events
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON complaints;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON complaints
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON decisions;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON decisions
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON admin_actions;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON admin_actions
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();
DROP TRIGGER IF EXISTS lab6_guard ON audits;
CREATE TRIGGER lab6_guard BEFORE INSERT OR UPDATE OR DELETE ON audits
FOR EACH STATEMENT EXECUTE FUNCTION lab6_guard();

-- ТРИГГЕР 1: совокупный результат блокировки всех строк одного UPDATE.
CREATE OR REPLACE FUNCTION lab6_block_user() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_now timestamptz := clock_timestamp();		-- момент запуска
    v_chat uuid;								-- id проблемного чата
    v_batch uuid := gen_random_uuid();			-- id действия
BEGIN
	-- Если есть пользователи, которые дейстивительно были заблокированы, то продолжаем
    IF NOT EXISTS (
        SELECT 1
        FROM new_users n
        JOIN old_users o ON o.user_id = n.user_id
        WHERE n.a_status = 'blocked'
          	AND o.a_status <> n.a_status
    ) THEN
        RETURN NULL;
    END IF;

    -- Затронутый активный чат имеет участников, но больше не имеет администратора.
    SELECT ch.chat_id INTO v_chat
    FROM chats ch
    WHERE ch.c_status = 'active'
      AND ch.c_type IN ('group', 'channel')
	  -- В чате кого то заблокировали
      AND EXISTS (
          SELECT 1
          FROM chat_memberships cm
          JOIN new_users n ON n.user_id = cm.user_id
          JOIN old_users o ON o.user_id = n.user_id
          WHERE cm.chat_id = ch.chat_id
          	AND n.a_status = 'blocked'
          	AND o.a_status <> n.a_status
          	AND cm.m_status = 'active'
           	AND cm.join_date <= v_now
           	AND (cm.leave_date IS NULL OR v_now < cm.leave_date)
      )
	  -- При этом в чате кто-то остался
      AND EXISTS (
          SELECT 1
          FROM chat_memberships cm
          JOIN users u ON u.user_id = cm.user_id
          WHERE cm.chat_id = ch.chat_id
            AND u.a_status <> 'deleted'
            AND cm.m_status = 'active'
            AND cm.join_date <= v_now
            AND (cm.leave_date IS NULL OR v_now < cm.leave_date)
      )
	  -- Но чат остался без администратора :(
      AND NOT EXISTS (
          SELECT 1
          FROM chat_memberships cm
          JOIN users u ON u.user_id = cm.user_id
          WHERE cm.chat_id = ch.chat_id
            AND u.a_status = 'active'
            AND cm.m_role IN ('admin', 'owner')
            AND cm.m_status = 'active'
            AND cm.join_date <= v_now
            AND (cm.leave_date IS NULL OR v_now < cm.leave_date)
      )
    ORDER BY ch.chat_id
    LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'Блокировка оставляет чат % без администратора', v_chat;
    END IF;

	-- Проверяем что нет активных сессий после бана
    IF EXISTS (
        SELECT 1
        FROM sessions s
        JOIN new_users n ON n.user_id = s.user_id
        JOIN old_users o ON o.user_id = n.user_id
        WHERE n.a_status = 'blocked'
          AND o.a_status <> n.a_status
          AND s.s_status = 'active'
          AND s.start_time >= v_now
    ) THEN
        RAISE EXCEPTION 'Время начала активной сессии должно предшествовать блокировке';
    END IF;

    -- RETURNING даёт именно те сессии, которые были закрыты сейчас.
    WITH ended AS (
        UPDATE sessions s
        SET s_status = 'inactive',
            end_time = v_now
        FROM new_users n
        JOIN old_users o ON o.user_id = n.user_id
        WHERE s.user_id = n.user_id
          AND s.s_status = 'active'
          AND n.a_status = 'blocked'
          AND o.a_status <> n.a_status
        RETURNING s.session_id, s.user_id
    )
    INSERT INTO audits (object_id, user_id, was_at, result, additional_info)
    SELECT user_id, user_id, v_now, 'success',
           'session_forced_end; session_id=' || session_id::text ||
           '; reason=account_blocked; batch=' || v_batch::text ||
           '; db_actor=' || session_user
    FROM ended;

    INSERT INTO audits (object_id, user_id, was_at, result, additional_info)
    SELECT n.user_id, n.user_id, v_now, 'success',
           'user_blocked; batch=' || v_batch::text || '; db_actor=' || session_user
    FROM new_users n
    JOIN old_users o ON o.user_id = n.user_id
    WHERE n.a_status = 'blocked'
      	AND o.a_status <> n.a_status;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS lab6_block_user ON users;
CREATE TRIGGER lab6_block_user AFTER UPDATE ON users
REFERENCING OLD TABLE AS old_users NEW TABLE AS new_users
FOR EACH STATEMENT EXECUTE FUNCTION lab6_block_user();

-- Мониторинг сессий - добавление новых и завершение старых.
CREATE OR REPLACE FUNCTION lab6_check_session() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM devices
        WHERE device_id = NEW.device_id
          AND user_id = NEW.user_id
    ) THEN
        RAISE EXCEPTION 'Устройство не принадлежит пользователю сессии';
    END IF;
    IF NEW.s_status = 'active' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM users
            WHERE user_id = NEW.user_id
              AND a_status = 'active'
        ) THEN
            RAISE EXCEPTION 'Для входа нужна активная учётная запись';
        END IF;
        IF NEW.end_time IS NOT NULL THEN
            RAISE EXCEPTION 'У активной сессии end_time должен быть NULL';
        END IF;
    ELSIF TG_OP = 'UPDATE' AND OLD.s_status = 'active' THEN
        IF NEW.end_time IS NULL THEN
            RAISE EXCEPTION 'Для завершения сессии укажите end_time';
        END IF;
        IF EXISTS (
            SELECT 1
            FROM users
            WHERE user_id = NEW.user_id
              AND a_status = 'active'
        ) THEN
            INSERT INTO audits (object_id, user_id, result, additional_info)
            VALUES (NEW.user_id, NEW.user_id, 'success',
                    'session_end; session_id=' || NEW.session_id::text ||
                    '; reason=voluntary_logout; db_actor=' || session_user);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS lab6_check_session ON sessions;
CREATE TRIGGER lab6_check_session BEFORE INSERT OR UPDATE ON sessions
FOR EACH ROW EXECUTE FUNCTION lab6_check_session();

-- ТРИГГЕР 2: проверяем полную историю затронутых пар после всего INSERT.
CREATE OR REPLACE FUNCTION lab6_check_delivery() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_pair record;				-- переменная пары message_id/device_id
    v_event record;				-- переменная для одного события доставки текущей пары
    v_message messages%ROWTYPE;	-- строка messages
    v_device devices%ROWTYPE;	-- строка devices
    v_number integer;			-- позиция события: 1-прием сервером, 2-доставка, 3-чтение
    v_previous uuid;			-- UUID предыдущего события
    v_time timestamptz;			-- Время предыдущего события
BEGIN
    FOR v_pair IN
        SELECT DISTINCT message_id, device_id
        FROM inserted_events
        ORDER BY message_id, device_id
    LOOP
        SELECT * INTO STRICT v_message
        FROM messages
        WHERE message_id = v_pair.message_id;

        SELECT * INTO STRICT v_device
        FROM devices
        WHERE device_id = v_pair.device_id;
        v_number := 0;
        v_previous := NULL;
        v_time := NULL;
        FOR v_event IN
            SELECT *
            FROM delivery_events
            WHERE message_id = v_pair.message_id
              AND device_id = v_pair.device_id
            ORDER BY sent_at, event_id
        LOOP
            v_number := v_number + 1;
            IF (v_number = 1 AND v_event.d_type <> 'received_by_server')
               OR (v_number = 2 AND v_event.d_type <> 'delivered')
               OR (v_number = 3 AND v_event.d_type <> 'read') OR v_number > 3 THEN
                RAISE EXCEPTION 'Нарушена последовательность доставки';
            END IF;
            IF v_time IS NOT NULL AND v_event.sent_at <= v_time THEN
                RAISE EXCEPTION 'Время следующего события должно быть строго больше';
            END IF;
            IF v_event.previous_event_id IS DISTINCT FROM v_previous THEN
                RAISE EXCEPTION 'Неверный previous_event_id';
            END IF;
            IF v_event.sent_at < v_device.registration_date OR v_event.sent_at < v_message.sent_at THEN
                RAISE EXCEPTION 'Событие предшествует устройству или сообщению';
            END IF;
            -- Получатель в исходной модели определяется владельцем устройства.
            -- Одна строка членства должна покрывать обе даты.
            IF NOT EXISTS (
                SELECT 1
                FROM chat_memberships cm
                WHERE cm.chat_id = v_message.chat_id
                  AND cm.user_id = v_device.user_id
                  AND cm.join_date <= v_message.sent_at
                  AND cm.join_date <= v_event.sent_at
                  AND (cm.leave_date IS NULL OR v_message.sent_at < cm.leave_date)
                  AND (cm.leave_date IS NULL OR v_event.sent_at < cm.leave_date)
                  AND (cm.leave_date IS NOT NULL OR cm.m_status = 'active')
            ) THEN
                RAISE EXCEPTION 'Сообщение и доставка относятся к разным периодам членства';
            END IF;
            v_previous := v_event.event_id;
            v_time := v_event.sent_at;
        END LOOP;
    END LOOP;
    RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS lab6_check_delivery ON delivery_events;
CREATE TRIGGER lab6_check_delivery AFTER INSERT ON delivery_events
REFERENCING NEW TABLE AS inserted_events
FOR EACH STATEMENT EXECUTE FUNCTION lab6_check_delivery();

-- История доставки и редакций дополняется; переписывать её нельзя.
CREATE OR REPLACE FUNCTION lab6_keep_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Историю нельзя изменять или удалять';
END;
$$;
DROP TRIGGER IF EXISTS lab6_keep_history ON delivery_events;
CREATE TRIGGER lab6_keep_history BEFORE UPDATE OR DELETE ON delivery_events
FOR EACH STATEMENT EXECUTE FUNCTION lab6_keep_history();
DROP TRIGGER IF EXISTS lab6_keep_history ON version_of_messages;
CREATE TRIGGER lab6_keep_history BEFORE UPDATE OR DELETE ON version_of_messages
FOR EACH STATEMENT EXECUTE FUNCTION lab6_keep_history();

-- Реальное действие временной санкции на новые публикации.
CREATE OR REPLACE FUNCTION lab6_check_publication() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = NEW.author_id
          AND a_status = 'active'
    ) OR lab6_user_restricted(NEW.author_id, clock_timestamp()) THEN
        RAISE EXCEPTION 'Публикация запрещена для заблокированного или ограниченного автора';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS lab6_check_publication ON messages;
CREATE TRIGGER lab6_check_publication BEFORE INSERT ON messages
FOR EACH ROW EXECUTE FUNCTION lab6_check_publication();

COMMIT;
