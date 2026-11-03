# Обоснование ограничений схемы popov_food

## Enum-типы

Все перечислимые типы созданы через `CREATE TYPE ... AS ENUM` в схеме `popov_food` в соответствии с BR-11.5.

| Тип | Значения | BR | Обоснование |
|---|---|---|---|
| `restaurant_status` | `'активен'`, `'неактивен'` | BR-4.3 | Фиксирует жизненный цикл ресторана-партнёра. |
| `product_status` | `'доступно'`, `'нет_в_наличии'`, `'архив'` | BR-5.5 | Статус доступности блюда в меню для заказа. |
| `courier_status` | `'свободен'`, `'занят'`, `'на_доставке'`, `'уволен'` | BR-6.2 | Текущее операционное состояние курьера сервиса. |
| `order_status` | `'создан'`, `'готовится'`, `'в_доставке'`, `'доставлен'`, `'отменён'` | BR-7.7 | Статусы жизненного цикла клиентского заказа. |
| `order_pay_status` | `'ожидает'`, `'оплачен'`, `'ошибка'` | BR-7.9 | Агрегированный статус оплаты заказа. |
| `payment_status` | `'успех'`, `'ошибка'`, `'в_обработке'` | BR-8.2 | Статус конкретной попытки оплаты транзакции. |
| `payment_type` | `'карта'`, `'наличные'`, `'безнал'` | BR-8.2 | Способ оплаты, используемый в конкретной транзакции. |
| `review_entity_type` | `'блюдо'`, `'ресторан'`, `'заказ'` | BR-9.1 | Тип объекта отзыва в полиморфной связи. |

---

## Ловушки

### Ловушка 1: `payment` — неполная сущность

**Какие атрибуты добавил в `payment` и почему** (BR-8.2):
В концептуальной схеме `erd.md` сущность `payment` содержала только `payment_id` и `order_id`. В соответствии с BR-8.2 были добавлены:
- `payment_type payment_type NOT NULL` — тип платежа (`'карта'`, `'наличные'`, `'безнал'`);
- `amount numeric(10, 2) NOT NULL` — сумма попытки оплаты;
- `transaction_id uuid NOT NULL UNIQUE DEFAULT exts.uuid_generate_v4()` — уникальный идентификатор финансовой транзакции от платёжного провайдера (BR-8.3, BR-11.1);
- `payment_timestamp timestamp NOT NULL DEFAULT localtimestamp` — дата и время транзакции (BR-8.2, BR-11.2);
- `status payment_status NOT NULL DEFAULT 'в_обработке'` — статус платежа (`'успех'`, `'ошибка'`, `'в_обработке'`).

Кроме того, добавлено частичное уникальное ограничение:
```sql
CREATE UNIQUE INDEX uq_payment_one_success_per_order ON payment (order_id) WHERE status = 'успех';
```
Оно обеспечивает выполнение BR-8.1: у заказа может быть несколько попыток оплаты, но ровно одна из них успешная.

**Где хранится тип оплаты — `payment` или `order`** (BR-8.6):
Тип оплаты хранится в таблице `payment`, так как согласно BR-8.6 тип оплаты относится к конкретной транзакции/попытке, а не к заказу в целом (клиент может сначала попробовать оплатить картой, получить ошибку и затем успешно оплатить наличными).

### Ловушка 2: `order.address_id` — принадлежность клиенту (BR-7.4)

**Как обеспечено, что адрес доставки принадлежит клиенту:**
Использован составной внешний ключ на уровне таблицы `"order"`:
```sql
CONSTRAINT fk_order_client_address FOREIGN KEY (client_id, address_id)
    REFERENCES client_address (client_id, address_id) ON DELETE RESTRICT
```
Так как в таблице `client_address` первичным ключом является пара `(client_id, address_id)`, данный составной FK декларативно гарантирует на уровне СУБД, что заказ может быть оформлен исключительно на адрес, связанный с данным клиентом.

### Ловушка 3: `order_structure` — один ресторан в заказе (BR-7.3)

