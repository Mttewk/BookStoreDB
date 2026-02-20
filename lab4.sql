BEGIN;
-- 2) Добавить возраст покупателя + категорию книги
ALTER TABLE покупатель
  ADD COLUMN IF NOT EXISTS возраст INT NOT NULL DEFAULT 18;

ALTER TABLE книги
  ADD COLUMN IF NOT EXISTS категория VARCHAR(10) NOT NULL DEFAULT '0+';

-- Backfill на случай, если столбцы уже были добавлены без default (страховка)
UPDATE покупатель SET возраст = 18 WHERE возраст IS NULL;
UPDATE книги SET категория = '0+' WHERE категория IS NULL;

-- ДОП. ПРОВЕРКИ (constraints) ДЛЯ ВОЗРАСТА / СКИДКИ / КАТЕГОРИИ
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'покупатель_возраст_chk') THEN
    ALTER TABLE покупатель
      ADD CONSTRAINT покупатель_возраст_chk
      CHECK (возраст BETWEEN 0 AND 120);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'покупатель_скидка_chk') THEN
    ALTER TABLE покупатель
      ADD CONSTRAINT покупатель_скидка_chk
      CHECK (скидка BETWEEN 0 AND 100);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'книги_категория_chk') THEN
    ALTER TABLE книги
      ADD CONSTRAINT книги_категория_chk
      CHECK (категория IN ('0+','12+','16+','18+'));
  END IF;
END $$;

-- 1) Функция: строка с инфо о покупателе + обработка "нет/нет покупок"
CREATE OR REPLACE FUNCTION fn_инфо_о_покупателе(p_покупатель_id INT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_фамилия  TEXT;
  v_район    TEXT;
  v_дата     TEXT;
  v_сумма    INT;
  v_магазин  TEXT;
BEGIN
  SELECT п.фамилия, п.район_проживания
    INTO v_фамилия, v_район
  FROM покупатель п
  WHERE п.идентификатор = p_покупатель_id;

  IF NOT FOUND THEN
    RETURN format('Покупатель с идентификатором %s не найден.', p_покупатель_id);
  END IF;

  SELECT pk.дата, pk.сумма, m.название
    INTO v_дата, v_сумма, v_магазин
  FROM покупка pk
  JOIN магазин m ON m.идентификатор = pk.продавец
  WHERE pk.покупатель = p_покупатель_id
  ORDER BY pk.номер_заказа DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN format('Покупатель: %s; район проживания: %s; покупок не совершал.', v_фамилия, v_район);
  END IF;

  RETURN format(
    'Покупатель: %s; район проживания: %s; последняя покупка: %s; сумма: %s; магазин: %s.',
    v_фамилия, v_район, v_дата, v_сумма, v_магазин
  );
END;
$$;

-- 2) + 3) Триггер на покупку:
--   - проверка возраста
--   - если сумма NULL, то посчитать
CREATE OR REPLACE FUNCTION trg_покупка_check_and_calc()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_возраст    INT;
  v_скидка     INT;
  v_категория  TEXT;
  v_стоимость  INT;
  v_min_age    INT;
BEGIN
  SELECT возраст, скидка
    INTO v_возраст, v_скидка
  FROM покупатель
  WHERE идентификатор = NEW.покупатель;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Покупатель % не найден.', NEW.покупатель;
  END IF;

  SELECT категория, стоимость
    INTO v_категория, v_стоимость
  FROM книги
  WHERE идентификатор = NEW.книга;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Книга % не найдена.', NEW.книга;
  END IF;

  v_min_age :=
    CASE v_категория
      WHEN '0+'  THEN 0
      WHEN '12+' THEN 12
      WHEN '16+' THEN 16
      WHEN '18+' THEN 18
      ELSE 0
    END;

  IF v_возраст < v_min_age THEN
    RAISE EXCEPTION
      'Покупателю % (% лет) нельзя покупать книгу категории % (требуется %+) ',
      NEW.покупатель, v_возраст, v_категория, v_min_age;
  END IF;

  IF NEW.сумма IS NULL THEN
    NEW.сумма :=
      ROUND((v_стоимость::numeric * NEW.количество::numeric) * (100 - v_скидка)::numeric / 100);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_покупка_check_and_calc ON покупка;

