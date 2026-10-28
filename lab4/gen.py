"""
Генерация тестовых данных для БД мессенджера «Ferstappen» (Вариант 56).

Заполняет ВСЕ таблицы:
    objects, users, devices, sessions,
    chats, chat_memberships, messages, version_of_messages,
    attachments, attachment_representations, delivery_events, reactions,
    complaints, decisions, admin_actions, audits

Запуск:
    python gen.py
    python gen.py --users 300 --chats 60 --messages 2000 --complaints 200
"""
import argparse
import os
import random
import uuid
from datetime import datetime, timedelta, timezone

import psycopg2
import psycopg2.extras
from psycopg2.extras import execute_values
from faker import Faker
from dotenv import load_dotenv

psycopg2.extras.register_uuid()  # чтобы uuid.UUID адаптировался к типу uuid

load_dotenv()
fake = Faker("ru_RU")
random.seed(42)
Faker.seed(42)

PHONE_PLATFORMS = ["android", "ios"]
DESKTOP_PLATFORMS = ["linux", "windows"]
REACTIONS = ["like", "heart", "laugh", "angry", "sad", "fire", "thumbsup"]
ATTACH_TYPES = ["photo", "audio", "video", "file"]
DECISION_TYPES = [
    "reject_complaint",
    "restrict_message",
    "temporarily_restrict_user",
    "forward_to_senior_moderator",
]
ADMIN_ACTION_TYPES = [
    "block",
    "restrict",
    "change_access",
    "edit_message",
    "delete_message",
]


# ---------------------------------------------------------------------------
# Подключение
# ---------------------------------------------------------------------------
def connect():
    return psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "lab4"),
        user=os.getenv("PGUSER", "postgres"),
        password=os.getenv("PGPASSWORD", "postgres"),
    )


# ---------------------------------------------------------------------------
# Вспомогательные
# ---------------------------------------------------------------------------
def insert_objects(cur, rows):
    """rows: список (object_id, o_type)."""
    if rows:
        execute_values(
            cur,
            "INSERT INTO objects (object_id, o_type) VALUES %s",
            rows,
        )


def gen_phone():
    # Подходит под CHECK: ^\+?[1-9]\d{1,14}$
    return f"+7{random.randint(9000000000, 9999999999)}"


# ---------------------------------------------------------------------------
# E1 users / E16 objects(user)
# ---------------------------------------------------------------------------
def gen_users(cur, n):
    obj_rows = []
    user_rows = []

    for i in range(n):
        user_id = uuid.uuid4()
        login = f"user_{i:05d}"
        phone = gen_phone() if random.random() > 0.2 else None
        email = f"{login}@example.com" if random.random() > 0.15 else None
        status = random.choices(
            ["active", "blocked", "deleted"],
            weights=[9, 1, 0.3],
        )[0]

        obj_rows.append((user_id, "user"))
        user_rows.append((
            user_id,
            login,
            fake.first_name(),
            fake.last_name(),
            phone,
            email,
            status,
        ))

    insert_objects(cur, obj_rows)

    if user_rows:
        execute_values(
            cur,
            """
            INSERT INTO users
                (user_id, u_login, first_name, last_name,
                 phone_number, email, a_status)
            VALUES %s
            """,
            user_rows,
        )

    return [r[0] for r in user_rows]


# ---------------------------------------------------------------------------
# E2 devices
# ---------------------------------------------------------------------------
def gen_devices(cur, user_ids):
    rows = []

    for uid in user_ids:
        for _ in range(random.randint(1, 3)):
            device_id = uuid.uuid4()
            dtype = random.choice(["phone_tablet", "computer_laptop"])
            platform = random.choice(
                PHONE_PLATFORMS if dtype == "phone_tablet" else DESKTOP_PLATFORMS
            )
            os_version = f"{random.randint(10, 17)}.{random.randint(0, 9)}"

            rows.append((device_id, uid, dtype, platform, os_version))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO devices
                (device_id, user_id, d_type, p_type, os_version)
            VALUES %s
            """,
            rows,
        )

    return [(r[0], r[1]) for r in rows]


# ---------------------------------------------------------------------------
# E3 sessions
# ---------------------------------------------------------------------------
def gen_sessions(cur, devices):
    rows = []

    for dev_id, uid in devices:
        for _ in range(random.randint(0, 3)):
            start = datetime.now() - timedelta(days=random.randint(0, 180))

            if random.random() > 0.3:
                end = start + timedelta(minutes=random.randint(5, 300))
                status = "inactive"
            else:
                end = None
                status = "active"

            rows.append((uid, dev_id, status, start, end))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO sessions
                (user_id, device_id, s_status, start_time, end_time)
            VALUES %s
            """,
            rows,
        )