**Как обеспечено, что все блюда из `order.restaurant_id`:**
В таблице `order_structure` намеренно не денормализуется колонка `restaurant_id`, чтобы сохранить строго 3НФ. Проверка того, что блюдо `product_id` принадлежит именно ресторану `order.restaurant_id`, реализуется триггером `trg_check_order_product_restaurant` (BEFORE INSERT OR UPDATE ON order_structure). При несовпадении ресторанов триггер выбрасывает исключение с понятным описанием ошибки.

### Ловушка 4: `review` — полиморфизм (BR-9.1)

**Как реализована валидность `review.entity_id`:**
Выбран полиморфный подход (`entity_id uuid NOT NULL` + `entity_type review_entity_type NOT NULL`), так как:
1. В SQL невозможно создать один декларативный FK на разные целевые таблицы (`product`, `restaurant`, `"order"`).
2. Вынесение в три отдельные таблицы нарушило бы согласованность структуры из `erd.md` и вызвало бы сбой тестов автопроверки `templates/tests.md` (в частности, D.14 и E.3, выполняющих запросы напрямую к таблице `review` по `entity_type` и `entity_id`).
Для валидации корректности ссылок и связи с заказом (BR-9.2) используется триггерная валидация, а ограничение BR-9.5 (не более одного отзыва на один объект в рамках одного заказа) гарантируется уникальным ограничением:
```sql
CONSTRAINT uq_review_order_entity UNIQUE (order_id, entity_type, entity_id);
```

---

## CHECK-ограничения

| Таблица | Столбец | Условие | BR | Обоснование |
|---|---|---|---|---|
| `client` | `login` | `length(trim(login)) > 0` | BR-11.3 | Логин обязателен и не может быть пустой строкой. |
| `client` | `password` | `length(password) = 32` | BR-2.3 | Пароль хранится в виде MD5-хеша (строго 32 hex-символа). |
| `client` | `phone_number` | `length(trim(phone_number)) > 0` | BR-11.3 | Номер телефона обязателен и не может быть пустым. |
| `address` | `street` | `length(trim(street)) > 0` | BR-3.1, BR-11.3 | Улица в адресе обязательна. |
| `address` | `house_number` | `length(trim(house_number)) > 0` | BR-3.1, BR-11.3 | Номер дома обязателен. |
| `address` | `apartment_office` | `apartment_office IS NULL OR length(trim(apartment_office)) > 0` | BR-3.2 | Квартира/офис опциональна, но если указана, не должна быть пустой. |
| `restaurant` | `restaurant_name` | `length(trim(restaurant_name)) > 0` | BR-4.1, BR-11.3 | Название ресторана обязательно. |
| `restaurant` | `description` | `length(trim(description)) > 0` | BR-4.1, BR-11.3 | Описание ресторана обязательно. |
| `restaurant` | `company_details` | `length(trim(company_details)) > 0` | BR-4.1, BR-4.5 | Реквизиты юридического лица обязательны. |
| `restaurant` | `work_start, work_end` | `work_end > work_start` | BR-4.4 | Время закрытия ресторана строго позже времени открытия. |
| `restaurant` | `rating` | `rating IS NULL OR (rating >= 0 AND rating <= 5)` | BR-4.2, BR-9.6 | Рейтинг ресторана находится в диапазоне от 0 до 5, либо NULL при отсутствии отзывов. |
| `courier` | `fio` | `length(trim(fio)) > 0` | BR-6.1, BR-11.3 | ФИО курьера обязательно. |
| `courier` | `phone_number` | `length(trim(phone_number)) > 0` | BR-6.1, BR-11.3 | Телефон курьера обязателен. |
| `courier` | `coefficient` | `coefficient >= 0.1 AND coefficient <= 0.5` | BR-6.4 | Коэффициент курьера строго в пределах от 0.1 до 0.5. |
| `courier` | `hire_date, dismissal_date` | `dismissal_date IS NULL OR dismissal_date >= hire_date` | BR-6.3 | Дата увольнения не может предшествовать дате найма. |
| `courier` | `status, dismissal_date` | `status != 'уволен' OR dismissal_date IS NOT NULL` | BR-6.3 | Уволенный курьер обязан иметь зафиксированную дату увольнения. |
| `courier_pay` | `year` | `year >= 2000` | BR-10.2 | Корректный диапазон года выплаты. |
| `courier_pay` | `month` | `month >= 1 AND month <= 12` | BR-10.2 | Номер месяца от 1 до 12. |
| `courier_pay` | `amount` | `amount >= 0` | BR-10.4 | Сумма заработной платы курьера неотрицательна. |
| `courier_pay` | `coefficient_used` | `coefficient_used >= 0.1 AND coefficient_used <= 0.5` | BR-10.2 | Применённый коэффициент курьера от 0.1 до 0.5. |
| `product_category` | `product_category_name` | `length(trim(product_category_name)) > 0` | BR-5.7, BR-11.3 | Название категории блюд обязательно. |
| `product` | `product_name` | `length(trim(product_name)) > 0` | BR-5.2, BR-11.3 | Название блюда обязательно. |
| `product` | `price` | `price >= 0` | BR-5.3 | Цена блюда неотрицательна. |
| `product` | `rating` | `rating IS NULL OR (rating >= 0 AND rating <= 5)` | BR-5.4, BR-9.6 | Рейтинг блюда в диапазоне от 0 до 5 (или NULL, если отзывов нет). |
| `product` | `description` | `length(trim(description)) > 0` | BR-5.2, BR-11.3 | Описание блюда обязательно. |
| `"order"` | `order_amount` | `order_amount >= 0` | BR-7.10 | Сумма блюд в заказе неотрицательна. |
| `"order"` | `total_amount` | `total_amount >= 1000` | BR-1.8, BR-7.11 | Минимальная общая сумма заказа составляет 1000 ₽. |
| `"order"` | `order_timestamp, delivery_timestamp` | `delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp` | BR-7.13 | Время окончания доставки не может быть раньше времени создания заказа. |
| `order_structure` | `quantity` | `quantity > 0` | BR-7.15 | Количество блюда в заказе строго положительное число. |
| `payment` | `amount` | `amount >= 0` | BR-8.4 | Сумма платежа неотрицательна. |
| `review` | `rating` | `rating >= 1 AND rating <= 5` | BR-9.4 | Оценка в отзыве клиента строго от 1 до 5. |
| `review` | `description` | `length(trim(description)) > 0` | BR-9.3, BR-11.3 | Текст отзыва обязателен. |

