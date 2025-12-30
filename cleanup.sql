-- Очистка всех таблиц с русскими названиями
-- Удаляем в правильном порядке (из-за внешних ключей)

-- 1. Сначала таблицу с внешними ключами (покупки)
DROP TABLE IF EXISTS покупка CASCADE;

-- 2. Затем основные таблицы (в любом порядке)
DROP TABLE IF EXISTS покупатель CASCADE;
DROP TABLE IF EXISTS магазин CASCADE;
DROP TABLE IF EXISTS книги CASCADE;

-- Сообщение об успешном удалении
DO $$
BEGIN
    RAISE NOTICE '✅ Все таблицы успешно удалены';
END $$;