/**
 * @file ll_drop_bitemporal_view.sql
 * @ingroup bitemporal_schema
 * @brief Drops an updatable bitemporal view, its INSTEAD OF trigger, trigger function, and as_of function.
 * @param[in] p_schema text Schema name containing the bitemporal view.
 * @param[in] p_view text Name of the view to drop.
 * @param[in] p_cascade boolean Optional flag to cascade drop to dependent database objects (defaults to false).
 * @retval true View and associated helper functions dropped successfully.
 * @retval false Dropping failed (error diagnostic logged via RAISE NOTICE).
 * @post Drops view `<p_schema>.<p_view>`, function `<p_schema>.<p_view>_bitemporal_dml()`, and function `<p_schema>.<p_view>_as_of(timestamptz, timestamptz)`.
 * @sa ll_create_bitemporal_view
 * @par Example
 * @code
 * SELECT bitemporal_internal.ll_drop_bitemporal_view('myschema', 'orders');
 * @endcode
 */
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_drop_bitemporal_view(
    p_schema text,
    p_view text,
    p_cascade boolean DEFAULT false
)
RETURNS boolean AS
$BODY$
DECLARE
    v_error text;
    v_cascade_str text := '';
BEGIN
    IF p_schema IS NULL OR trim(p_schema) = '' THEN
        RAISE EXCEPTION 'Schema name cannot be null or empty';
    END IF;
    IF p_view IS NULL OR trim(p_view) = '' THEN
        RAISE EXCEPTION 'View name cannot be null or empty';
    END IF;

    IF p_cascade THEN
        v_cascade_str := 'CASCADE';
    END IF;

    -- 1. Drop view (automatically removes any INSTEAD OF triggers attached to it)
    EXECUTE format('DROP VIEW IF EXISTS %I.%I %s', p_schema, p_view, v_cascade_str);

    -- 2. Drop trigger function
    EXECUTE format('DROP FUNCTION IF EXISTS %I.%I() %s', p_schema, p_view || '_bitemporal_dml', v_cascade_str);

    -- 3. Drop parameterized as_of function
    EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(timestamptz, timestamptz) %s', p_schema, p_view || '_as_of', v_cascade_str);

    RETURN true;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    RAISE NOTICE '%', v_error;
    RETURN false;
END;
$BODY$ LANGUAGE plpgsql;