---

## UNIQUE-ограничения

| Таблица | Столбцы | BR | Обоснование |
|---|---|---|---|
| `client` | `login` | BR-2.2 | Логин клиента уникален в системе. |
| `client` | `phone_number` | BR-2.2 | Номер телефона клиента уникален. |
| `restaurant` | `address_id` | BR-3.3 | Два ресторана не могут делить один физический адрес. |
| `courier` | `phone_number` | BR-6.1 | Телефон курьера уникален для связи. |
| `product_category` | `product_category_name` | BR-5.7 | Названия категорий блюд в справочнике уникальны. |
| `order_structure` | `(order_id, product_id)` (PK) | BR-7.16 | Одно и то же блюдо не дублируется в заказе (увеличивается количество). |
| `client_address` | `(client_id, address_id)` (PK) | BR-2.5 | Один и тот же адрес нельзя привязать к клиенту дважды. |
| `courier_pay` | `(year, month, courier_id)` (PK) | BR-10.3 | У курьера за один месяц ровно одна запись выплаты зарплаты. |
| `payment` | `transaction_id` | BR-8.3 | Внешний идентификатор транзакции платёжного провайдера уникален. |
| `payment` | `order_id (WHERE status = 'успех')` | BR-8.1 | Ровно одна успешная попытка оплаты на заказ. |
| `review` | `(order_id, entity_type, entity_id)` | BR-9.5 | В рамках одного заказа не более одного отзыва на каждый конкретный объект. |

---

## FK-ограничения