# ---------------------------------------------------------------------------
# E4 chats / objects(chat)
# ---------------------------------------------------------------------------
def gen_chats(cur, user_ids, n):
    obj_rows = []
    chat_rows = []

    for _ in range(n):
        chat_id = uuid.uuid4()
        ctype = random.choice(["dialog", "group", "channel"])
        chat_name = None if ctype == "dialog" else fake.catch_phrase()[:150]

        obj_rows.append((chat_id, "chat"))
        chat_rows.append((chat_id, ctype, chat_name))

    insert_objects(cur, obj_rows)

    if chat_rows:
        execute_values(
            cur,
            """
            INSERT INTO chats (chat_id, c_type, chat_name)
            VALUES %s
            """,
            chat_rows,
        )

    return [(r[0], r[1]) for r in chat_rows]


# ---------------------------------------------------------------------------
# E5 chat_memberships
# ---------------------------------------------------------------------------
def gen_memberships(cur, chats, user_ids):
    rows = []

    for chat_id, ctype in chats:
        if ctype == "dialog":
            members = random.sample(user_ids, min(2, len(user_ids)))
            roles = ["owner", "member"][:len(members)]
        else:
            k = random.randint(2, min(15, len(user_ids)))
            members = random.sample(user_ids, k)
            roles = ["owner"] + [
                random.choice(["admin", "member", "reader"]) for _ in range(k - 1)
            ]

        for uid, role in zip(members, roles):
            rows.append((chat_id, uid, role, "active"))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO chat_memberships
                (chat_id, user_id, m_role, m_status)
            VALUES %s
            """,
            rows,
        )


# ---------------------------------------------------------------------------
# E6 messages / objects(message)
# ---------------------------------------------------------------------------
def gen_messages(cur, chats, n):
    chat_ids = [c[0] for c in chats]

    cur.execute("""
        SELECT chat_id, user_id
          FROM chat_memberships
         WHERE m_status = 'active'
    """)
    members_by_chat = {}
    for cid, uid in cur.fetchall():
        members_by_chat.setdefault(cid, []).append(uid)

    obj_rows = []
    msg_rows = []

    for _ in range(n):
        if not chat_ids:
            break

        cid = random.choice(chat_ids)
        authors = members_by_chat.get(cid, [])
        if not authors:
            continue

        author = random.choice(authors)
        message_id = uuid.uuid4()
        sent = datetime.now() - timedelta(
            days=random.randint(0, 365),
            minutes=random.randint(0, 1440),
        )
        ctype = "text" if random.random() > 0.2 else "attachment"
        status = random.choices(
            ["sent", "edited", "deleted"],
            weights=[8, 1.5, 0.5],
        )[0]

        obj_rows.append((message_id, "message"))
        msg_rows.append((message_id, cid, author, sent, ctype, status))

    insert_objects(cur, obj_rows)

    if msg_rows:
        execute_values(
            cur,
            """
            INSERT INTO messages
                (message_id, chat_id, author_id, sent_at, c_type, m_status)
            VALUES %s
            """,
            msg_rows,
            page_size=500,
        )

    return [r[0] for r in msg_rows]


# ---------------------------------------------------------------------------
# E7 version_of_messages
# ---------------------------------------------------------------------------
def gen_versions(cur):
    cur.execute("SELECT message_id, author_id, m_status FROM messages")
    rows = []

    for mid, author_id, status in cur.fetchall():
        rows.append((
            mid,
            0,
            fake.paragraph(nb_sentences=2)[:500],
            author_id,
            "original",
        ))

        if status == "edited":
            rows.append((
                mid,
                1,
                fake.paragraph(nb_sentences=2)[:500],
                author_id,
                "edited",
            ))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO version_of_messages
                (message_id, version_number, content, editor_id, v_type)
            VALUES %s
            """,
            rows,
            page_size=500,
        )