CREATE TRIGGER trg_покупка_check_and_calc
BEFORE INSERT OR UPDATE OF покупатель, книга, количество, сумма
ON покупка
FOR EACH ROW
EXECUTE FUNCTION trg_покупка_check_and_calc();

-- 4) VIEW + изменение скидки через VIEW
CREATE OR REPLACE VIEW vw_заказы_детально AS
SELECT
  pk.номер_заказа  AS номер_заказа,
  p.фамилия        AS имя_покупателя,
  p.скидка         AS скидка,
  k.название       AS название_книги,
  k.стоимость      AS цена_книги,
  pk.количество    AS количество,
  ROUND((k.стоимость::numeric * pk.количество::numeric) * (100 - p.скидка)::numeric / 100)::INT AS стоимость
FROM покупка pk
JOIN покупатель p ON p.идентификатор = pk.покупатель
JOIN книги k      ON k.идентификатор = pk.книга;

CREATE OR REPLACE FUNCTION trg_vw_заказы_детально_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_buyer_id INT;
BEGIN
  SELECT покупатель
    INTO v_buyer_id
  FROM покупка
  WHERE номер_заказа = OLD.номер_заказа;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Заказ % не найден.', OLD.номер_заказа;
  END IF;

  IF NEW.скидка IS DISTINCT FROM OLD.скидка THEN
    UPDATE покупатель
       SET скидка = NEW.скидка
     WHERE идентификатор = v_buyer_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vw_заказы_детально_update ON vw_заказы_детально;

CREATE TRIGGER trg_vw_заказы_детально_update
INSTEAD OF UPDATE
ON vw_заказы_детально
FOR EACH ROW
EXECUTE FUNCTION trg_vw_заказы_детально_update();

COMMIT;


--ТЕСТЫ

-- Берём любого существующего продавца
WITH shop AS (
  SELECT идентификатор AS shop_id
  FROM магазин
  ORDER BY идентификатор
  LIMIT 1
)
-- Создаём 2 покупателей:
--  - Смирнов (будет с покупкой)
--  - Кузнецов  (без покупок)
INSERT INTO покупатель(фамилия, район_проживания, скидка, возраст)
VALUES ('Смирнов', 'Нижегородский', 10, 15);

INSERT INTO покупатель(фамилия, район_проживания, скидка, возраст)
VALUES ('Кузнецов', 'Совецкий', 5, 30);

-- Создаём 2 книги:
-- Книга12+ (разрешена для 15 лет)
--  Книга18+ (запрещена для 15 лет)
INSERT INTO книги(название, стоимость, склад, количество, категория)
VALUES ('Книга12+', 500, 'Сормовский', 100, '12+');

INSERT INTO книги(название, стоимость, склад, количество, категория)
VALUES ('Книга18+', 700, 'Сормовский', 100, '18+');


/*
   ТЕСТ 1 (1.1, 1.2, 1.3) — fn_инфо_о_покупателе
   1.1) покупатель есть и он делал покупки
   1.2) покупатель есть, но покупки не делал
   1.3) покупателя нет
*/
WITH ctx AS (
  SELECT
    (SELECT идентификатор FROM магазин ORDER BY идентификатор LIMIT 1) AS shop_id,
    (SELECT идентификатор FROM покупатель WHERE фамилия='Смирнов' ORDER BY идентификатор DESC LIMIT 1) AS buyer_id,
    (SELECT идентификатор FROM книги WHERE название='Книга12+' ORDER BY идентификатор DESC LIMIT 1) AS book_id
)
INSERT INTO покупка(дата, продавец, покупатель, книга, количество, сумма)
SELECT 'Июль', shop_id, buyer_id, book_id, 2, NULL
FROM ctx
RETURNING номер_заказа, дата, продавец, покупатель, книга, количество, сумма;

-- 1.1) покупатель есть и он делал покупки
SELECT fn_инфо_о_покупателе(
  (SELECT идентификатор
   FROM покупатель
   WHERE фамилия='Потапов'
   ORDER BY идентификатор DESC
   LIMIT 1)
);

-- 1.2) покупатель есть, но покупки не делал
SELECT fn_инфо_о_покупателе(
  (SELECT идентификатор
   FROM покупатель
   WHERE фамилия='Кузнецов'
   ORDER BY идентификатор DESC
   LIMIT 1)
);