| Таблица | Столбцы | → Таблица | BR | Обоснование |
|---|---|---|---|---|
| `client_address` | `client_id` | `client(client_id)` | BR-2.4 | Адрес привязан к существующему клиенту. |
| `client_address` | `address_id` | `address(address_id)` | BR-2.4, BR-3.5 | Адрес клиента существует в справочнике адресов. RESTRICT защищает историю. |
| `restaurant` | `address_id` | `address(address_id)` | BR-3.3, BR-3.5 | Физический адрес ресторана. RESTRICT защищает историю. |
| `courier_pay` | `courier_id` | `courier(courier_id)` | BR-10.2 | Выплата начисляется конкретному курьеру. |
| `product` | `product_category_id` | `product_category(product_category_id)` | BR-5.1 | Блюдо принадлежит конкретной категории справочника. |
| `product` | `restaurant_id` | `restaurant(restaurant_id)` | BR-5.1 | Блюдо принадлежит конкретному ресторану-партнёру. |
| `"order"` | `courier_id` | `courier(courier_id)` | BR-7.5 | Заказ доставляется конкретным курьером. |
| `"order"` | `client_id` | `client(client_id)` | BR-7.2 | Заказ оформляется конкретным клиентом. |
| `"order"` | `address_id` | `address(address_id)` | BR-7.4 | Адрес доставки заказа. |
| `"order"` | `restaurant_id` | `restaurant(restaurant_id)` | BR-7.2 | Заказ оформляется в конкретном ресторане. |
| `"order"` | `(client_id, address_id)` | `client_address(client_id, address_id)` | BR-7.4 | Адрес доставки обязан принадлежать клиенту, оформляющему заказ. |
| `order_structure` | `order_id` | `"order"(order_id)` | BR-7.14 | Позиция принадлежит конкретному заказу. |
| `order_structure` | `product_id` | `product(product_id)` | BR-7.14 | Позиция заказа ссылается на существующее блюдо. |
| `payment` | `order_id` | `"order"(order_id)` | BR-8.1 | Попытка оплаты относится к конкретному заказу. |
| `review` | `client_id` | `client(client_id)` | BR-9.1 | Автор отзыва — клиент сервиса. |
| `review` | `order_id` | `"order"(order_id)` | BR-9.2 | Отзыв всегда привязан к конкретному заказу клиента. |

---

## NOT NULL (только бизнес-обязательные)

| Таблица | Столбец | BR | Обоснование |
|---|---|---|---|
| `client` | `login` | BR-2.1 | Логин необходим для авторизации и идентификации клиента. |
| `client` | `password` | BR-2.1 | Пароль необходим для авторизации клиента. |
| `client` | `phone_number` | BR-2.1 | Телефон необходим для связи и идентификации (BR-2.6). |
| `address` | `street, house_number` | BR-3.1 | Улица и дом обязательны для определения физического адреса. |
| `restaurant` | `restaurant_name` | BR-4.1 | Название ресторана обязательно для отображения в каталоге. |
| `restaurant` | `work_start, work_end` | BR-4.4 | График работы обязателен для контроля времени приёма заказов. |
| `courier` | `fio` | BR-6.1 | ФИО курьера обязательно для трудового учёта. |
| `courier` | `hire_date` | BR-6.1 | Дата найма обязательна для расчёта стажа и работы курьера. |
| `courier` | `coefficient` | BR-6.4, BR-6.5 | Текущий коэффициент курьера обязателен для расчёта зарплаты. |
| `"order"` | `order_timestamp` | BR-7.1 | Момент оформления заказа обязателен для учёта и отчётности. |
| `"order"` | `order_amount` | BR-7.10 | Базовая стоимость блюд заказа обязательна для расчёта комиссии. |
| `order_structure` | `quantity` | BR-7.15 | Количество блюда в позиции заказа обязательно. |
| `payment` | `payment_type, amount` | BR-8.2, BR-8.4 | Тип платежа и сумма транзакции обязательны при попытке оплаты. |
| `review` | `rating, description` | BR-9.3, BR-9.4 | Оценка и текстовый комментарий обязательны для полноценного отзыва. |

---

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
|---|---|---|---|
| `address` | `apartment_office` | BR-3.2, BR-11.3 | Частные дома и отдельно стоящие здания не имеют номера квартиры/офиса. |
| `courier` | `dismissal_date` | BR-6.3, BR-11.3 | Работающий курьер не имеет даты увольнения (заполняется только при увольнении). |
| `restaurant` | `rating` | BR-9.6, BR-9.7 | При отсутствии отзывов на ресторан рейтинг сущности равен `NULL`. |
| `product` | `rating` | BR-9.6, BR-9.7 | При отсутствии отзывов на блюдо рейтинг равен `NULL`. |
| `product` | `photo_url` | BR-5.6, BR-11.3 | Фотография блюда является необязательной ссылкой. |
| `"order"` | `delivery_timestamp` | BR-7.12, BR-11.3 | Время окончания доставки отсутствует до момента получения статуса `'доставлен'`. |
| `"order"` | `description` | `erd.md` | Примечание/комментарий к заказу опционален. |
| `review` | `photo_url` | BR-9.3, BR-11.3 | Фотография к отзыву клиента необязательна. |