# ---------------------------------------------------------------------------
# E8 attachments / objects(attachment)
# ---------------------------------------------------------------------------
def gen_attachments(cur):
    cur.execute("""
        SELECT message_id
          FROM messages
         WHERE c_type = 'attachment'
    """)
    msg_ids = [r[0] for r in cur.fetchall()]

    obj_rows = []
    attach_rows = []

    for mid in msg_ids:
        for _ in range(random.randint(1, 3)):
            aid = uuid.uuid4()
            atype = random.choice(ATTACH_TYPES)
            name = fake.file_name()
            size = random.randint(1000, 50_000_000)
            path = f"https://cdn.ferstappen.ru/files/{uuid.uuid4()}"
            status = random.choice(
                ["uploading", "uploaded", "uploaded", "deleted"]
            )

            obj_rows.append((aid, "attachment"))
            attach_rows.append((aid, mid, atype, name, size, path, status))

    insert_objects(cur, obj_rows)

    if attach_rows:
        execute_values(
            cur,
            """
            INSERT INTO attachments
                (attachment_id, message_id, a_type, name, size, path, a_status)
            VALUES %s
            """,
            attach_rows,
            page_size=500,
        )

    return [(r[0], r[2]) for r in attach_rows]


# ---------------------------------------------------------------------------
# E9 attachment_representations
# ---------------------------------------------------------------------------
def gen_representations(cur, attachments):
    rows = []

    for aid, atype in attachments:
        if atype == "photo":
            formats = ["jpg", "png", "webp"]
        elif atype == "video":
            formats = ["mp4", "webm"]
        elif atype == "audio":
            formats = ["mp3", "ogg"]
        else:
            formats = ["bin", "pdf", "zip"]

        k = random.randint(1, len(formats))

        for fmt in random.sample(formats, k):
            size = random.randint(1000, 10_000_000)
            path = f"s3://ferstappen/{uuid.uuid4()}.{fmt}"
            status = random.choice(["ready", "not_ready"])

            rows.append((aid, fmt, size, path, status))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO attachment_representations
                (attachment_id, format, size, path, r_status)
            VALUES %s
            """,
            rows,
            page_size=500,
        )


# ---------------------------------------------------------------------------
# E10 delivery_events
# ---------------------------------------------------------------------------
def gen_delivery_events(cur, devices):
    cur.execute("SELECT message_id FROM messages")
    msg_ids = [r[0] for r in cur.fetchall()]

    rows = []

    for mid in msg_ids:
        if not devices:
            break

        chosen = random.sample(
            devices,
            k=min(len(devices), random.randint(1, 3)),
        )

        for dev_id, _ in chosen:
            for evt in ["sent", "received_by_server", "delivered", "read"]:
                if random.random() < 0.8:
                    rows.append((mid, dev_id, evt))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO delivery_events
                (message_id, device_id, d_type)
            VALUES %s
            """,
            rows,
            page_size=500,
        )


