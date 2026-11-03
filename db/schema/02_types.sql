-- ============================================================================
-- 02_types.sql
-- Перечислимые типы (ENUM) для схемы popov_food
-- ============================================================================

SET search_path TO popov_food, exts, public;

-- Статус ресторана (BR-4.3)
CREATE TYPE restaurant_status AS ENUM (
    'активен',
    'неактивен'
);

-- Статус блюда (BR-5.5)
CREATE TYPE product_status AS ENUM (
    'доступно',
    'нет_в_наличии',
    'архив'
);

-- Статус курьера (BR-6.2)
CREATE TYPE courier_status AS ENUM (
    'свободен',
    'занят',
    'на_доставке',
    'уволен'
);

-- Статус заказа (BR-7.7)
CREATE TYPE order_status AS ENUM (
    'создан',
    'готовится',
    'в_доставке',
    'доставлен',
    'отменён'
);

-- Статус оплаты заказа (BR-7.9)
CREATE TYPE order_pay_status AS ENUM (
    'ожидает',
    'оплачен',
    'ошибка'
);

-- Статус попытки платежа (BR-8.2)
CREATE TYPE payment_status AS ENUM (
    'успех',
    'ошибка',
    'в_обработке'
);

-- Тип оплаты (BR-8.2)
CREATE TYPE payment_type AS ENUM (
    'карта',
    'наличные',
    'безнал'
);

-- Тип сущности отзыва (BR-9.1)
CREATE TYPE review_entity_type AS ENUM (
    'блюдо',
    'ресторан',
    'заказ'
);
