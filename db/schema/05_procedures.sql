-- ============================================================================
-- 05_procedures.sql
-- Процедуры управления данными:
-- FOOD-103: erase_test_data()
-- FOOD-102: insert_test_data(value int)
-- ============================================================================

SET search_path TO popov_food, exts, public;

-- Вспомогательные последовательности для генерации уникальных значений
CREATE SEQUENCE IF NOT EXISTS seq_client_num START WITH 1;
CREATE SEQUENCE IF NOT EXISTS seq_client_phone START WITH 1000000;
CREATE SEQUENCE IF NOT EXISTS seq_courier_num START WITH 1;
CREATE SEQUENCE IF NOT EXISTS seq_courier_phone START WITH 2000000;
CREATE SEQUENCE IF NOT EXISTS seq_category_num START WITH 1;
CREATE SEQUENCE IF NOT EXISTS seq_restaurant_num START WITH 1;
CREATE SEQUENCE IF NOT EXISTS seq_product_num START WITH 1;

-- ----------------------------------------------------------------------------
-- FOOD-103: Очистка тестовых данных
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE erase_test_data()
AS $$
BEGIN
    TRUNCATE TABLE
        review,
        payment,
        order_structure,
        "order",
        courier_pay,
        client_address,
        product,
        product_category,
        restaurant,
        courier,
        client,
        address
    CASCADE;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- FOOD-102: Генератор тестовых данных
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE insert_test_data(value int)
AS $$
DECLARE
    v_val int := value;
    i int;
    j int;
    m int;
    v_client_id uuid;
    v_courier_id uuid;
    v_cat_id uuid;
    v_rest_id uuid;
    v_addr_id uuid;
    v_order_id uuid;
    v_prod_id uuid;
    
    v_clients uuid[] := ARRAY[]::uuid[];
    v_couriers uuid[] := ARRAY[]::uuid[];
    v_categories uuid[] := ARRAY[]::uuid[];
    v_restaurants uuid[] := ARRAY[]::uuid[];
    v_rest_addrs uuid[] := ARRAY[]::uuid[];
    v_client_addrs uuid[] := ARRAY[]::uuid[];
    
    v_prod_ids uuid[];
    v_prod_prices numeric[];
    
    v_order_ts timestamp;
    v_delivery_ts timestamp;
    v_order_status order_status;
    v_order_amt numeric(10, 2);
    v_cur_client uuid;
    v_cur_addr uuid;
    v_cur_rest uuid;
    v_cur_courier uuid;
    v_dish1 uuid;
    v_dish2 uuid;
    v_qty1 numeric;
    v_qty2 numeric;
    
    v_comm_sum numeric;
    v_deliv_cnt int;
    v_curr_coef numeric;
    v_next_coef numeric;
    v_pay_amt numeric;
    v_m_date date;
    v_m_year int;
    v_m_month int;
    v_tot_amt numeric;