-- 1.3) покупателя нет
SELECT fn_инфо_о_покупателе(999999999);


/*
   ТЕСТ 2 — проверка "можно ли читать"
   2.1) покупатель купил книгу, которую ему можно
   2.2) покупатель хотел купить книгу, которую ему нельзя (ошибка)
 */

-- 2.1) МОЖНО: 15 лет покупает 12+
WITH ctx AS (
  SELECT
    (SELECT идентификатор FROM магазин ORDER BY идентификатор LIMIT 1) AS shop_id,
    (SELECT идентификатор FROM покупатель WHERE фамилия='Смирнов' ORDER BY идентификатор DESC LIMIT 1) AS buyer_id,
    (SELECT идентификатор FROM книги WHERE название='Книга12+' ORDER BY идентификатор DESC LIMIT 1) AS book_id
)
INSERT INTO покупка(дата, продавец, покупатель, книга, количество, сумма)
SELECT 'Август', shop_id, buyer_id, book_id, 1, NULL
FROM ctx
RETURNING номер_заказа, дата, покупатель, книга, количество, сумма;

-- 2.2) НЕЛЬЗЯ: 15 лет покупает 18+
WITH ctx AS (
  SELECT
    (SELECT идентификатор FROM магазин ORDER BY идентификатор LIMIT 1) AS shop_id,
    (SELECT идентификатор FROM покупатель WHERE фамилия='Смирнов' ORDER BY идентификатор DESC LIMIT 1) AS buyer_id,
    (SELECT идентификатор FROM книги WHERE название='Книга18+' ORDER BY идентификатор DESC LIMIT 1) AS book_id
)
INSERT INTO покупка(дата, продавец, покупатель, книга, количество, сумма)
SELECT 'Сентябрь', shop_id, buyer_id, book_id, 1, NULL
FROM ctx;

/*
   ТЕСТ 3 — триггер вычисления суммы, если сумма не указана
 */

-- Вставка с суммой NULL
WITH ctx AS (
  SELECT
    (SELECT идентификатор FROM магазин ORDER BY идентификатор LIMIT 1) AS shop_id,
    (SELECT идентификатор FROM покупатель WHERE фамилия='Смирнов' ORDER BY идентификатор DESC LIMIT 1) AS buyer_id,
    (SELECT идентификатор FROM книги WHERE название='Книга12+' ORDER BY идентификатор DESC LIMIT 1) AS book_id
)
INSERT INTO покупка(дата, продавец, покупатель, книга, количество, сумма)
SELECT 'Октябрь', shop_id, buyer_id, book_id, 3, NULL
FROM ctx
RETURNING номер_заказа, дата, количество, сумма;

SELECT номер_заказа, дата, продавец, покупатель, книга, количество, сумма
FROM покупка
WHERE покупатель = (SELECT идентификатор FROM покупатель WHERE фамилия='Смирнов' ORDER BY идентификатор DESC LIMIT 1)
ORDER BY номер_заказа;


/*
   ТЕСТ 4 — VIEW + изменение скидки + пересчёт стоимости
   "показать до/после"
*/

-- 4.1) ДО: показать строку из view
SELECT *
FROM vw_заказы_детально
WHERE номер_заказа = (
  SELECT номер_заказа
  FROM покупка
  WHERE покупатель = (SELECT идентификатор FROM покупатель WHERE фамилия='Попов' ORDER BY идентификатор DESC LIMIT 1)
  ORDER BY номер_заказа
  LIMIT 1
);

-- 4.2) Обновим скидку через VIEW
UPDATE vw_заказы_детально
SET скидка = 25
WHERE номер_заказа = (
  SELECT номер_заказа
  FROM покупка
  WHERE покупатель = (SELECT идентификатор FROM покупатель WHERE фамилия='Попов' ORDER BY идентификатор DESC LIMIT 1)
  ORDER BY номер_заказа
  LIMIT 1
);

-- 4.3) ПОСЛЕ: снова показать строку из view (стоимость должна измениться)
SELECT *
FROM vw_заказы_детально
WHERE номер_заказа = (
  SELECT номер_заказа
  FROM покупка
  WHERE покупатель = (SELECT идентификатор FROM покупатель WHERE фамилия='Попов' ORDER BY идентификатор DESC LIMIT 1)
  ORDER BY номер_заказа
  LIMIT 1
);