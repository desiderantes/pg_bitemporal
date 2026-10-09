BEGIN;
set client_min_messages to warning;
set local search_path = 'bitemporal_internal', 'public';
set local TimeZone = 'UTC';

SELECT plan(20);

select lives_ok($$ 
    create schema test_view_schema;
$$, 'create test_view_schema');

-- 1. Create single-key bitemporal table
select lives_ok($$
    select * from bitemporal_internal.ll_create_bitemporal_table(
        'test_view_schema',
        'orders_bt',
        'order_id integer, cust_id integer, status text',
        'order_id'
    );
$$, 'create orders_bt');

-- 2. Test error cases
select is(
    bitemporal_internal.ll_create_bitemporal_view('test_view_schema', 'orders_bt', ''),
    false,
    'fails on empty view name'
);

select is(
    bitemporal_internal.ll_create_bitemporal_view('test_view_schema', 'non_existent_bt', 'orders'),
    false,
    'fails on non-existent table'
);

-- 3. Create view
select is(
    bitemporal_internal.ll_create_bitemporal_view('test_view_schema', 'orders_bt', 'orders'),
    true,
    'll_create_bitemporal_view succeeds'
);

-- Verify view exists in information_schema
select has_view('test_view_schema', 'orders', 'view test_view_schema.orders exists');

-- 4. Test INSERT on view
select lives_ok($$
    INSERT INTO test_view_schema.orders (order_id, cust_id, status)
    VALUES (1, 101, 'PENDING');
$$, 'insert through view');

select results_eq(
    $$ SELECT order_id, cust_id, status FROM test_view_schema.orders WHERE order_id = 1 $$,
    $$ VALUES (1, 101, 'PENDING'::text) $$,
    'read newly inserted row from view'
);

select is(
    (SELECT count(*)::integer FROM test_view_schema.orders_bt WHERE order_id = 1 AND now() <@ effective AND now() <@ asserted),
    1,
    'underlying orders_bt has 1 active bitemporal row'
);

-- 5. Test UPDATE on view
-- In bitemporal modeling, temporal updates establish a new effective period (starting at now())
-- while preserving the preceding historical interval for records established prior to now().
select lives_ok($$
    INSERT INTO test_view_schema.orders_bt (order_id, cust_id, status, effective, asserted)
    VALUES (2, 202, 'PENDING', '[2020-01-01, infinity)', '[2020-01-01, infinity)');
$$, 'seed order 2 with established effective start');

select lives_ok($$
    UPDATE test_view_schema.orders
    SET status = 'SHIPPED'
    WHERE order_id = 2;
$$, 'update through view');

select results_eq(
    $$ SELECT status FROM test_view_schema.orders WHERE order_id = 2 $$,
    $$ VALUES ('SHIPPED'::text) $$,
    'view reflects updated status'
);

select is(
    (SELECT count(*)::integer FROM test_view_schema.orders_bt WHERE order_id = 2 AND now() <@ asserted),
    2,
    'underlying orders_bt preserved historical version (2 active asserted rows)'
);

-- 6. Test DELETE on view
select lives_ok($$
    DELETE FROM test_view_schema.orders
    WHERE order_id = 2;
$$, 'delete through view');

select is(
    (SELECT count(*)::integer FROM test_view_schema.orders WHERE order_id = 2),
    0,
    'row is deleted from view'
);

select is(
    (SELECT count(*)::integer FROM test_view_schema.orders_bt WHERE order_id = 2 AND now() <@ asserted),
    0,
    'underlying orders_bt has 0 active asserted rows after delete'
);

select lives_ok($$
    DELETE FROM test_view_schema.orders
    WHERE order_id = 1;
$$, 'delete inserted row through view');

select is(
    (SELECT count(*)::integer FROM test_view_schema.orders WHERE order_id = 1),
    0,
    'order 1 is deleted from view'
);

-- 7. Test composite business key
select lives_ok($$
    select * from bitemporal_internal.ll_create_bitemporal_table(
        'test_view_schema',
        'order_items_bt',
        'order_id integer, item_id integer, qty integer',
        'order_id, item_id'
    );
    select * from bitemporal_internal.ll_create_bitemporal_view(
        'test_view_schema',
        'order_items_bt',
        'order_items'
    );
    INSERT INTO test_view_schema.order_items_bt (order_id, item_id, qty, effective, asserted)
    VALUES (1, 10, 5, '[2020-01-01, infinity)', '[2020-01-01, infinity)');
    UPDATE test_view_schema.order_items SET qty = 12 WHERE order_id = 1 AND item_id = 10;
$$, 'composite key table view setup and update');

select results_eq(
    $$ SELECT qty FROM test_view_schema.order_items WHERE order_id = 1 AND item_id = 10 $$,
    $$ VALUES (12) $$,
    'composite key view reflects updated qty'
);

SELECT * FROM finish();
ROLLBACK;
