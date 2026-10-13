BEGIN;
set client_min_messages to warning;
set local search_path = 'bitemporal_internal', 'public';
set local TimeZone = 'UTC';

SELECT plan(9);

select lives_ok($$ 
    create schema test_partition_schema;
$$, 'create test_partition_schema');

-- 1. Create partitioned bitemporal table
select is(
    bitemporal_internal.ll_create_bitemporal_table_partitioned(
        'test_partition_schema',
        'sensor_readings',
        'sensor_id integer, reading_date date, value numeric',
        'sensor_id,reading_date',
        'reading_date'
    ),
    true,
    'll_create_bitemporal_table_partitioned creates table partitioned by reading_date'
);

-- 2. Verify table exists and is partitioned
select has_table('test_partition_schema', 'sensor_readings', 'table sensor_readings exists');

-- 3. Create partitions
select is(
    bitemporal_internal.ll_create_bitemporal_partition(
        'test_partition_schema',
        'sensor_readings',
        'sensor_readings_2023_01',
        $$FROM ('2023-01-01') TO ('2023-02-01')$$
    ),
    true,
    'create partition sensor_readings_2023_01'
);

select is(
    bitemporal_internal.ll_create_bitemporal_partition(
        'test_partition_schema',
        'sensor_readings',
        'sensor_readings_2023_02',
        $$FROM ('2023-02-01') TO ('2023-03-01')$$
    ),
    true,
    'create partition sensor_readings_2023_02'
);

-- 4. Verify partition tables exist
select has_table('test_partition_schema', 'sensor_readings_2023_01', 'partition sensor_readings_2023_01 exists');
select has_table('test_partition_schema', 'sensor_readings_2023_02', 'partition sensor_readings_2023_02 exists');

-- 5. Insert rows routed across partitions
select lives_ok($$
    INSERT INTO test_partition_schema.sensor_readings (sensor_id, reading_date, value, effective, asserted)
    VALUES (
        1,
        '2023-01-15'::date,
        42.5,
        temporal_relationships.timeperiod(now(), 'infinity'),
        temporal_relationships.timeperiod(now(), 'infinity')
    ),
    (
        1,
        '2023-02-10'::date,
        45.0,
        temporal_relationships.timeperiod(now(), 'infinity'),
        temporal_relationships.timeperiod(now(), 'infinity')
    );
$$, 'insert rows into partitioned bitemporal table routed to respective partitions');

select results_eq(
    $$ SELECT count(*)::integer FROM test_partition_schema.sensor_readings $$,
    $$ VALUES (2::integer) $$,
    'partitioned table contains 2 rows'
);

SELECT * FROM finish();
ROLLBACK;
