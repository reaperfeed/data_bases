-- создаём календарь с запасом в 7 дней для расчёта начальных показателей
WITH calendar AS (
    SELECT gs::date AS day
    FROM generate_series(
        DATE '2026-10-01' - 7,
        DATE '2026-11-01' - 1,
        INTERVAL '1 day'
    ) AS gs
),
-- считаем сообщения каждого чата за день, включая дни без сообщений
daily_counts AS (
    SELECT
        c.day,
        ch.chat_id,
        COUNT(m.message_id) AS messages_per_day
    FROM calendar c
    CROSS JOIN chats ch
    LEFT JOIN messages m
        ON m.chat_id = ch.chat_id
        -- определяем границы календарного дня по московскому времени
        AND m.sent_at >= (
            c.day::timestamp AT TIME ZONE 'Europe/Moscow'
            )
        AND m.sent_at < (
            (c.day + 1)::timestamp AT TIME ZONE 'Europe/Moscow'
            )
    GROUP BY c.day, ch.chat_id
),
-- считаем сообщения за текущий день и шесть предыдущих дней
rolling AS (
    SELECT
        day,
        chat_id,
        messages_per_day,
        SUM(messages_per_day) OVER (
            PARTITION BY chat_id
            ORDER BY day
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS messages_7_days
    FROM daily_counts
),
-- вычисляем изменение семидневного показателя относительно предыдущего дня
with_change AS (
    SELECT
        day,
        chat_id,
        messages_per_day,
        messages_7_days,
        messages_7_days
            - LAG(messages_7_days) OVER (
                PARTITION BY chat_id
                ORDER BY day
            ) AS change_vs_previous_day
    FROM rolling
),
-- формируем рейтинг чатов на каждую дату по семидневной активности
ranked AS (
    SELECT
        day,
        chat_id,
        messages_per_day,
        messages_7_days,
        change_vs_previous_day,
        RANK() OVER (
            PARTITION BY day
            ORDER BY messages_7_days DESC
        ) AS chat_rank
    FROM with_change
)
-- выводим показатели только за заданный период
SELECT
    day,
    chat_id,
    messages_per_day,
    messages_7_days,
    change_vs_previous_day,
    chat_rank
FROM ranked
WHERE day >= DATE '2026-10-01'
  	AND day <  DATE '2026-11-01'
ORDER BY day, chat_rank, chat_id;