BEGIN
    IF v_val IS NULL OR v_val <= 0 THEN
        RETURN;
    END IF;

    -- 1. Адреса (всего value * 5):
    -- value адресов под рестораны (BR-11.7)
    FOR i IN 1..v_val LOOP
        v_addr_id := exts.uuid_generate_v4();
        INSERT INTO address (address_id, street, house_number, apartment_office)
        VALUES (
            v_addr_id,
            'Ресторанная ул.',
            (i + 100)::text,
            NULL
        );
        v_rest_addrs := array_append(v_rest_addrs, v_addr_id);
    END LOOP;

    -- value * 4 адресов под клиентов (BR-11.7)
    FOR i IN 1..(v_val * 4) LOOP
        v_addr_id := exts.uuid_generate_v4();
        INSERT INTO address (address_id, street, house_number, apartment_office)
        VALUES (
            v_addr_id,
            'Клиентская ул.',
            (i)::text,
            'кв. ' || (i % 100 + 1)::text
        );
        v_client_addrs := array_append(v_client_addrs, v_addr_id);
    END LOOP;

    -- 2. Клиенты: value * 1 (BR-11.7)
    FOR i IN 1..v_val LOOP
        v_client_id := exts.uuid_generate_v4();
        INSERT INTO client (client_id, login, password, phone_number)
        VALUES (
            v_client_id,
            'user_' || nextval('seq_client_num')::text || '_' || substr(replace(v_client_id::text, '-', ''), 1, 8),
            md5(random()::text),
            '+79' || lpad(nextval('seq_client_phone')::text, 9, '0')
        );
        v_clients := array_append(v_clients, v_client_id);

        -- Связываем клиента с 4 адресами из v_client_addrs (BR-2.4, BR-2.5)
        FOR j IN 1..4 LOOP
            INSERT INTO client_address (client_id, address_id)
            VALUES (v_client_id, v_client_addrs[(i - 1) * 4 + j]);
        END LOOP;
    END LOOP;

    -- 3. Курьеры: value * 1 (BR-11.7)
    FOR i IN 1..v_val LOOP
        v_courier_id := exts.uuid_generate_v4();
        IF i = 1 THEN
            -- Гарантированно активный курьер (BR-6.6, тест C.7)
            INSERT INTO courier (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
            VALUES (
                v_courier_id,
                'Курьер Активный ' || nextval('seq_courier_num')::text,
                '+78' || lpad(nextval('seq_courier_phone')::text, 9, '0'),
                'свободен',
                current_date - interval '8 months',
                NULL,
                0.1
            );
        ELSIF i = v_val AND v_val > 1 THEN
            -- Один уволенный курьер для проверки граничных условий (BR-6.3)
            INSERT INTO courier (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
            VALUES (
                v_courier_id,
                'Курьер Уволенный ' || nextval('seq_courier_num')::text,
                '+78' || lpad(nextval('seq_courier_phone')::text, 9, '0'),
                'уволен',
                current_date - interval '8 months',
                current_date - interval '1 month',
                0.1
            );
        ELSE
            INSERT INTO courier (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
            VALUES (
                v_courier_id,
                'Курьер ' || nextval('seq_courier_num')::text,
                '+78' || lpad(nextval('seq_courier_phone')::text, 9, '0'),
                'свободен',
                current_date - interval '8 months',
                NULL,
                0.1
            );
        END IF;
        v_couriers := array_append(v_couriers, v_courier_id);
    END LOOP;

    -- 4. Категории блюд: value * 1 (BR-11.7)
    FOR i IN 1..v_val LOOP
        v_cat_id := exts.uuid_generate_v4();
        INSERT INTO product_category (product_category_id, product_category_name)
        VALUES (
            v_cat_id,
            'Категория ' || nextval('seq_category_num')::text
        );
        v_categories := array_append(v_categories, v_cat_id);
    END LOOP;

    -- 5. Рестораны: value * 1 (BR-11.7)
    FOR i IN 1..v_val LOOP
        v_rest_id := exts.uuid_generate_v4();
        INSERT INTO restaurant (restaurant_id, restaurant_name, address_id, description, work_start, work_end, company_details, rating, status)
        VALUES (
            v_rest_id,
            'Ресторан ' || nextval('seq_restaurant_num')::text,
            v_rest_addrs[i],
            'Описание ресторана',
            time '09:00:00',
            time '23:00:00',
            'ИНН ' || lpad(floor(random() * 8999999999 + 1000000000)::bigint::text, 10, '0'),
            NULL,
            'активен'
        );
        v_restaurants := array_append(v_restaurants, v_rest_id);
    END LOOP;

    -- 6. Блюда: value * 5 (по 5 блюд на ресторан, BR-11.7)
    FOR i IN 1..v_val LOOP
        v_rest_id := v_restaurants[i];
        FOR j IN 1..5 LOOP
            v_prod_id := exts.uuid_generate_v4();
            INSERT INTO product (product_id, product_name, product_category_id, price, restaurant_id, photo_url, rating, status, description)
            VALUES (
                v_prod_id,
                'Блюдо ' || nextval('seq_product_num')::text || ' (Ресторан ' || i || ')',
                v_categories[(i - 1 + j - 1) % v_val + 1],
                (200.00 + j * 100.00), -- 300, 400, 500, 600, 700
                v_rest_id,
                'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg',
                NULL,
                'доступно',
                'Вкусное свежее блюдо'
            );
        END LOOP;
    END LOOP;

    -- 7. Заказы (value * 5), Состав заказа, Оплаты (value * 5), Отзывы (value * 5)
    FOR j IN 1..(v_val * 5) LOOP
        v_order_id := exts.uuid_generate_v4();
        m := (j - 1) % 6; -- распределение по 6 месяцам (0..5)
        
        -- Дата заказа внутри соответствующего месяца
        v_order_ts := date_trunc('month', current_date - (m || ' months')::interval) + interval '2 days' + (((j * 11) % 500) || ' hours')::interval;
        
        -- Курьер, ресторан, клиент
        v_cur_courier := v_couriers[(j - 1) % v_val + 1];
        v_cur_rest := v_restaurants[(j - 1) % v_val + 1];
        v_cur_client := v_clients[(j - 1) % v_val + 1];
        
        -- Адрес доставки строго из адресов данного клиента (BR-7.4)
        SELECT address_id INTO v_cur_addr
        FROM client_address
        WHERE client_id = v_cur_client
        ORDER BY address_id
        LIMIT 1;

        -- 90% заказов доставлены, 10% в процессе (для реалистичности)
        IF j % 10 != 0 THEN
            v_order_status := 'доставлен';
            v_delivery_ts := v_order_ts + interval '35 minutes';
        ELSE
            v_order_status := 'готовится';
            v_delivery_ts := NULL;
        END IF;

        -- 2 блюда строго из этого ресторана (BR-7.3)
        SELECT array_agg(product_id), array_agg(price)
        INTO v_prod_ids, v_prod_prices
        FROM (
            SELECT product_id, price
            FROM product
            WHERE restaurant_id = v_cur_rest
            ORDER BY product_id
            LIMIT 2
        ) t;
        v_dish1 := v_prod_ids[1];
        v_dish2 := v_prod_ids[2];
        v_qty1 := 2.0;
        v_qty2 := 1.0;
        v_order_amt := round(v_qty1 * v_prod_prices[1] + v_qty2 * v_prod_prices[2], 2);

        -- Вставляем заказ
        INSERT INTO "order" (
            order_id, courier_id, client_id, address_id, restaurant_id,
            order_timestamp, delivery_timestamp, order_amount, status, pay_status, description
        ) VALUES (
            v_order_id, v_cur_courier, v_cur_client, v_cur_addr, v_cur_rest,
            v_order_ts, v_delivery_ts, v_order_amt, v_order_status, 'оплачен', 'Тестовый заказ'
        );

        -- Вставляем позиции заказа
        INSERT INTO order_structure (order_id, product_id, quantity)
        VALUES
            (v_order_id, v_dish1, v_qty1),
            (v_order_id, v_dish2, v_qty2);

        -- Вставляем оплату: ровно 1 успешная оплата на заказ (BR-8.1, BR-8.4, test D.8, D.9)
        SELECT total_amount INTO v_tot_amt FROM "order" WHERE order_id = v_order_id;
        INSERT INTO payment (
            payment_id, order_id, payment_type, amount, transaction_id, payment_timestamp, status
        ) VALUES (
            exts.uuid_generate_v4(),
            v_order_id,
            'карта',
            v_tot_amt,
            exts.uuid_generate_v4(),
            v_order_ts,
            'успех'
        );

        -- Вставляем отзыв: ровно 1 отзыв на заказ (value * 5 отзывов)
        IF j % 2 = 1 THEN
            INSERT INTO review (
                review_id, client_id, order_id, review_timestamp, entity_id, entity_type, description, photo_url, rating
            ) VALUES (
                exts.uuid_generate_v4(),
                v_cur_client,
                v_order_id,
                v_order_ts + interval '1 hour',
                v_dish1,
                'блюдо',
                'Отличное блюдо, вкусно!',
                NULL,
                (3.0 + (j % 3)) -- 3.0, 4.0, 5.0
            );
        ELSE
            INSERT INTO review (
                review_id, client_id, order_id, review_timestamp, entity_id, entity_type, description, photo_url, rating
            ) VALUES (
                exts.uuid_generate_v4(),
                v_cur_client,
                v_order_id,
                v_order_ts + interval '1 hour',
                v_cur_rest,
                'ресторан',
                'Отличный ресторан!',
                NULL,
                (4.0 + (j % 2)) -- 4.0, 5.0
            );
        END IF;
    END LOOP;

    -- 8. Заполнение courier_pay за 6 месяцев по правилам BR-10.2 (test C.8)
    FOR i IN 1..array_length(v_couriers, 1) LOOP
        v_courier_id := v_couriers[i];
        v_curr_coef := 0.1; -- начальный коэффициент

        -- Идем от самого старого месяца (5 месяцев назад) к текущему (0)
        FOR m IN REVERSE 5..0 LOOP
            v_m_date := (date_trunc('month', current_date) - (m || ' months')::interval)::date;
            v_m_year := extract(year from v_m_date)::int;
            v_m_month := extract(month from v_m_date)::int;

            SELECT
                coalesce(count(*), 0),
                coalesce(sum(commission), 0)
            INTO v_deliv_cnt, v_comm_sum
            FROM "order"
            WHERE courier_id = v_courier_id
              AND status = 'доставлен'
              AND extract(year from order_timestamp) = v_m_year
              AND extract(month from order_timestamp) = v_m_month;

            v_pay_amt := round(v_comm_sum * v_curr_coef, 2);

            INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
            VALUES (v_m_year, v_m_month, v_courier_id, v_pay_amt, v_curr_coef)
            ON CONFLICT (year, month, courier_id) DO UPDATE
            SET amount = EXCLUDED.amount, coefficient_used = EXCLUDED.coefficient_used;

            -- Расчёт нового коэффициента на следующий месяц
            IF v_deliv_cnt <= 150 THEN
                v_next_coef := 0.1;
            ELSIF v_deliv_cnt <= 250 THEN
                v_next_coef := 0.2;
            ELSIF v_deliv_cnt <= 500 THEN
                v_next_coef := 0.3;
            ELSE
                v_next_coef := 0.5;
            END IF;

            -- Если курьер не уволен, коэффициент обновляется на следующий месяц
            IF NOT EXISTS (SELECT 1 FROM courier WHERE courier_id = v_courier_id AND status = 'уволен') THEN
                v_curr_coef := v_next_coef;
            END IF;
        END LOOP;

        -- Обновляем courier.coefficient итоговым коэффициентом
        UPDATE courier
        SET coefficient = v_curr_coef
        WHERE courier_id = v_courier_id AND status != 'уволен';
    END LOOP;
END;
$$ LANGUAGE plpgsql;
