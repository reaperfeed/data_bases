/* ================================================================
   0. Подготовка собственных данных
   ================================================================*/

BEGIN;

DELETE FROM admin_actions
WHERE action_id IN (
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
    '87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid
)
OR object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid;

DELETE FROM decisions
WHERE decision_id = 'e62f6466-8104-4aa2-bb74-646025fcf428'::uuid;

DELETE FROM objects
WHERE object_id IN (
    'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid,
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
    '87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid
);

WITH template AS (
    SELECT o AS value
    FROM objects AS o
    ORDER BY o.object_id
    LIMIT 1
), demo_ids(object_id) AS (
    VALUES
        ('a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid),
        ('a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid),
        ('87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid)
)
INSERT INTO objects
SELECT (jsonb_populate_record(
    NULL::objects,
    jsonb_set(to_jsonb(template.value), '{object_id}', to_jsonb(demo_ids.object_id), true)
)).*
FROM template
CROSS JOIN demo_ids;

WITH template AS (
    SELECT d AS value
    FROM decisions AS d
    ORDER BY d.decision_id
    LIMIT 1
)
INSERT INTO decisions
SELECT (jsonb_populate_record(
    NULL::decisions,
    jsonb_set(to_jsonb(template.value), '{decision_id}', to_jsonb('e62f6466-8104-4aa2-bb74-646025fcf428'::uuid), true)
)).*
FROM template;

COMMIT;

/* ================================================================
   1. Наивный вариант
   ================================================================
*/

/* T1 */
BEGIN;

SELECT NOT EXISTS (
    SELECT 1
    FROM admin_actions
    WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
      AND action_type = (SELECT action_type FROM admin_actions ORDER BY executed_at LIMIT 1)
      AND reason = 'LR8_NAIVE'
) AS resource_is_free;

SELECT pg_sleep(3);

INSERT INTO admin_actions
    (action_id, object_id, user_id, decision_id, executed_at, action_type, reason, duration)
VALUES
    ('a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
     'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid,
     (SELECT user_id FROM admin_actions ORDER BY executed_at LIMIT 1),
     'e62f6466-8104-4aa2-bb74-646025fcf428'::uuid,
     clock_timestamp(),
     (SELECT action_type FROM admin_actions ORDER BY executed_at LIMIT 1),
     'LR8_NAIVE',
     (SELECT duration FROM admin_actions ORDER BY executed_at LIMIT 1));

COMMIT;

/* T2 */
BEGIN;

SELECT NOT EXISTS (
    SELECT 1
    FROM admin_actions
    WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
      AND action_type = (SELECT action_type FROM admin_actions ORDER BY executed_at LIMIT 1)
      AND reason = 'LR8_NAIVE'
) AS resource_is_free;

INSERT INTO admin_actions
    (action_id, object_id, user_id, decision_id, executed_at, action_type, reason, duration)
VALUES
    ('87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid,
     'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid,
     (SELECT user_id FROM admin_actions ORDER BY executed_at LIMIT 1),
     'e62f6466-8104-4aa2-bb74-646025fcf428'::uuid,
     clock_timestamp(),
     (SELECT action_type FROM admin_actions ORDER BY executed_at LIMIT 1),
     'LR8_NAIVE',
     (SELECT duration FROM admin_actions ORDER BY executed_at LIMIT 1));

COMMIT;

SELECT object_id, action_type, COUNT(*) AS copies
FROM admin_actions
WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
  AND reason = 'LR8_NAIVE'
GROUP BY object_id, action_type;

BEGIN;
DELETE FROM admin_actions WHERE reason = 'LR8_NAIVE';
COMMIT;

/* Очистка перед следующим вариантом.
   Если предыдущая команда завершилась ошибкой, сначала выполните ROLLBACK. */
BEGIN;

DELETE FROM admin_actions
WHERE action_id IN (
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
    '87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid
)
OR (object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
    AND reason LIKE 'LR8_%');

COMMIT;
/* ================================================================
   2. Исправление 1. SELECT ... FOR UPDATE
   ================================================================ 
*/

/* T1 */
BEGIN;
SELECT object_id
FROM objects
WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
FOR UPDATE;

SELECT pg_sleep(3);

INSERT INTO admin_actions
    (action_id, object_id, user_id, decision_id, executed_at, action_type, reason, duration)
SELECT
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
    'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid,
    (SELECT user_id FROM admin_actions ORDER BY executed_at LIMIT 1),
    'e62f6466-8104-4aa2-bb74-646025fcf428'::uuid,
    clock_timestamp(),
    (SELECT action_type FROM admin_actions ORDER BY executed_at LIMIT 1),
    'LR8_FOR_UPDATE',
    (SELECT duration FROM admin_actions ORDER BY executed_at LIMIT 1)
WHERE NOT EXISTS (
    SELECT 1 FROM admin_actions
    WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
      AND reason = 'LR8_FOR_UPDATE'
);
COMMIT;

/* T2 */
BEGIN;
SELECT object_id
FROM objects
WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
FOR UPDATE;

INSERT INTO admin_actions
    (action_id, object_id, user_id, decision_id, executed_at, action_type, reason, duration)
SELECT
    '87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid,
    'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid,
    (SELECT user_id FROM admin_actions ORDER BY executed_at LIMIT 1),
    'e62f6466-8104-4aa2-bb74-646025fcf428'::uuid,
    clock_timestamp(),
    (SELECT action_type FROM admin_actions ORDER BY executed_at LIMIT 1),
    'LR8_FOR_UPDATE',
    (SELECT duration FROM admin_actions ORDER BY executed_at LIMIT 1)
WHERE NOT EXISTS (
    SELECT 1 FROM admin_actions
    WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
      AND reason = 'LR8_FOR_UPDATE'
);
COMMIT;

SELECT object_id, action_type, COUNT(*) AS copies
FROM admin_actions
WHERE reason = 'LR8_FOR_UPDATE'
GROUP BY object_id, action_type;

BEGIN;
DELETE FROM admin_actions WHERE reason = 'LR8_FOR_UPDATE';
COMMIT;

/* Очистка перед следующим вариантом.
   Если предыдущая команда завершилась ошибкой, сначала выполните ROLLBACK. */
BEGIN;

DELETE FROM admin_actions
WHERE action_id IN (
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
    '87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid
)
OR (object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
    AND reason LIKE 'LR8_%');

COMMIT;
/* ================================================================
   3. Исправление 2. SELECT ... FOR NO KEY UPDATE
   ================================================================
*/

/* T1 */
BEGIN;

SELECT object_id
FROM objects
WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
FOR NO KEY UPDATE;

SELECT pg_sleep(3);

INSERT INTO admin_actions
    (action_id, object_id, user_id, decision_id, executed_at, action_type, reason, duration)
SELECT
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
    'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid,
    (SELECT user_id FROM admin_actions ORDER BY executed_at LIMIT 1),
    'e62f6466-8104-4aa2-bb74-646025fcf428'::uuid,
    clock_timestamp(),
    (SELECT action_type FROM admin_actions ORDER BY executed_at LIMIT 1),
    'LR8_NO_KEY_UPDATE',
    (SELECT duration FROM admin_actions ORDER BY executed_at LIMIT 1)
WHERE NOT EXISTS (
    SELECT 1 FROM admin_actions
    WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
      AND reason = 'LR8_NO_KEY_UPDATE'
);

COMMIT;

/* T2 */
BEGIN;

SELECT object_id
FROM objects
WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
FOR NO KEY UPDATE;

INSERT INTO admin_actions
    (action_id, object_id, user_id, decision_id, executed_at, action_type, reason, duration)
SELECT
    '87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid,
    'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid,
    (SELECT user_id FROM admin_actions ORDER BY executed_at LIMIT 1),
    'e62f6466-8104-4aa2-bb74-646025fcf428'::uuid,
    clock_timestamp(),
    (SELECT action_type FROM admin_actions ORDER BY executed_at LIMIT 1),
    'LR8_NO_KEY_UPDATE',
    (SELECT duration FROM admin_actions ORDER BY executed_at LIMIT 1)
WHERE NOT EXISTS (
    SELECT 1 FROM admin_actions
    WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
      AND reason = 'LR8_NO_KEY_UPDATE'
);

COMMIT;

SELECT object_id, action_type, COUNT(*) AS copies
FROM admin_actions
WHERE reason = 'LR8_NO_KEY_UPDATE'
GROUP BY object_id, action_type;

BEGIN;
DELETE FROM admin_actions WHERE reason = 'LR8_NO_KEY_UPDATE';
COMMIT;
/* Очистка перед следующим вариантом */
BEGIN;

DELETE FROM admin_actions
WHERE action_id IN (
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
    '87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid
)
OR (object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
    AND reason LIKE 'LR8_%');

COMMIT;
/* ================================================================
   4. Deadlock
   ================================================================
*/

/* T1 */
BEGIN;
SELECT object_id FROM objects
WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
FOR UPDATE;
SELECT pg_sleep(2);
SELECT object_id FROM objects
WHERE object_id = 'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid
FOR UPDATE;
ROLLBACK;

/* T2 */
BEGIN;
SELECT object_id FROM objects
WHERE object_id = 'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid
FOR UPDATE;
SELECT pg_sleep(2);
SELECT object_id FROM objects
WHERE object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid
FOR UPDATE;
ROLLBACK;

/* Единый порядок блокировок устраняет deadlock */
BEGIN;
SELECT object_id
FROM objects
WHERE object_id IN (
    'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid,
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid
)
ORDER BY object_id
FOR UPDATE;
COMMIT;

/* ================================================================
   5. Финальная очистка
   ================================================================ */

BEGIN;
DELETE FROM admin_actions
WHERE action_id IN (
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
    '87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid
)
OR object_id = 'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid;

DELETE FROM decisions
WHERE decision_id = 'e62f6466-8104-4aa2-bb74-646025fcf428'::uuid;

DELETE FROM objects
WHERE object_id IN (
    'a5a0478f-fbd2-4846-8263-821b9d16f121'::uuid,
    'a2c8d1ea-f04e-48e2-a7f3-9ce8ce794a8f'::uuid,
    '87eb621c-649e-44f1-8d62-8ab5c3a82eeb'::uuid
);
COMMIT;


