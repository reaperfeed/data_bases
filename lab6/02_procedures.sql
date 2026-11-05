BEGIN;
SET LOCAL search_path = public, pg_temp;

-- ПРОЦЕДУРА 1. Элементы трёх массивов с одинаковым индексом образуют изменение.
CREATE OR REPLACE PROCEDURE edit_messages_batch(
    p_user uuid,		-- UUID автора	
    p_messages uuid[],	-- массив сообщений
    p_expected bigint[],-- массив ожидаемых текущих номеров версий
    p_texts text[]		-- массив текстов сообщений в порядке ожидаемых версий
)
LANGUAGE plpgsql AS $$
DECLARE
    v_now timestamptz;						-- момент операции (после блокировок)
    v_message messages%ROWTYPE;				-- строка messages
    v_version version_of_messages%ROWTYPE;	-- строка verison_of_messages
    v_chat_type chat_type;					-- тип чата	
    v_i integer;							-- временный индекс
    v_batch uuid := gen_random_uuid();		-- ID новой записи в журнале аудита
BEGIN
    PERFORM lab6_lock(); -- PERFORM вызывает функцию и не сохраняет результат
    -- cardinality даёт число элементов массива. Проверяем форму входных списков.
    IF p_user IS NULL OR cardinality(p_messages) IS NULL OR cardinality(p_messages) = 0
       OR cardinality(p_expected) IS DISTINCT FROM cardinality(p_messages)
       OR cardinality(p_texts) IS DISTINCT FROM cardinality(p_messages)
	   -- ndims вычисляет размерность массива
       OR array_ndims(p_messages) <> 1 OR array_ndims(p_expected) <> 1 OR array_ndims(p_texts) <> 1
	   -- lower вычисляет младший индекс
       OR array_lower(p_messages, 1) <> 1 OR array_lower(p_expected, 1) <> 1 OR array_lower(p_texts, 1) <> 1 THEN
        	RAISE EXCEPTION 'Нужны непустые одномерные массивы одинаковой длины с индексом от 1';
    END IF;
    -- unnest представляет элементы массива строками для обычного SELECT.
    IF EXISTS (
        SELECT 1
        FROM unnest(p_messages) x(id)
        WHERE id IS NULL
    ) OR (
        SELECT COUNT(DISTINCT id)
        FROM unnest(p_messages) x(id)
    ) <> cardinality(p_messages) THEN
        RAISE EXCEPTION 'Идентификаторы сообщений не должны повторяться или быть NULL';
    END IF;

    -- Этот порядок одинаков и для пересекающихся пакетов с обратным порядком входа.
    -- = ANY(p_messages): идентификатор равен одному из элементов входного списка.
    PERFORM 1 -- Блокируем все сообщения из подзапроса для обновлений
    FROM messages
    WHERE message_id = ANY(p_messages)
    ORDER BY message_id
    FOR UPDATE;

    IF (
        SELECT COUNT(*)
        FROM messages
        WHERE message_id = ANY(p_messages)
    ) <> cardinality(p_messages) THEN
        RAISE EXCEPTION 'Не все сообщения найдены';
    END IF;
    v_now := clock_timestamp();
    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = p_user
          AND a_status = 'active'
    ) OR lab6_user_restricted(p_user, v_now) THEN
        RAISE EXCEPTION 'Инициатор неактивен или временно ограничен';
    END IF;

    FOR v_i IN 1..cardinality(p_messages) LOOP
        SELECT * INTO STRICT v_message -- STRICT требует ровно одну строчку
        FROM messages
        WHERE message_id = p_messages[v_i];
        IF v_message.author_id <> p_user OR v_message.m_status = 'deleted'
           OR v_now < v_message.sent_at OR v_now > v_message.sent_at + INTERVAL '30 minutes' THEN
            RAISE EXCEPTION 'Сообщение % нельзя редактировать: автор, статус или срок', v_message.message_id;
        END IF;
        SELECT c_type INTO v_chat_type
        FROM chats
        WHERE chat_id = v_message.chat_id;
        IF NOT EXISTS (
            SELECT 1
            FROM chat_memberships cm
            WHERE cm.chat_id = v_message.chat_id
              AND cm.user_id = p_user
              AND cm.m_status = 'active'
              AND cm.join_date <= v_message.sent_at
              AND cm.join_date <= v_now
              AND (cm.leave_date IS NULL OR v_now < cm.leave_date)
              AND (v_chat_type <> 'channel' OR cm.m_role IN ('admin', 'owner'))
        ) THEN
            RAISE EXCEPTION 'Нет непрерывного членства или текущих полномочий в канале';
        END IF;
        IF lab6_message_restricted(v_message.message_id, v_now) THEN
            RAISE EXCEPTION 'Доступ к сообщению ограничен модератором';
        END IF;
        SELECT * INTO v_version
        FROM version_of_messages
        WHERE message_id = v_message.message_id
        ORDER BY version_number DESC
        LIMIT 1;
        IF NOT FOUND OR p_expected[v_i] IS DISTINCT FROM v_version.version_number THEN
            RAISE EXCEPTION 'Текущая версия отсутствует или ожидаемый номер устарел';
        END IF;
        IF p_texts[v_i] IS NULL OR p_texts[v_i] IS NOT DISTINCT FROM v_version.content THEN
            RAISE EXCEPTION 'Новый текст не должен быть NULL или совпадать с текущим';
        END IF;

        INSERT INTO version_of_messages
            (message_id, version_number, content, created_at, editor_id, change_reason, v_type)
        VALUES (v_message.message_id, v_version.version_number + 1, p_texts[v_i],
                v_now, p_user, 'Пакетное редактирование', 'edited');
        UPDATE messages
        SET m_status = 'edited'
        WHERE message_id = v_message.message_id;
        INSERT INTO audits (object_id, user_id, was_at, result, additional_info)
        VALUES (v_message.message_id, p_user, v_now, 'success',
                'message_edited; batch=' || v_batch::text ||
                '; version=' || (v_version.version_number + 1)::text);
    END LOOP;
    -- Нет EXCEPTION WHEN OTHERS: ошибка не скрывается и откатывает весь CALL.
