CREATE DATABASE IF NOT EXISTS dv;

-- Хаб: География клиента
-- Бизнес-ключ: комбинация City + State + Postal Code + Country + Region
CREATE TABLE IF NOT EXISTS dv.hub_customer_location (
    /* 
    Для MD5-хеша идеально подходит FixedString(32), так как он всегда занимает ровно 32 байта (hex-представление), 
    что позволяет сэкономить память по сравнению со String.
    */
    hub_customer_location_hk FixedString(32),
    -- Описательные атрибуты бизнес-ключа. String выбран, так как длина заранее не известна.
    city String,
    state String,
    postal_code String,
    country String,
    region String,
    -- Технические поля Data Vault
    load_ts DateTime DEFAULT now(),
    record_source String DEFAULT 'superstore_csv'
/*
В ClickHouse PRIMARY KEY не обеспечивает уникальность. 
Вместо этого используется ReplacingMergeTree: при слиянии фоновых процессов дубликаты 
с одинаковым hub_customer_location_hk будут приведены к единому уникальному значению комбинации. 
*/
) ENGINE = ReplacingMergeTree(load_ts)
-- В ORDER BY указывается хеш для ускорения поиска и джойнов по ключу
ORDER BY (hub_customer_location_hk);

-- Хаб: Товар
-- Бизнес-ключ: комбинация Category + Sub-Category
CREATE TABLE IF NOT EXISTS dv.hub_product (
    hub_product_hk  FixedString(32),
    category String,
    sub_category String,
    load_ts DateTime DEFAULT now(),
    record_source String DEFAULT 'superstore_csv'
) ENGINE = ReplacingMergeTree(load_ts)
ORDER BY (hub_product_hk);

-- Хаб: Способ доставки
-- Бизнес-ключ: Ship Mode
CREATE TABLE IF NOT EXISTS dv.hub_ship_mode (
    hub_ship_mode_hk FixedString(32),
    ship_mode String,
    load_ts DateTime DEFAULT now(),
    record_source String DEFAULT 'superstore_csv'
) ENGINE = ReplacingMergeTree(load_ts)
ORDER BY (hub_ship_mode_hk);

-- Хаб: Сегмент клиента
-- Бизнес-ключ: Segment
CREATE TABLE IF NOT EXISTS dv.hub_segment (
    hub_segment_hk FixedString(32),
    segment String,
    load_ts DateTime DEFAULT now(),
    record_source String DEFAULT 'superstore_csv'
) ENGINE = ReplacingMergeTree(load_ts)
ORDER BY (hub_segment_hk);

-- Линк: Продажа
-- Связывает 4 хаба
-- Поскольку в датасете нет order_id, линк представляет собой уникальную комбинацию этих 4-х бизнес-сущностей
CREATE TABLE IF NOT EXISTS dv.link_sale (
    link_sale_hk FixedString(32),
    /*
    Ссылки на хабы. В ClickHouse нет FOREIGN KEY, целостность обеспечивается 
    на уровне Python-скрипта при загрузке, хеши хранятся для джойнов.
    */
    hub_customer_location_hk FixedString(32),
    hub_product_hk FixedString(32),
    hub_ship_mode_hk FixedString(32),
    hub_segment_hk FixedString(32),
    load_ts DateTime DEFAULT now(),
    record_source String DEFAULT 'superstore_csv'
/*
Используется обычный MergeTree, так как линк - неизменяемая связь.
Вставка уникальных связей контролируется на стороне ETL (скрипта).
*/
) ENGINE = MergeTree
ORDER BY (link_sale_hk);

-- Сателлит: Меры продажи
-- Хранит контекст и метрики для конкретной связи (link_sale_hk)
CREATE TABLE IF NOT EXISTS dv.sat_sale_measures (
    link_sale_hk FixedString(32),
    load_ts DateTime DEFAULT now(),
    -- Нужен для отслеживания изменений, считается от всех мер (Sales|Quantity|Discount|Profit)
    hash_diff FixedString(32),
    sales Float64,
    quantity Int32,
    discount Float64,
    profit Float64,
    record_source String DEFAULT 'superstore_csv'
/*
Используется ReplacingMergeTree по load_ts. При обновлении, 
ClickHouse оставит запись с самым свежим load_ts, а старую удалит при MERGE.
*/
) ENGINE = ReplacingMergeTree(load_ts)
ORDER BY (link_sale_hk, load_ts);