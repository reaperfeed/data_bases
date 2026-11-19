# Лабораторная работа 7

## Оптимизация и анализ выполнения запросов

---

## Запрос 1. Последняя версия каждого сообщения

### Исходный SQL-запрос

```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
SELECT m.message_id,
       m.chat_id,
       v.content,
       v.created_at
FROM messages AS m
JOIN version_of_messages AS v
  ON v.message_id = m.message_id
WHERE m.m_status <> 'deleted'
  AND v.version_number = (
      SELECT MAX(v2.version_number)
      FROM version_of_messages AS v2
      WHERE v2.message_id = v.message_id
  )
ORDER BY v.created_at DESC,
         m.message_id
LIMIT 1000;
```

### Основные элементы исходного плана

```text
Limit
(actual time=763.200..763.312 rows=1000 loops=1)
Buffers: shared hit=818008 read=4090

Sort Method: top-N heapsort Memory: 508kB

Nested Loop
(actual time=0.190..729.291 rows=95058 loops=1)

Seq Scan on messages
(actual time=0.111..20.605 rows=95058 loops=1)
Rows Removed by Filter: 4986

Index Only Scan using idx_versions_message_latest
(actual time=0.006..0.007 rows=1 loops=95058)
Index Searches: 95058
Heap Fetches: 109953

SubPlan 2
(actual time=0.002..0.002 rows=1 loops=109953)
```

### Оптимизация

```sql
CREATE INDEX IF NOT EXISTS idx_versions_message_latest
ON version_of_messages (message_id, version_number DESC)
INCLUDE (content, created_at);

CREATE INDEX IF NOT EXISTS idx_messages_not_deleted
ON messages (message_id, chat_id)
WHERE m_status <> 'deleted';

ANALYZE version_of_messages;
ANALYZE messages;
```

### Исправленный оптимизированный SQL-запрос

```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
SELECT message_id,
       chat_id,
       content,
       created_at
FROM (
    SELECT DISTINCT ON (m.message_id)
           m.message_id,
           m.chat_id,
           v.content,
           v.created_at
    FROM messages AS m
    JOIN version_of_messages AS v
      ON v.message_id = m.message_id
    WHERE m.m_status <> 'deleted'
      AND v.version_number IS NOT NULL
    ORDER BY m.message_id,
             v.version_number DESC
) AS latest
ORDER BY created_at DESC,
         message_id
LIMIT 1000;
```

### Основные элементы оптимизированного плана

```text
Limit
(cost=37391.78..37394.28 rows=1000)
(actual time=197.681..197.769 rows=1000 loops=1)
Buffers: shared hit=128253 read=575

Sort Method: top-N heapsort Memory: 317kB

Subquery Scan on latest
(actual time=0.082..176.870 rows=95058 loops=1)

Unique
(actual time=0.081..166.405 rows=95058 loops=1)

Merge Join
(actual time=0.080..145.875 rows=109953 loops=1)

Index Only Scan using idx_versions_message_latest
(actual time=0.007..97.183 rows=114939 loops=1)
Heap Fetches: 114939
Index Searches: 1

Index Only Scan using idx_messages_not_deleted
(actual time=0.071..20.230 rows=95058 loops=1)
Heap Fetches: 74
Index Searches: 1
```

### Сравнение первого запроса

| Показатель | До оптимизации | После оптимизации | Изменение |
|---|---:|---:|---:|
| `Execution Time` | 763.495 мс | 197.909 мс | в 3,86 раза быстрее |
| Фактические строки | 1000 | 1000 | результат совпал |
| `shared hit` | 818008 | 128253 | значительно меньше |
| `shared read` | 4090 | 575 | значительно меньше |
| Основной план | `Nested Loop` + `SubPlan` | `Merge Join` + `Unique` | повторные проверки устранены |
| Доступ к версиям | 95058 поисков индекса | 1 проход `Index Only Scan` | существенно эффективнее |

---

## Запрос 2. Доставленные, но непрочитанные сообщения

### Исходный SQL-запрос

```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
SELECT u.user_id,
       u.u_login,
       COUNT(*) AS unread_count,
       MAX(d.sent_at) AS last_unread
FROM users AS u
JOIN devices AS dv
  ON dv.user_id = u.user_id
JOIN delivery_events AS d
  ON d.device_id = dv.device_id
WHERE u.a_status = 'active'
  AND d.d_type = 'delivered'
  AND NOT EXISTS (
      SELECT 1
      FROM delivery_events AS r
      WHERE r.device_id = d.device_id
        AND r.message_id = d.message_id
        AND r.d_type = 'read'
  )
GROUP BY u.user_id,
         u.u_login
HAVING COUNT(*) >= 20
ORDER BY unread_count DESC;
```

### Основные элементы исходного плана

```text
Sort
(actual time=9169.285..9171.856 rows=168 loops=1)
Buffers: shared hit=111266 read=6026

GroupAggregate
(actual time=384.256..9171.274 rows=168 loops=1)
Rows Removed by Filter: 2475

Nested Loop
(actual time=284.125..9132.653 rows=28408 loops=1)
Join Filter: (u.user_id = dv.user_id)
Rows Removed by Join Filter: 85582067

Execution Time: 9172.173 ms
```