END;
$$;

-- ПРОЦЕДУРА 2. Одна группа жалоб - одно решение каждого обращения и одна санкция.
-- Для передачи p_assignee обязателен. Для временной санкции нужен p_duration.
CREATE OR REPLACE PROCEDURE review_complaints_batch(
    p_moderator uuid,					-- UUID модератора
    p_complaints uuid[],				-- список UUID жалоб
    p_type decision_type,				-- тип решения: отклонение, ограничение сообщения, запрет автору или передача
    p_reason text,						-- обязательное текстовое обоснование решения
    p_duration interval DEFAULT NULL,	-- срок передаётся только для временного ограничения
    p_assignee uuid DEFAULT NULL		-- назначаемый старший сотрудник
)
LANGUAGE plpgsql AS $$
DECLARE
    v_now timestamptz;					-- единый момент рассмотрения
    v_role member_role;					-- действующая служебная роль инициатора
    v_object uuid;						-- общий объект жалоб
    v_object_type object_type;			-- тип этого объекта
    v_target uuid;						-- цель санкции
    v_complaint complaints%ROWTYPE;		-- строка жалобы целиком
    v_pending decisions%ROWTYPE;		-- найденное ожидающее назначение старшему сотруднику
    v_decision uuid;					-- UUID решения
    v_first_decision uuid;				-- первое решение пакета
    v_action uuid;						-- UUID общей санкции
    v_create_action boolean := false;	-- флаг нового действия
    v_batch uuid := gen_random_uuid();	-- общая UUID-метка операции
