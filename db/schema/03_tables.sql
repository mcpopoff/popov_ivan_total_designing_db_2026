-- ============================================================================
-- 03_tables.sql
-- Таблицы и ограничения схемы popov_food (FOOD-101, 3НФ)
-- ============================================================================

SET search_path TO popov_food, exts, public;

-- 1. Клиенты (BR-2.1 - BR-2.6)
CREATE TABLE client (
    client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login varchar(50) NOT NULL UNIQUE,
    password varchar(32) NOT NULL,
    phone_number varchar(20) NOT NULL UNIQUE,
    CONSTRAINT chk_client_login_not_empty CHECK (length(trim(login)) > 0),
    CONSTRAINT chk_client_password_md5 CHECK (length(password) = 32),
    CONSTRAINT chk_client_phone_not_empty CHECK (length(trim(phone_number)) > 0)
);

-- 2. Физические адреса (BR-3.1 - BR-3.5)
CREATE TABLE address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(100) NOT NULL,
    house_number varchar(20) NOT NULL,
    apartment_office varchar(20) NULL,
    CONSTRAINT chk_address_street_not_empty CHECK (length(trim(street)) > 0),
    CONSTRAINT chk_address_house_not_empty CHECK (length(trim(house_number)) > 0),
    CONSTRAINT chk_address_apt_not_empty CHECK (apartment_office IS NULL OR length(trim(apartment_office)) > 0)
);

-- 3. Связь клиентов и адресов M:N (BR-2.4, BR-2.5, BR-3.4)
CREATE TABLE client_address (
    client_id uuid NOT NULL REFERENCES client (client_id) ON DELETE CASCADE,
    address_id uuid NOT NULL REFERENCES address (address_id) ON DELETE RESTRICT,
    PRIMARY KEY (client_id, address_id)
);

-- 4. Рестораны (BR-4.1 - BR-4.5, BR-3.3)
CREATE TABLE restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100) NOT NULL,
    address_id uuid NOT NULL UNIQUE REFERENCES address (address_id) ON DELETE RESTRICT,
    description text NOT NULL,
    work_start time NOT NULL,
    work_end time NOT NULL,
    company_details text NOT NULL,
    rating numeric(3, 2) NULL,
    status restaurant_status NOT NULL DEFAULT 'активен',
    CONSTRAINT chk_restaurant_name_not_empty CHECK (length(trim(restaurant_name)) > 0),
    CONSTRAINT chk_restaurant_desc_not_empty CHECK (length(trim(description)) > 0),
    CONSTRAINT chk_restaurant_details_not_empty CHECK (length(trim(company_details)) > 0),
    CONSTRAINT chk_restaurant_work_hours CHECK (work_end > work_start),
    CONSTRAINT chk_restaurant_rating CHECK (rating IS NULL OR (rating >= 0 AND rating <= 5))
);

-- 5. Курьеры (BR-6.1 - BR-6.6)
CREATE TABLE courier (
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio varchar(100) NOT NULL,
    phone_number varchar(20) NOT NULL UNIQUE,
    status courier_status NOT NULL DEFAULT 'свободен',
    hire_date date NOT NULL,
    dismissal_date date NULL,
    coefficient numeric(3, 2) NOT NULL DEFAULT 0.1,
    CONSTRAINT chk_courier_fio_not_empty CHECK (length(trim(fio)) > 0),
    CONSTRAINT chk_courier_phone_not_empty CHECK (length(trim(phone_number)) > 0),
    CONSTRAINT chk_courier_coefficient CHECK (coefficient >= 0.1 AND coefficient <= 0.5),
    CONSTRAINT chk_courier_dates CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date),
    CONSTRAINT chk_courier_dismissal_status CHECK (status != 'уволен' OR dismissal_date IS NOT NULL)
);

-- 6. Ежемесячные выплаты курьерам (BR-10.1 - BR-10.4)
CREATE TABLE courier_pay (
    year int NOT NULL,
    month int NOT NULL,
    courier_id uuid NOT NULL REFERENCES courier (courier_id) ON DELETE CASCADE,
    amount numeric(12, 2) NOT NULL,
    coefficient_used numeric(3, 2) NOT NULL,
    PRIMARY KEY (year, month, courier_id),
    CONSTRAINT chk_courier_pay_year CHECK (year >= 2000),
    CONSTRAINT chk_courier_pay_month CHECK (month >= 1 AND month <= 12),
    CONSTRAINT chk_courier_pay_amount CHECK (amount >= 0),
    CONSTRAINT chk_courier_pay_coef CHECK (coefficient_used >= 0.1 AND coefficient_used <= 0.5)
);