### Оптимизация

```sql
CREATE INDEX IF NOT EXISTS idx_delivery_delivered_pair
ON delivery_events (device_id, message_id)
INCLUDE (sent_at)
WHERE d_type = 'delivered';

CREATE INDEX IF NOT EXISTS idx_delivery_read_pair
ON delivery_events (device_id, message_id)
WHERE d_type = 'read';

CREATE INDEX IF NOT EXISTS idx_devices_user_device
ON devices (user_id, device_id);

ANALYZE delivery_events;
ANALYZE devices;
ANALYZE users;
```

### Оптимизированный SQL-запрос

```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
WITH delivered AS (
    SELECT d.device_id,
           d.message_id,
           d.sent_at
    FROM delivery_events AS d
    WHERE d.d_type = 'delivered'
),
read_pairs AS (
    SELECT DISTINCT
           r.device_id,
           r.message_id
    FROM delivery_events AS r
    WHERE r.d_type = 'read'
),
unread_by_user AS (
    SELECT dv.user_id,
           COUNT(*) AS unread_count,
           MAX(d.sent_at) AS last_unread
    FROM devices AS dv
    JOIN delivered AS d
      ON d.device_id = dv.device_id
    LEFT JOIN read_pairs AS r
      ON r.device_id = d.device_id
     AND r.message_id = d.message_id
    WHERE r.message_id IS NULL
    GROUP BY dv.user_id
    HAVING COUNT(*) >= 20
)
SELECT u.user_id,
       u.u_login,
       x.unread_count,
       x.last_unread
FROM unread_by_user AS x
JOIN users AS u
  ON u.user_id = x.user_id
WHERE u.a_status = 'active'
ORDER BY x.unread_count DESC;
```

### Фактический оптимизированный план

```text
Sort
(cost=43593.14..43595.35 rows=884 width=43)
(actual time=585.735..585.747 rows=168 loops=1)
Sort Key: x.unread_count DESC
Buffers: shared hit=14820 read=134,
temp read=1443 written=3589

CTE delivered
-> Bitmap Heap Scan on delivery_events
(cost=1775.91..14002.17 rows=158901 width=40)
(actual time=4.385..47.729 rows=160000 loops=1)

CTE read_pairs
-> HashAggregate
(cost=14800.44..15546.55 rows=74611 width=32)
(actual time=117.041..172.744 rows=159916 loops=1)
Batches: 5
Memory Usage: 9273kB
Disk Usage: 3576kB

-> Hash Right Anti Join
(cost=6803.53..12425.98 rows=119176 width=24)
(actual time=469.668..566.260 rows=32245 loops=1)

-> Hash Join
(cost=7013.22..12948.72 rows=119176 width=24)
(actual time=471.221..577.291 rows=32245 loops=1)
Hash Cond: (d.device_id = dv.device_id)

-> HashAggregate
(cost=13842.54..13880.09 rows=1001 width=32)
(actual time=584.408..584.961 rows=199 loops=1)
Group Key: dv.user_id
Filter: (count(*) >= 20)
Rows Removed by Filter: 2792

-> Hash Join
Hash Cond: (u.user_id = x.user_id)
(actual time=585.128..585.702 rows=168 loops=1)

Execution Time: 592.877 ms
```

### Сравнение второго запроса

| Показатель | До оптимизации | После оптимизации | Изменение |
|---|---:|---:|---:|
| `Execution Time` | 9172.173 мс | 592.877 мс | в 15,47 раза быстрее |
| Фактические строки | 168 | 168 | результат совпал |
| `shared hit` | 111266 | 14820 | значительно меньше |
| `shared read` | 6026 | 134 | значительно меньше |
| `temp read / written` | не указаны | 1443 / 3589 | появилась материализация CTE |
| Основное соединение | `Nested Loop` | `Hash Right Anti Join` + `Hash Join` | лишние сравнения устранены |
| `Rows Removed by Join Filter` | 85582067 | отсутствует | узкое место устранено |

## Дополнительное задание. Индекс не используется

### SQL

```sql
CREATE INDEX IF NOT EXISTS idx_delivery_type_only
ON delivery_events (d_type);

ANALYZE delivery_events;

EXPLAIN (ANALYZE, BUFFERS, COSTS, FORMAT TEXT)
SELECT *
FROM delivery_events
WHERE d_type IN (
    'received_by_server',
    'delivered',
    'read'
);
```

### Фактический план

```text
Seq Scan on delivery_events
(cost=0.00..19040.56 rows=480180 width=76)
(actual time=6.549..90.886 rows=480000 loops=1)
Filter: (d_type = ANY ('{received_by_server,delivered,read}'::delivery_event_type[]))
Rows Removed by Filter: 160041
Buffers: shared hit=8182 read=2058

Planning:
Buffers: shared hit=43 read=1 dirtied=3
Planning Time: 1.581 ms
Execution Time: 105.228 ms
```

## Итоговая таблица

| Запрос | До, мс | После, мс | Ускорение |
|---|---:|---:|---:|---|
| Последняя версия сообщения | 763.495 | 197.909 | 3.86x | 
| Непрочитанные доставки | 9172.173 | 592.877 | 15.47x |