BEGIN
    PERFORM lab6_lock();
	-- btrim убирает пробелы по краям обоснования
    IF p_moderator IS NULL OR p_type IS NULL OR p_reason IS NULL OR btrim(p_reason) = ''
       OR cardinality(p_complaints) IS NULL OR cardinality(p_complaints) = 0
       OR array_ndims(p_complaints) <> 1 OR array_lower(p_complaints, 1) <> 1 THEN
        RAISE EXCEPTION 'Нужны модератор, решение, обоснование и непустой массив жалоб';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM unnest(p_complaints) x(id)
        WHERE id IS NULL
    ) OR (
        SELECT COUNT(DISTINCT id)
        FROM unnest(p_complaints) x(id)
    ) <> cardinality(p_complaints) THEN
        RAISE EXCEPTION 'Идентификаторы жалоб не должны повторяться или быть NULL';
    END IF;

	-- блокируем выбранные жалобы до конца транзакции
    PERFORM 1
    FROM complaints
    WHERE complaint_id = ANY(p_complaints)
    ORDER BY complaint_id
    FOR UPDATE;

	-- проверяем существование всех жалоб и принадлежность ровно одному объекту
    IF (
        SELECT COUNT(*)
        FROM complaints
        WHERE complaint_id = ANY(p_complaints)
    ) <> cardinality(p_complaints) OR (
        SELECT COUNT(DISTINCT object_id)
        FROM complaints
        WHERE complaint_id = ANY(p_complaints)
    ) <> 1 THEN
        RAISE EXCEPTION 'Все жалобы должны существовать и относиться к одному объекту';
    END IF;
    v_now := clock_timestamp();
    v_role := lab6_staff_role(p_moderator, v_now);
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Инициатор не является действующим модератором';
    END IF;
	-- берём объект первой жалобы: равенство объектов всего пакета уже проверено
    -- SELECT ... INTO сохраняет выбранное значение в переменную
    SELECT object_id INTO v_object
    FROM complaints
    WHERE complaint_id = p_complaints[1];

    SELECT o_type INTO v_object_type
    FROM objects
    WHERE object_id = v_object;
	-- процедура поддерживает только жалобы на сообщения и административные действия
    IF v_object_type NOT IN ('message', 'admin_action') THEN
        RAISE EXCEPTION 'Процедура рассматривает жалобы на сообщения и административные действия';
    END IF;
	-- одной записи в objects недостаточно: нужна запись соответствующей таблицы
    IF (v_object_type = 'message' AND NOT EXISTS (
            SELECT 1
            FROM messages
            WHERE message_id = v_object
        )) OR (v_object_type = 'admin_action' AND NOT EXISTS (
            SELECT 1
            FROM admin_actions
            WHERE action_id = v_object
        )) THEN
        RAISE EXCEPTION 'Не найдена запись объекта жалобы в соответствующей таблице';
    END IF;

	-- при передаче проверяем нового ответственного, при окончательном решении - независимость инициатора
    IF p_type = 'forward_to_senior_moderator' THEN
        IF p_assignee IS NULL OR lab6_staff_role(p_assignee, v_now) IS DISTINCT FROM 'owner'::member_role
           OR p_assignee = p_moderator OR p_duration IS NOT NULL THEN
            RAISE EXCEPTION 'Для передачи нужен другой действующий старший модератор без срока санкции';
        END IF;
        IF v_object_type = 'admin_action' AND EXISTS (
            SELECT 1
            FROM admin_actions
            WHERE action_id = v_object
              AND user_id = p_assignee
        ) THEN
            RAISE EXCEPTION 'Нельзя передать дело исполнителю оспариваемого действия';
        END IF;
    ELSE
        IF p_assignee IS NOT NULL THEN
            RAISE EXCEPTION 'Ответственный указывается только при передаче';
        END IF;
        IF v_object_type = 'admin_action' AND EXISTS (
            SELECT 1
            FROM admin_actions
            WHERE action_id = v_object
              AND user_id = p_moderator
        ) THEN
            RAISE EXCEPTION 'Конфликт интересов: модератор исполнил оспариваемое действие';
        END IF;
    END IF;

    -- Проверяем весь пакет прежде, чем формировать результаты рассмотрения.
    FOR v_complaint IN
        SELECT *
        FROM complaints
        WHERE complaint_id = ANY(p_complaints)
        ORDER BY complaint_id
    LOOP
		-- жалоба должна ожидать рассмотрения и не иметь окончательного выполненного решения
        IF v_complaint.c_status <> 'filed' OR EXISTS (
            SELECT 1
            FROM decisions d
            WHERE d.complaint_id = v_complaint.complaint_id
              AND d.d_status = 'executed'
			  -- передача сама по себе не считается окончательным рассмотрением
              AND d.d_type <> 'forward_to_senior_moderator'
        ) THEN
            RAISE EXCEPTION 'Жалоба уже рассмотрена';
        END IF;
		-- ищем ожидающую передачу текущей жалобы
        SELECT * INTO v_pending
        FROM decisions
        WHERE complaint_id = v_complaint.complaint_id
          AND d_type = 'forward_to_senior_moderator'
          AND d_status = 'in_queue';
		-- FOUND относится к предыдущему SELECT
        IF FOUND THEN
            IF p_type = 'forward_to_senior_moderator' AND v_pending.user_id = p_assignee THEN
                RAISE EXCEPTION 'Жалоба уже передана этому сотруднику';
            END IF;
            IF p_type <> 'forward_to_senior_moderator'
               AND (v_role <> 'owner' OR v_pending.user_id <> p_moderator) THEN
                RAISE EXCEPTION 'Переданную жалобу завершает назначенный старший модератор';
            END IF;
        END IF;
    END LOOP;

	-- готовим ограничительную санкцию
    IF p_type IN ('restrict_message', 'temporarily_restrict_user') THEN
        IF v_object_type <> 'message' THEN
            RAISE EXCEPTION 'Эта санкция применима только к жалобам на сообщение';
        END IF;
		-- блокируем строку сообщения; FOUND далее покажет, удалось ли её найти
        PERFORM 1
        FROM messages
        WHERE message_id = v_object
        FOR UPDATE;
		-- нельзя применить эту санкцию к отсутствующему либо удалённому сообщению
        IF NOT FOUND OR EXISTS (
            SELECT 1
            FROM messages
            WHERE message_id = v_object
              AND m_status = 'deleted'
        ) THEN
            RAISE EXCEPTION 'Сообщение отсутствует или удалено';
        END IF;
		
        IF p_type = 'restrict_message' THEN
			-- ограничение сообщения бессрочное, поэтому срок не принимается
            IF p_duration IS NOT NULL THEN
                RAISE EXCEPTION 'Для ограничения сообщения срок не указывается';
            END IF;
            -- Более поздняя жалоба может подтвердить уже применённую санкцию.
            IF lab6_message_restricted(v_object, v_now) THEN
				-- получаем UUID прежней санкции на это же сообщение
                SELECT a.action_id INTO v_action
                FROM admin_actions a
				-- по связанному решению уточняем вид санкции и проверяем её выполнение
                JOIN decisions d ON d.decision_id = a.decision_id
                WHERE a.object_id = v_object
                  AND a.action_type = 'restrict'
                  AND d.d_type = 'restrict_message'
                  AND d.d_status = 'executed'
                  AND a.executed_at <= v_now
                ORDER BY a.executed_at, a.action_id
				-- детерминированно выбираем одну подходящую прежнюю санкцию
                LIMIT 1;
				-- решение об ограничении без соответствующего действия считаем несогласованными данными
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'У существующего ограничения отсутствует административное действие';
                END IF;
            END IF;
			-- для ограничения содержимого целью действия является само сообщение
            v_target := v_object;
        ELSE
			-- ветка временного запрета автору: срок от 1 часа до 30 суток включительно
            -- равенство границам разрешено, поскольку используются только < и >
            IF p_duration IS NULL OR p_duration < INTERVAL '1 hour' OR p_duration > INTERVAL '30 days'
				-- отдельно запрещаем годы и месяцы: срок задаётся днями, часами и меньшими единицами
               OR EXTRACT(YEAR FROM p_duration) <> 0 OR EXTRACT(MONTH FROM p_duration) <> 0 THEN
                RAISE EXCEPTION 'Срок временного ограничения: от 1 часа до 30 суток, без месяцев';
            END IF;
			-- временная санкция применяется к первоначальному автору сообщения, а не к заявителю жалобы
            SELECT author_id INTO v_target
            FROM messages
            WHERE message_id = v_object;
			-- блокируем аккаунт автора и одновременно требуем его статус active
            PERFORM 1
            FROM users
            WHERE user_id = v_target
              AND a_status = 'active'
            FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Автор сообщения неактивен';
            END IF;
			-- проверяем пересечение нового периода с прежними выполненными временными ограничениями автора
            IF EXISTS (
                SELECT 1
                FROM admin_actions a
                JOIN decisions d ON d.decision_id = a.decision_id
                WHERE a.object_id = v_target
                  AND a.action_type = 'restrict'
                  AND d.d_type = 'temporarily_restrict_user'
                  AND d.d_status = 'executed'
                  AND a.executed_at < v_now + p_duration
                  AND v_now < a.executed_at + a.duration
            ) THEN
                RAISE EXCEPTION 'Период ограничения пересекается с существующим';
            END IF;
        END IF;
		-- если прежнее действие не использовано, подготавливаем одну новую санкцию на весь пакет
        IF v_action IS NULL THEN
            v_action := gen_random_uuid();
            v_create_action := true;
        END IF;
    ELSIF p_duration IS NOT NULL THEN
        RAISE EXCEPTION 'Для отклонения или передачи срок не указывается';
    END IF;

	-- второй цикл записывает индивидуальное решение каждой жалобы
    -- все проверки и подготовка общей санкции к этому моменту уже выполнены
    FOR v_complaint IN
        SELECT *
        FROM complaints
        WHERE complaint_id = ANY(p_complaints)
        ORDER BY complaint_id
    LOOP
        -- Старое ожидающее назначение закрыто, но остаётся в истории
        UPDATE decisions
        SET d_status = 'executed'
        WHERE complaint_id = v_complaint.complaint_id
          AND d_type = 'forward_to_senior_moderator'
          AND d_status = 'in_queue';
        INSERT INTO decisions
            (object_id, user_id, complaint_id, executed_at, d_type, d_status)
        VALUES (v_object,
                CASE WHEN p_type = 'forward_to_senior_moderator' THEN p_assignee ELSE p_moderator END,
                v_complaint.complaint_id, v_now, p_type,
                CASE WHEN p_type = 'forward_to_senior_moderator'
                     THEN 'in_queue'::decision_status ELSE 'executed'::decision_status END)
        RETURNING decision_id INTO v_decision;
        IF v_first_decision IS NULL THEN
            v_first_decision := v_decision;
        END IF;
        UPDATE complaints
        SET c_status = CASE WHEN p_type = 'forward_to_senior_moderator'
                            THEN 'filed'::complaint_status ELSE 'reviewed'::complaint_status END
        WHERE complaint_id = v_complaint.complaint_id;
        -- В очереди decisions.user_id = ответственный, инициатор передачи = audits.user_id.
        -- Каждая жалоба через своё решение получает связь с одним общим действием.
        INSERT INTO audits (object_id, user_id, was_at, result, additional_info)
        VALUES (v_object, p_moderator, v_now, 'success',
                'complaint_review; batch=' || v_batch::text ||
                '; complaint=' || v_complaint.complaint_id::text ||
                '; decision=' || v_decision::text ||
                '; action=' || COALESCE(v_action::text, 'none') ||
                '; type=' || p_type::text || '; reason=' || p_reason);
    END LOOP;

    IF v_create_action THEN
        INSERT INTO objects (object_id, o_type) VALUES (v_action, 'admin_action');
        INSERT INTO admin_actions
            (action_id, object_id, user_id, decision_id, executed_at, action_type, reason, duration)
        VALUES (v_action, v_target, p_moderator, v_first_decision, v_now, 'restrict',
                p_reason, p_duration);
        INSERT INTO audits (object_id, user_id, was_at, result, additional_info)
        VALUES (v_action, p_moderator, v_now, 'success', 'sanction_created; batch=' || v_batch::text);
    END IF;
END;
$$;

COMMIT;