# ---------------------------------------------------------------------------
# E11 reactions
# ---------------------------------------------------------------------------
def gen_reactions(cur, user_ids):
    cur.execute("SELECT message_id FROM messages")
    msg_ids = [r[0] for r in cur.fetchall()]

    rows = []

    if msg_ids and user_ids:
        sample_size = max(1, len(msg_ids) // 2)
        for mid in random.sample(msg_ids, k=min(len(msg_ids), sample_size)):
            for uid in random.sample(
                user_ids,
                k=min(len(user_ids), random.randint(1, 5)),
            ):
                rows.append((mid, uid, random.choice(REACTIONS)))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO reactions (message_id, user_id, reaction)
            VALUES %s
            ON CONFLICT (message_id, user_id, reaction) DO NOTHING
            """,
            rows,
            page_size=500,
        )


# ---------------------------------------------------------------------------
# E12 complaints
# ---------------------------------------------------------------------------
def gen_complaints(cur, user_ids, n):
    if not user_ids or n <= 0:
        return []

    cur.execute("SELECT object_id FROM objects WHERE o_type <> 'admin_action'")
    objects = [r[0] for r in cur.fetchall()]
    if not objects:
        return []

    rows = []
    for _ in range(n):
        complaint_id = uuid.uuid4()
        target_obj = random.choice(objects)
        complainant = random.choice(user_ids)
        description = fake.paragraph(nb_sentences=2)[:300]
        filed_at = datetime.now() - timedelta(days=random.randint(0, 90))
        status = random.choices(
            ["filed", "reviewed"],
            weights=[6, 4],
        )[0]
        rows.append((
            complaint_id, target_obj, complainant,
            description, filed_at, status,
        ))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO complaints
                (complaint_id, object_id, complainant_id,
                 description, filed_at, c_status)
            VALUES %s
            """,
            rows,
            page_size=500,
        )

    return rows


