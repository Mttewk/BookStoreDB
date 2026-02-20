1. Реализовать хранимую процедуру, возвращающую текстовую строку, содержащую информацию о покупателе (фамилия, район проживания, дата, сумма и название магазина последней покупки). Обработать ситуацию, когда покупатель не делал покупок.
```postgresql
-- 1.1) покупатель есть и он делал покупки
SELECT fn_инфо_о_покупателе(
  (SELECT идентификатор
   FROM покупатель
   WHERE фамилия='Потапов'
   ORDER BY идентификатор DESC
   LIMIT 1)
);
```
![Screenshot 2026-02-21 at 02.01.05.png](screenshots/Screenshot%202026-02-21%20at%2002.01.05.png)
```postgresql
-- 1.2) покупатель есть, но покупки не делал
SELECT fn_инфо_о_покупателе(
  (SELECT идентификатор
   FROM покупатель
   WHERE фамилия='Кузнецов'
   ORDER BY идентификатор DESC
   LIMIT 1)
);
```
![Screenshot 2026-02-21 at 02.03.06.png](screenshots/Screenshot%202026-02-21%20at%2002.03.06.png)

```postgresql
-- 1.3) покупателя нет
SELECT fn_инфо_о_покупателе(999999999);
```
![Screenshot 2026-02-21 at 02.04.11.png](screenshots/Screenshot%202026-02-21%20at%2002.04.11.png)

2. Добавить возраст покупателя. Добавить категорию книги. При добавлении покупки проверять, можно ли данному покупателю читать данную книгу.
-- 2.1) МОЖНО: 15 лет покупает 12+
```postgresql
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
```

![Screenshot 2026-02-21 at 02.05.49.png](screenshots/Screenshot%202026-02-21%20at%2002.05.49.png)
-- 2.2) НЕЛЬЗЯ: 15 лет покупает 18+ 
```postgresql
WITH ctx AS (
  SELECT
    (SELECT идентификатор FROM магазин ORDER BY идентификатор LIMIT 1) AS shop_id,
    (SELECT идентификатор FROM покупатель WHERE фамилия='Смирнов' ORDER BY идентификатор DESC LIMIT 1) AS buyer_id,
    (SELECT идентификатор FROM книги WHERE название='Книга18+' ORDER BY идентификатор DESC LIMIT 1) AS book_id
)
INSERT INTO покупка(дата, продавец, покупатель, книга, количество, сумма)
SELECT 'Сентябрь', shop_id, buyer_id, book_id, 1, NULL
FROM ctx;
```
![Screenshot 2026-02-21 at 02.10.18.png](screenshots/Screenshot%202026-02-21%20at%2002.10.18.png)


3. Реализовать триггер такой, что при вводе строки в таблице покупок, если сумма покупки не указана, то она вычисляется 

```postgresql
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
```
![Screenshot 2026-02-21 at 02.13.14.png](screenshots/Screenshot%202026-02-21%20at%2002.13.14.png)
![Screenshot 2026-02-21 at 02.14.05.png](screenshots/Screenshot%202026-02-21%20at%2002.14.05.png)

4. Создать представление (view), содержащее поля: номер заказа, имя покупателя, скидка, название книги, цена книги, количество и стоимость. Обеспечить возможность изменения предоставленной скидки. При этом должна быть пересчитана стоимость покупки.
```postgresql
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
```
![Screenshot 2026-02-21 at 02.15.29.png](screenshots/Screenshot%202026-02-21%20at%2002.15.29.png)
```postgresql
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
```
```postgresql
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
```
![Screenshot 2026-02-21 at 02.16.48.png](screenshots/Screenshot%202026-02-21%20at%2002.16.48.png)