-- 7. Категории блюд (BR-5.7)
CREATE TABLE product_category (
    product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(100) NOT NULL UNIQUE,
    CONSTRAINT chk_category_name_not_empty CHECK (length(trim(product_category_name)) > 0)
);

-- 8. Блюда (BR-5.1 - BR-5.6)
CREATE TABLE product (
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name varchar(100) NOT NULL,
    product_category_id uuid NOT NULL REFERENCES product_category (product_category_id) ON DELETE RESTRICT,
    price numeric(10, 2) NOT NULL,
    restaurant_id uuid NOT NULL REFERENCES restaurant (restaurant_id) ON DELETE CASCADE,
    photo_url text NULL,
    rating numeric(3, 2) NULL,
    status product_status NOT NULL DEFAULT 'доступно',
    description text NOT NULL,
    CONSTRAINT chk_product_name_not_empty CHECK (length(trim(product_name)) > 0),
    CONSTRAINT chk_product_desc_not_empty CHECK (length(trim(description)) > 0),
    CONSTRAINT chk_product_price CHECK (price >= 0),
    CONSTRAINT chk_product_rating CHECK (rating IS NULL OR (rating >= 0 AND rating <= 5))
);

-- 9. Заказы (BR-7.1 - BR-7.13, BR-13.1)
CREATE TABLE "order" (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id uuid NOT NULL REFERENCES courier (courier_id) ON DELETE RESTRICT,
    client_id uuid NOT NULL REFERENCES client (client_id) ON DELETE RESTRICT,
    address_id uuid NOT NULL REFERENCES address (address_id) ON DELETE RESTRICT,
    restaurant_id uuid NOT NULL REFERENCES restaurant (restaurant_id) ON DELETE RESTRICT,
    order_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp NULL,
    order_amount numeric(10, 2) NOT NULL,
    commission numeric(10, 2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,
    total_amount numeric(10, 2) GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED,
    status order_status NOT NULL DEFAULT 'создан',
    pay_status order_pay_status NOT NULL DEFAULT 'ожидает',
    description text NULL,
    CONSTRAINT chk_order_amount_non_negative CHECK (order_amount >= 0),
    CONSTRAINT chk_order_min_total CHECK (total_amount >= 1000),
    CONSTRAINT chk_order_delivery_time CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CONSTRAINT fk_order_client_address FOREIGN KEY (client_id, address_id)
        REFERENCES client_address (client_id, address_id) ON DELETE RESTRICT
);

-- 10. Состав заказа (BR-7.14 - BR-7.16)
CREATE TABLE order_structure (
    order_id uuid NOT NULL REFERENCES "order" (order_id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES product (product_id) ON DELETE RESTRICT,
    quantity numeric(8, 3) NOT NULL,
    PRIMARY KEY (order_id, product_id),
    CONSTRAINT chk_order_structure_quantity CHECK (quantity > 0)
);

-- 11. Попытки оплаты (BR-8.1 - BR-8.6)
CREATE TABLE payment (
    payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES "order" (order_id) ON DELETE CASCADE,
    payment_type payment_type NOT NULL,
    amount numeric(10, 2) NOT NULL,
    transaction_id uuid NOT NULL UNIQUE DEFAULT exts.uuid_generate_v4(),
    payment_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    status payment_status NOT NULL DEFAULT 'в_обработке',
    CONSTRAINT chk_payment_amount_non_negative CHECK (amount >= 0)
);

-- Ровно одна успешная попытка оплаты на заказ (BR-8.1)
CREATE UNIQUE INDEX uq_payment_one_success_per_order ON payment (order_id) WHERE status = 'успех';

-- 12. Отзывы (BR-9.1 - BR-9.5)
CREATE TABLE review (
    review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id uuid NOT NULL REFERENCES client (client_id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES "order" (order_id) ON DELETE CASCADE,
    review_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    entity_id uuid NOT NULL,
    entity_type review_entity_type NOT NULL,
    description text NOT NULL,
    photo_url text NULL,
    rating numeric(2, 1) NOT NULL,
    CONSTRAINT chk_review_rating_range CHECK (rating >= 1 AND rating <= 5),
    CONSTRAINT chk_review_desc_not_empty CHECK (length(trim(description)) > 0),
    CONSTRAINT uq_review_order_entity UNIQUE (order_id, entity_type, entity_id)
);
