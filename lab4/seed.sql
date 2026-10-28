BEGIN;

DO $$
DECLARE
    u_admin  uuid; u_moder uuid; u_alex uuid; u_mich uuid; u_pavel uuid;
    d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid;
    c1 uuid; c2 uuid; c3 uuid;
    m1 uuid; m2 uuid; m3 uuid; m4 uuid; m5 uuid;
    compl1 uuid;
    dec1   uuid;
BEGIN
    INSERT INTO objects (object_type) VALUES ('user') RETURNING object_id INTO u_admin;
    INSERT INTO users (user_id, u_login, first_name, last_name, phone_number, email, a_status)
    VALUES (u_admin, 'tikomarov', 'Тимофей', 'Комаров', '+79000000001', 'admin@ferstappen.ru', 'active');

    INSERT INTO objects (object_type) VALUES ('user') RETURNING object_id INTO u_moder;
    INSERT INTO users (user_id, u_login, first_name, last_name, phone_number, email, a_status)
    VALUES (u_moder, 'yuliya_myxa', 'Юлия', 'Половнева', '+79000000002', 'moder@ferstappen.ru', 'active');

    INSERT INTO objects (object_type) VALUES ('user') RETURNING object_id INTO u_alex;
    INSERT INTO users (user_id, u_login, first_name, last_name, phone_number, email, a_status)
    VALUES (u_alex, 'abvavrenyuk', 'Александр', 'Вавренюк', '+79001111111', 'abv@example.com', 'active');

    INSERT INTO objects (object_type) VALUES ('user') RETURNING object_id INTO u_mich;
    INSERT INTO users (user_id, u_login, first_name, last_name, phone_number, email, a_status)
    VALUES (u_mich, 'mpgrigoriev', 'Михаил', 'Григорьев', NULL, 'mpgrigoriev@example.com', 'active');

    INSERT INTO objects (object_type) VALUES ('user') RETURNING object_id INTO u_pavel;
    INSERT INTO users (user_id, u_login, first_name, last_name, phone_number, email, a_status)
    VALUES (u_pavel, 'pavkacherepkov', 'Павел', 'Черепков', '+79003333333', NULL, 'blocked');

    INSERT INTO devices (user_id, d_type, p_type, os_version)
    VALUES (u_admin, 'computer_laptop', 'windows', '11')  RETURNING device_id INTO d1;
    INSERT INTO devices (user_id, d_type, p_type, os_version)
    VALUES (u_admin, 'phone_tablet', 'android', '14')     RETURNING device_id INTO d2;
    INSERT INTO devices (user_id, d_type, p_type, os_version)
    VALUES (u_moder, 'computer_laptop', 'linux', 'Ubuntu 24.04') RETURNING device_id INTO d3;
    INSERT INTO devices (user_id, d_type, p_type, os_version)
    VALUES (u_alex,  'phone_tablet', 'ios', '17.5')       RETURNING device_id INTO d4;
    INSERT INTO devices (user_id, d_type, p_type, os_version)
    VALUES (u_mich,  'phone_tablet', 'android', '13')     RETURNING device_id INTO d5;

    INSERT INTO sessions (user_id, device_id, s_status) VALUES
        (u_admin, d1, 'active'),
        (u_alex,  d4, 'active'),
        (u_mich,  d5, 'active');

    INSERT INTO objects (object_type) VALUES ('chat') RETURNING object_id INTO c1;
    INSERT INTO chats (chat_id, chat_type, chat_name) VALUES (c1, 'dialog', NULL);

    INSERT INTO objects (object_type) VALUES ('chat') RETURNING object_id INTO c2;
    INSERT INTO chats (chat_id, chat_type, chat_name) VALUES (c2, 'group', 'Разработка Ferstappen');

    INSERT INTO objects (object_type) VALUES ('chat') RETURNING object_id INTO c3;
    INSERT INTO chats (chat_id, chat_type, chat_name) VALUES (c3, 'channel', 'Кафедра 12');

    INSERT INTO chat_memberships (user_id, chat_id, member_role) VALUES
        (u_alex,  c1, 'owner'),
        (u_mich,  c1, 'owner'),
        (u_admin, c2, 'owner'),
        (u_moder, c2, 'admin'),
        (u_alex,  c2, 'member'),
        (u_admin, c3, 'owner');

    INSERT INTO objects (object_type) VALUES ('message') RETURNING object_id INTO m1;
    INSERT INTO messages (message_id, chat_id, author_id, content_type, message_status)
    VALUES (m1, c1, u_alex, 'text', 'sent');

    INSERT INTO objects (object_type) VALUES ('message') RETURNING object_id INTO m2;
    INSERT INTO messages (message_id, chat_id, author_id, content_type, message_status)
    VALUES (m2, c1, u_mich, 'text', 'sent');

    INSERT INTO objects (object_type) VALUES ('message') RETURNING object_id INTO m3;
    INSERT INTO messages (message_id, chat_id, author_id, content_type, message_status)
    VALUES (m3, c2, u_admin, 'text', 'sent');

    INSERT INTO objects (object_type) VALUES ('message') RETURNING object_id INTO m4;
    INSERT INTO messages (message_id, chat_id, author_id, content_type, message_status)
    VALUES (m4, c2, u_alex, 'text', 'edited');

    INSERT INTO objects (object_type) VALUES ('message') RETURNING object_id INTO m5;
    INSERT INTO messages (message_id, chat_id, author_id, content_type, message_status)
    VALUES (m5, c3, u_admin, 'text', 'sent');

    INSERT INTO version_of_messages (message_id, content, version_number, editor_id, version_type) VALUES
        (m1, 'Привет!',                    0, u_alex,  'original'),
        (m2, 'Привет, как дела?',          0, u_mich,  'original'),
        (m3, 'Коллеги, начинаем спринт',   0, u_admin, 'original'),
        (m4, 'Первый набросок',            0, u_alex,  'original'),
        (m4, 'Финальная версия',           1, u_alex,  'edited'),
        (m5, 'Релиз назначен на 15 число', 0, u_admin, 'original');

    INSERT INTO reactions (user_id, message_id, reaction) VALUES
        (u_mich, m1, 'like'),
        (u_alex, m2, 'heart');

    INSERT INTO complaints (object_id, complainant_id, description, complaint_status)
    VALUES (m4, u_mich, 'Содержит некорректную лексику', 'filed')
    RETURNING complaint_id INTO compl1;

    INSERT INTO decisions (object_id, user_id, complaint_id, decision_type, decision_status)
    VALUES (m4, u_moder, compl1, 'restrict_message', 'executed')
    RETURNING decision_id INTO dec1;

    INSERT INTO admin_actions (object_id, user_id, decision_id, action_type, reason)
    VALUES (m4, u_moder, dec1, 'edit_message', 'Скрытие содержимого');
END $$;

COMMIT;