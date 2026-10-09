/**
 * @file ll_create_bitemporal_view.sql
 * @ingroup bitemporal_schema
 * @brief Creates an updatable current-state view for a bitemporal table with INSTEAD OF triggers.
 * @param[in] p_schema text Schema name containing the bitemporal table.
 * @param[in] p_table text Bitemporal table name.
 * @param[in] p_view text Mandatory target view name to create.
 * @retval true View and INSTEAD OF triggers created successfully.
 * @retval false View creation failed (error diagnostic logged via RAISE NOTICE).
 * @pre Target table must exist and be a valid bitemporal table.
 * @post Creates view `<p_schema>.<p_view>` filtered by `now() <@ effective AND now() <@ asserted`, and binds an INSTEAD OF trigger supporting INSERT, UPDATE, and DELETE.
 * @sa ll_create_bitemporal_table, ll_is_bitemporal_table
 * @par Example
 * @code
 * SELECT bitemporal_internal.ll_create_bitemporal_view('myschema', 'orders_bt', 'orders');
 * @endcode
 */
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_create_bitemporal_view(
    p_schema text,
    p_table text,
    p_view text
)
RETURNS boolean AS
$BODY$
DECLARE
    v_error text;
    v_is_bitemporal boolean;
    v_business_key_array text[];
    v_business_key_types text[];
    v_all_view_cols text[];
    v_all_view_types text[];
    v_non_key_cols text[];
    v_non_key_types text[];
    v_view_cols_str text;
    v_key_cols_str text;
    v_non_key_cols_str text;
    v_insert_cols_str text;
    v_insert_vals_str text;
    v_update_key_cond text;
    v_update_non_key_vals_expr text;
    v_update_all_vals_expr text;
    v_search_vals_expr text;
    v_trig_func_name text;
    v_trig_name text;
    v_trig_sql text;