---

## DEFAULT и GENERATED

| Таблица | Столбец | Что | Обоснование |
|---|---|---|---|
| Все таблицы | `*_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1: централизованная автоматическая генерация UUID на стороне сервера. |
| `courier` | `coefficient` | `DEFAULT 0.1` | BR-6.5: стартовый коэффициент нового курьера равен 0.1. |
| `courier` | `status` | `DEFAULT 'свободен'` | BR-6.2: базовое состояние нового курьера. |
| `restaurant` | `status` | `DEFAULT 'активен'` | BR-4.3: ресторан регистрируется как активный. |
| `product` | `status` | `DEFAULT 'доступно'` | BR-5.5: новое блюдо по умолчанию доступно для заказа. |
| `"order"` | `commission` | `GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED` | BR-1.4, BR-7.10: фиксированные 10% сервисной комиссии; физически сохраняемый расчёт гарантирует целостность и исключает расхождение данных. |
| `"order"` | `total_amount` | `GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED` | BR-1.5, BR-7.10: итоговая стоимость заказа (стоимость блюд + комиссия); генерация исключает ошибки рассинхронизации. |
| `"order"` | `order_timestamp` | `DEFAULT localtimestamp` | BR-7.1, BR-11.2: время создания в часовом поясе сервера. |
| `"order"` | `status` | `DEFAULT 'создан'` | BR-7.7: начальный статус созданного заказа. |
| `"order"` | `pay_status` | `DEFAULT 'ожидает'` | BR-7.9: начальный статус оплаты заказа. |
| `payment` | `payment_timestamp` | `DEFAULT localtimestamp` | BR-8.2: фиксация момента проведения транзакции. |
| `payment` | `status` | `DEFAULT 'в_обработке'` | BR-8.2: начальный статус попытки оплаты. |
| `review` | `review_timestamp` | `DEFAULT localtimestamp` | BR-9.3: момент публикации отзыва. |

---

## Нормализация (3НФ)

Все таблицы спроектированы в соответствии с требованиями третьей нормальной формы (3НФ):

1. **1НФ:** Все атрибуты атомарны. Имена, адреса, даты и статусы хранятся в отдельных типизированных столбцах. Повторяющиеся группы отсутствуют.
2. **2НФ:** Таблицы находятся в 1НФ, и каждый неключевой атрибут функционально полно зависит от первичного ключа. В таблицах с составными ключами (`client_address`, `order_structure`, `courier_pay`):
   - в `client_address` нет неключевых атрибутов;
   - в `order_structure` атрибут `quantity` зависит от конкретной пары `(order_id, product_id)`;
   - в `courier_pay` атрибуты `amount` и `coefficient_used` зависят от полного составного ключа `(year, month, courier_id)`.
3. **3НФ:** Таблицы находятся во 2НФ, и отсутствуют транзитивные функциональные зависимости неключевых атрибутов от первичного ключа.

**Особые случаи:**
- `order.commission` и `order.total_amount`: функционально определяются стоимостью `order_amount`. Выполнены как `GENERATED ALWAYS ... STORED`, что исключает аномалии модификации данных при сохранении высокой скорости аналитических выборок.
- `product.rating` и `restaurant.rating`: являются денормализованными агрегированными значениями среднего рейтинга по отзывам. Данная денормализация строго регламентирована бизнес-требованиями (BR-9.6, BR-9.7) и поддерживается в актуальном состоянии триггером `rating_change()` (FOOD-105).
- `review.entity_id` + `entity_type`: полиморфная ссылка на сущности. Не нарушает 3НФ, так как описывает атрибуты непосредственно самого отзыва, а не свойства оцениваемой сущности.
