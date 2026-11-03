-- ============================================================================
-- 04_triggers.sql
-- Триггеры схемы popov_food
-- ============================================================================

SET search_path TO popov_food, exts, public;

-- ----------------------------------------------------------------------------
-- 1. Валидация принадлежности блюда ресторану заказа (BR-7.3, Ловушка 3)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_order_product_restaurant()
RETURNS TRIGGER AS $$
DECLARE
    v_order_restaurant_id uuid;
    v_product_restaurant_id uuid;
BEGIN
    SELECT restaurant_id INTO v_order_restaurant_id
    FROM "order"
    WHERE order_id = NEW.order_id;

    SELECT restaurant_id INTO v_product_restaurant_id
    FROM product
    WHERE product_id = NEW.product_id;

    IF v_order_restaurant_id IS DISTINCT FROM v_product_restaurant_id THEN
        RAISE EXCEPTION 'Блюдо % (ресторан %) не принадлежит ресторану заказа % (ресторан %)',
            NEW.product_id, v_product_restaurant_id, NEW.order_id, v_order_restaurant_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_order_product_restaurant ON order_structure;
CREATE TRIGGER trg_check_order_product_restaurant
BEFORE INSERT OR UPDATE ON order_structure
FOR EACH ROW
EXECUTE FUNCTION check_order_product_restaurant();


-- ----------------------------------------------------------------------------
-- 2. FOOD-105: Триггер пересчёта рейтинга блюд и ресторанов (BR-9.6, BR-9.7)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rating_change()
RETURNS TRIGGER AS $$
DECLARE
    v_type review_entity_type;
    v_id uuid;
BEGIN
    -- Функция для пересчёта сущности
    -- Обрабатываем как старые (при UPDATE/DELETE), так и новые (при INSERT/UPDATE) значения
    
    -- 1. Если UPDATE или DELETE: пересчёт для OLD
    IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
        IF OLD.entity_type = 'блюдо' THEN
            UPDATE product
            SET rating = (
                SELECT round(AVG(rating), 2)
                FROM review
                WHERE entity_type = 'блюдо' AND entity_id = OLD.entity_id
            )
            WHERE product_id = OLD.entity_id;
        ELSIF OLD.entity_type = 'ресторан' THEN
            UPDATE restaurant
            SET rating = (
                SELECT round(AVG(rating), 2)
                FROM review
                WHERE entity_type = 'ресторан' AND entity_id = OLD.entity_id
            )
            WHERE restaurant_id = OLD.entity_id;
        END IF;
    END IF;

    -- 2. Если INSERT или UPDATE: пересчёт для NEW
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        IF NEW.entity_type = 'блюдо' THEN
            UPDATE product
            SET rating = (
                SELECT round(AVG(rating), 2)
                FROM review
                WHERE entity_type = 'блюдо' AND entity_id = NEW.entity_id
            )
            WHERE product_id = NEW.entity_id;
        ELSIF NEW.entity_type = 'ресторан' THEN
            UPDATE restaurant
            SET rating = (
                SELECT round(AVG(rating), 2)
                FROM review
                WHERE entity_type = 'ресторан' AND entity_id = NEW.entity_id
            )
            WHERE restaurant_id = NEW.entity_id;
        END IF;
    END IF;

    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rating_change ON review;
CREATE TRIGGER trg_rating_change
AFTER INSERT OR UPDATE OR DELETE ON review
FOR EACH ROW
EXECUTE FUNCTION rating_change();