BEGIN
    -- Validate arguments
    IF p_schema IS NULL OR trim(p_schema) = '' THEN
        RAISE EXCEPTION 'Schema name cannot be null or empty';
    END IF;
    IF p_table IS NULL OR trim(p_table) = '' THEN
        RAISE EXCEPTION 'Table name cannot be null or empty';
    END IF;
    IF p_view IS NULL OR trim(p_view) = '' THEN
        RAISE EXCEPTION 'View name cannot be null or empty';
    END IF;

    -- Validate target table is bitemporal
    v_is_bitemporal := bitemporal_internal.ll_is_bitemporal_table(p_schema || '.' || p_table);
    IF NOT v_is_bitemporal THEN
        RAISE EXCEPTION 'Table %.% is not a valid bitemporal table', p_schema, p_table;
    END IF;

    -- Discover business key columns and types from GiST exclusion constraint
    SELECT 
        array_agg(a.attname ORDER BY u.ord),
        array_agg(format_type(a.atttypid, a.atttypmod) ORDER BY u.ord)
    INTO v_business_key_array, v_business_key_types
    FROM pg_constraint c
    JOIN pg_class cc ON cc.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = cc.relnamespace
    JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS u(attnum, ord) ON true
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = u.attnum
    WHERE n.nspname = p_schema
      AND cc.relname = p_table
      AND c.contype = 'x'
      AND a.attname NOT IN ('effective', 'asserted');

    IF v_business_key_array IS NULL OR array_length(v_business_key_array, 1) = 0 THEN
        RAISE EXCEPTION 'Could not discover business key from exclusion constraint on %.%', p_schema, p_table;
    END IF;

    -- Discover user/business columns and types (exclude surrogate PK, effective, asserted, row_created_at)
    SELECT 
        array_agg(a.attname ORDER BY a.attnum),
        array_agg(format_type(a.atttypid, a.atttypmod) ORDER BY a.attnum)
    INTO v_all_view_cols, v_all_view_types
    FROM pg_attribute a
    JOIN pg_class cc ON cc.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = cc.relnamespace
    LEFT JOIN pg_constraint pk ON pk.conrelid = cc.oid AND pk.contype = 'p' AND a.attnum = ANY(pk.conkey)
    WHERE n.nspname = p_schema
      AND cc.relname = p_table
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND pk.conkey IS NULL
      AND a.attname NOT IN ('effective', 'asserted', 'row_created_at', p_table || '_key');

    IF v_all_view_cols IS NULL OR array_length(v_all_view_cols, 1) = 0 THEN
        RAISE EXCEPTION 'No business attributes found for table %.%', p_schema, p_table;
    END IF;

    -- Non-key columns and types
    SELECT 
        coalesce(array_agg(c.col), ARRAY[]::text[]),
        coalesce(array_agg(c.typ), ARRAY[]::text[])
    INTO v_non_key_cols, v_non_key_types
    FROM (
        SELECT unnest(v_all_view_cols) AS col, unnest(v_all_view_types) AS typ
    ) c
    WHERE c.col != ALL(v_business_key_array);

    -- Format strings for DDL and triggers
    v_view_cols_str := array_to_string(v_all_view_cols, ', ');
    v_key_cols_str := array_to_string(v_business_key_array, ', ');
    v_non_key_cols_str := array_to_string(v_non_key_cols, ', ');

    -- 1. Create or replace the view
    EXECUTE format(
        'CREATE OR REPLACE VIEW %I.%I AS SELECT %s FROM %I.%I WHERE now() <@ effective AND now() <@ asserted',
        p_schema, p_view, v_view_cols_str, p_schema, p_table
    );

    -- 2. Build trigger function components
    -- INSERT columns and values
    v_insert_cols_str := v_view_cols_str || ', effective, asserted';
    SELECT array_to_string(array_agg('NEW.' || quote_ident(col)), ', ')
    INTO v_insert_vals_str
    FROM unnest(v_all_view_cols) AS col;
    v_insert_vals_str := v_insert_vals_str || ', v_eff, v_asserted';

    -- Search values expression for OLD business key with explicit type casts
    SELECT array_to_string(
        array_agg(
            'quote_nullable(OLD.' || quote_ident(c.col) || '::text) || ' || quote_literal('::' || c.typ)
        ),
        ' || '', '' || '
    )
    INTO v_search_vals_expr
    FROM (
        SELECT unnest(v_business_key_array) AS col, unnest(v_business_key_types) AS typ
    ) c;

    -- Update key condition: (NEW.k1, NEW.k2) IS NOT DISTINCT FROM (OLD.k1, OLD.k2)
    SELECT '(' || array_to_string(array_agg('NEW.' || quote_ident(col)), ', ') || ') IS NOT DISTINCT FROM (' ||
                  array_to_string(array_agg('OLD.' || quote_ident(col)), ', ') || ')'
    INTO v_update_key_cond
    FROM unnest(v_business_key_array) AS col;

    -- Update non-key values expression with explicit type casts
    IF array_length(v_non_key_cols, 1) > 0 THEN
        SELECT array_to_string(
            array_agg(
                'quote_nullable(NEW.' || quote_ident(c.col) || '::text) || ' || quote_literal('::' || c.typ)
            ),
            ' || '', '' || '
        )
        INTO v_update_non_key_vals_expr
        FROM (
            SELECT unnest(v_non_key_cols) AS col, unnest(v_non_key_types) AS typ
        ) c;
    ELSE
        v_update_non_key_vals_expr := '''''';
    END IF;

    -- Update all values expression with explicit type casts (used when business key is modified)
    SELECT array_to_string(
        array_agg(
            'quote_nullable(NEW.' || quote_ident(c.col) || '::text) || ' || quote_literal('::' || c.typ)
        ),
        ' || '', '' || '
    )
    INTO v_update_all_vals_expr
    FROM (
        SELECT unnest(v_all_view_cols) AS col, unnest(v_all_view_types) AS typ
    ) c;

    -- 3. Construct and execute the trigger function
    v_trig_func_name := p_view || '_bitemporal_dml';
    v_trig_name := p_view || '_bitemporal_dml_trig';

    v_trig_sql := format($func$
CREATE OR REPLACE FUNCTION %I.%I()
RETURNS TRIGGER AS $trig$
DECLARE
    v_eff temporal_relationships.timeperiod := temporal_relationships.timeperiod(now(), 'infinity');
    v_asserted temporal_relationships.timeperiod := temporal_relationships.timeperiod(now(), 'infinity');
    v_search_values text;
    v_update_values text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO %I.%I (%s)
        VALUES (%s);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        v_search_values := %s;
$func$,
        p_schema, v_trig_func_name,
        p_schema, p_table, v_insert_cols_str,
        v_insert_vals_str,
        v_search_vals_expr
    );

    IF array_length(v_non_key_cols, 1) > 0 THEN
        v_trig_sql := v_trig_sql || format($func$
        IF %s THEN
            v_update_values := %s;
            PERFORM bitemporal_internal.ll_bitemporal_update(
                %L,
                %L,
                %L,
                v_update_values,
                %L,
                v_search_values,
                v_eff,
                v_asserted
            );
        ELSE
            v_update_values := %s;
            PERFORM bitemporal_internal.ll_bitemporal_update(
                %L,
                %L,
                %L,
                v_update_values,
                %L,
                v_search_values,
                v_eff,
                v_asserted
            );
        END IF;
        RETURN NEW;
$func$,
            v_update_key_cond,
            v_update_non_key_vals_expr,
            p_schema, p_table, v_non_key_cols_str, v_key_cols_str,
            v_update_all_vals_expr,
            p_schema, p_table, v_view_cols_str, v_key_cols_str
        );
    ELSE
        v_trig_sql := v_trig_sql || format($func$
        IF NOT (%s) THEN
            v_update_values := %s;
            PERFORM bitemporal_internal.ll_bitemporal_update(
                %L,
                %L,
                %L,
                v_update_values,
                %L,
                v_search_values,
                v_eff,
                v_asserted
            );
        END IF;
        RETURN NEW;
$func$,
            v_update_key_cond,
            v_update_all_vals_expr,
            p_schema, p_table, v_view_cols_str, v_key_cols_str
        );
    END IF;

    v_trig_sql := v_trig_sql || format($func$
    ELSIF TG_OP = 'DELETE' THEN
        v_search_values := %s;
        PERFORM bitemporal_internal.ll_bitemporal_delete(
            %L,
            %L,
            v_search_values,
            v_asserted
        );
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$trig$ LANGUAGE plpgsql;
$func$,
        v_search_vals_expr,
        p_schema || '.' || p_table,
        v_key_cols_str
    );

    EXECUTE v_trig_sql;

    -- 4. Create INSTEAD OF trigger on the view
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I', v_trig_name, p_schema, p_view);
    EXECUTE format(
        'CREATE TRIGGER %I INSTEAD OF INSERT OR UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION %I.%I()',
        v_trig_name, p_schema, p_view, p_schema, v_trig_func_name
    );

    RETURN true;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    RAISE NOTICE '%', v_error;
    RETURN false;
END;
$BODY$ LANGUAGE plpgsql;