# ---------------------------------------------------------------------------
# E13 decisions
# ---------------------------------------------------------------------------
def gen_decisions(cur, complaints, user_ids):
    if not complaints or not user_ids:
        return []

    rows = []
    for (cid, target_obj, _complainant,
         _desc, _filed, cstatus) in complaints:
        if cstatus != "reviewed":
            continue

        decision_id = uuid.uuid4()
        moderator = random.choice(user_ids)
        executed_at = datetime.now() - timedelta(days=random.randint(0, 30))
        d_type = random.choice(DECISION_TYPES)
        d_status = random.choices(
            ["executed", "in_queue"],
            weights=[7, 3],
        )[0]

        rows.append((
            decision_id, target_obj, moderator, cid,
            executed_at, d_type, d_status,
        ))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO decisions
                (decision_id, object_id, user_id, complaint_id,
                 executed_at, d_type, d_status)
            VALUES %s
            """,
            rows,
            page_size=500,
        )

    return rows


# ---------------------------------------------------------------------------
# E14 admin_actions / objects(admin_action)
# ---------------------------------------------------------------------------
def gen_admin_actions(cur, decisions, user_ids):
    if not decisions or not user_ids:
        return

    obj_rows = []
    rows = []

    for (did, target_obj, moderator, _cid,
         executed_at, _d_type, d_status) in decisions:
        if d_status != "executed":
            continue
        if random.random() > 0.7:
            continue  # не каждое решение приводит к явному действию

        action_id = uuid.uuid4()
        executed_at_action = executed_at + timedelta(hours=random.randint(1, 72))
        action_type = random.choice(ADMIN_ACTION_TYPES)
        reason = fake.sentence(nb_words=8)[:200]
        duration = None
        if action_type in ("block", "restrict"):
            duration = timedelta(days=random.randint(1, 30))

        obj_rows.append((action_id, "admin_action"))
        rows.append((
            action_id, target_obj, moderator, did,
            executed_at_action, action_type, reason, duration,
        ))

    if rows:
        insert_objects(cur, obj_rows)
        execute_values(
            cur,
            """
            INSERT INTO admin_actions
                (action_id, object_id, user_id, decision_id,
                 executed_at, action_type, reason, duration)
            VALUES %s
            """,
            rows,
            page_size=500,
        )


# ---------------------------------------------------------------------------
# E15 audits
# ---------------------------------------------------------------------------
def gen_audits(cur, user_ids, n):
    if not user_ids or n <= 0:
        return

    cur.execute("SELECT object_id FROM objects")
    objects = [r[0] for r in cur.fetchall()]
    if not objects:
        return

    rows = []
    for _ in range(n):
        target_obj = random.choice(objects)
        uid = random.choice(user_ids)
        was_at = datetime.now() - timedelta(days=random.randint(0, 180))
        result = random.choices(["success", "error"], weights=[8, 2])[0]
        info = fake.sentence(nb_words=10)[:200]
        rows.append((target_obj, uid, was_at, result, info))

    if rows:
        execute_values(
            cur,
            """
            INSERT INTO audits
                (object_id, user_id, was_at, result, additional_info)
            VALUES %s
            """,
            rows,
            page_size=500,
        )



# ---------------------------------------------------------------------------
# Детерминированные данные для лабораторных запросов
# ---------------------------------------------------------------------------
def seed_query_fixtures(cur, user_ids):
    """Добавляет небольшие гарантированные наборы для запросов 1–3.

    Период сообщений и жалоб совпадает с примером в SQL: октябрь 2026.
    Также добавляет пользователя с двумя устройствами: со старого не было
    входов 30 дней, а с нового был вход в последние 30 дней.
    """
    if not user_ids:
        return

    now = datetime.now(timezone.utc)
    fixture_user = user_ids[0]
    second_user = user_ids[1] if len(user_ids) > 1 else fixture_user

    # Пользователь для тестового сценария должен быть активен.
    cur.execute(
        "UPDATE users SET a_status = 'active' WHERE user_id = %s",
        (fixture_user,),
    )
    if second_user != fixture_user:
        cur.execute(
            "UPDATE users SET a_status = 'active' WHERE user_id = %s",
            (second_user,),
        )

    # Сценарий для запроса 2: старое устройство без недавних сессий,
    # другое устройство с недавним входом.
    old_device_id = uuid.uuid4()
    recent_device_id = uuid.uuid4()
    cur.execute(
        """
        INSERT INTO devices
            (device_id, user_id, d_type, p_type, os_version,
             registration_date, d_status, last_activity_date)
        VALUES
            (%s, %s, 'phone_tablet', 'android', '14.0', %s,
             'disconnected', %s),
            (%s, %s, 'computer_laptop', 'windows', '11', %s,
             'connected', %s)
        """,
        (
            old_device_id, fixture_user, now - timedelta(days=120),
            now - timedelta(days=45),
            recent_device_id, fixture_user, now - timedelta(days=60),
            now - timedelta(days=1),
        ),
    )
    cur.execute(
        """
        INSERT INTO sessions (user_id, device_id, s_status, start_time, end_time)
        VALUES (%s, %s, 'inactive', %s, %s)
        """,
        (fixture_user, recent_device_id, now - timedelta(days=1), now - timedelta(hours=1)),
    )

    # Сценарии для запросов 1 и 3: один чат с 25 сообщениями и шестью
    # жалобами, второй чат с сообщениями для осмысленного ежедневного рейтинга.
    period_start = datetime(2026, 10, 1, 0, 0, tzinfo=timezone(timedelta(hours=3)))
    fixture_chats = [uuid.uuid4(), uuid.uuid4()]
    insert_objects(cur, [(cid, "chat") for cid in fixture_chats])
    execute_values(
        cur,
        "INSERT INTO chats (chat_id, c_type, chat_name) VALUES %s",
        [
            (fixture_chats[0], "group", "fixture_complaints_chat"),
            (fixture_chats[1], "group", "fixture_activity_chat"),
        ],
    )

    membership_rows = []
    for chat_id in fixture_chats:
        membership_rows.append((chat_id, fixture_user, "owner", "active"))
        if second_user != fixture_user:
            membership_rows.append((chat_id, second_user, "member", "active"))
    execute_values(
        cur,
        """
        INSERT INTO chat_memberships (chat_id, user_id, m_role, m_status)
        VALUES %s
        """,
        membership_rows,
    )

    message_rows = []
    for i in range(25):
        message_id = uuid.uuid4()
        author_id = fixture_user if i % 2 == 0 else second_user
        sent_at = period_start + timedelta(days=i % 20, hours=9 + i % 10)
        message_rows.append(
            (message_id, fixture_chats[0], author_id, sent_at, "text", "sent")
        )
    for i in range(14):
        message_id = uuid.uuid4()
        author_id = fixture_user if i % 2 == 0 else second_user
        sent_at = period_start + timedelta(days=14 + i % 7, hours=10 + i % 8)
        message_rows.append(
            (message_id, fixture_chats[1], author_id, sent_at, "text", "sent")
        )

    insert_objects(cur, [(row[0], "message") for row in message_rows])
    execute_values(
        cur,
        """
        INSERT INTO messages
            (message_id, chat_id, author_id, sent_at, c_type, m_status)
        VALUES %s
        """,
        message_rows,
        page_size=500,
    )

    version_rows = [
        (row[0], 0, "Тестовое сообщение для проверки запросов", row[2], "original")
        for row in message_rows
    ]
    execute_values(
        cur,
        """
        INSERT INTO version_of_messages
            (message_id, version_number, content, editor_id, v_type)
        VALUES %s
        """,
        version_rows,
        page_size=500,
    )

    # Все шесть жалоб поданы в октябре на сообщения первого тестового чата.
    target_messages = [row for row in message_rows if row[1] == fixture_chats[0]][:6]
    complaint_rows = []
    for i, row in enumerate(target_messages):
        complaint_rows.append((
            uuid.uuid4(), row[0], second_user,
            "Тестовая жалоба на сообщение",
            period_start + timedelta(days=20, hours=12, minutes=i),
            "reviewed",
        ))
    execute_values(
        cur,
        """
        INSERT INTO complaints
            (complaint_id, object_id, complainant_id, description, filed_at, c_status)
        VALUES %s
        """,
        complaint_rows,
    )

    decision_rows = []
    for i, (complaint_id, message_id, _complainant, _description, filed_at, _status) in enumerate(complaint_rows):
        if i < 3:
            decision_type, decision_status = "restrict_message", "executed"
        elif i == 3:
            decision_type, decision_status = "temporarily_restrict_user", "executed"
        elif i == 4:
            decision_type, decision_status = "reject_complaint", "executed"
        else:
            decision_type, decision_status = "restrict_message", "in_queue"
        decision_rows.append((
            uuid.uuid4(), message_id, fixture_user, complaint_id,
            filed_at + timedelta(hours=1), decision_type, decision_status,
        ))
    execute_values(
        cur,
        """
        INSERT INTO decisions
            (decision_id, object_id, user_id, complaint_id, executed_at, d_type, d_status)
        VALUES %s
        """,
        decision_rows,
    )

    print(
        "-> query fixtures: 2 chats, 39 messages, 6 complaints, "
        "1 inactive device with a recent login from another device"
    )

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main():
    p = argparse.ArgumentParser()
    p.add_argument("--users", type=int, default=300)
    p.add_argument("--chats", type=int, default=60)
    p.add_argument("--messages", type=int, default=2000)
    p.add_argument("--complaints", type=int, default=200,
                   help="число жалоб; от них зависят decisions/admin_actions")
    args = p.parse_args()
    if args.users < 1:
        p.error("--users должен быть не меньше 1: тестовый сценарий использует пользователя")

    with connect() as conn, conn.cursor() as cur:
        print("-> users")
        user_ids = gen_users(cur, args.users)

        print("-> devices")
        devices = gen_devices(cur, user_ids)

        print("-> sessions")
        gen_sessions(cur, devices)

        print("-> chats")
        chats = gen_chats(cur, user_ids, args.chats)

        print("-> memberships")
        gen_memberships(cur, chats, user_ids)

        print("-> messages")
        gen_messages(cur, chats, args.messages)

        print("-> versions")
        gen_versions(cur)

        print("-> attachments")
        attachments = gen_attachments(cur)

        print("-> attachment_representations")
        gen_representations(cur, attachments)

        print("-> delivery_events")
        gen_delivery_events(cur, devices)

        print("-> reactions")
        gen_reactions(cur, user_ids)

        print("-> complaints")
        complaints = gen_complaints(cur, user_ids, args.complaints)

        print("-> decisions")
        decisions = gen_decisions(cur, complaints, user_ids)

        print("-> admin_actions")
        gen_admin_actions(cur, decisions, user_ids)

        print("-> audits")
        gen_audits(cur, user_ids, args.complaints * 2)

        print("-> query fixtures")
        seed_query_fixtures(cur, user_ids)

        conn.commit()

    print("OK: тестовые данные сгенерированы")


if __name__ == "__main__":
    main()