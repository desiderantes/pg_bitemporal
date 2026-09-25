/**
 * @file ll_bitemporal_update.sql
 * @ingroup bitemporal_dml
 * @brief Performs a bitemporal update operation, closing existing system assertion periods and creating updated effective history.
 * @param[in] p_schema_name text Schema name containing the bitemporal table.
 * @param[in] p_table_name text Target table name.
 * @param[in] p_list_of_fields text Comma-separated column names to update.
 * @param[in] p_list_of_values text Comma-separated literal values for updated columns.
 * @param[in] p_search_fields text Comma-separated list of search columns in WHERE clause.
 * @param[in] p_search_values text Comma-separated literal search values.
 * @param[in] p_effective temporal_relationships.timeperiod Business effective range of the update.
 * @param[in] p_asserted temporal_relationships.timeperiod System assertion range for the update.
 * @return integer Count of updated records.
 * @pre Target table must be a valid bitemporal table.
 * @post Closes assertion period on matching active records and inserts new assertion version with updated effective ranges and attribute values.
 * @throws EXCEPTION 'Asserted interval starts in the past or has a finite end' if `p_asserted` lower bound is before current date or upper bound is finite.
 * @throws EXCEPTION 'Empty list of fields for a table' if table metadata lookup fails.
 * @warning Update vs Correction: `ll_bitemporal_update` creates new temporal versions. To correct errant data without versioning history, use `ll_bitemporal_correction`.
 * @sa ll_bitemporal_update_select, ll_bitemporal_correction
 * @example
 * SELECT * FROM bitemporal_internal.ll_bitemporal_update(
 *     'bitemp_tables',
 *     'devices',
 *     'device_descr',
 *     $$'descr starting from jan 1'$$,
 *     'device_id',
 *     $$1$$,
 *     '[2020-01-01, infinity)',
 *     '[now(), infinity)'
 * );
 */
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_update(p_schema_name text
,p_table_name text
,p_list_of_fields text -- fields to update
,p_list_of_values TEXT  -- values to update with
,p_search_fields TEXT  -- search fields
,p_search_values TEXT  --  search values
,p_effective temporal_relationships.timeperiod  -- effective range of the update
,p_asserted temporal_relationships.timeperiod  -- assertion for the update
) 
RETURNS INTEGER
AS
$BODY$
DECLARE
v_rowcount INTEGER:=0;
v_list_of_fields_to_insert text:=' ';
v_list_of_fields_to_insert_excl_effective text;
v_table_attr text[];
v_serial_key text:=p_table_name||'_key';
v_table text:=p_schema_name||'.'||p_table_name;
v_keys_old int[];
v_keys int[];
v_now timestamptz:=now();-- so that we can reference this time
BEGIN 
 IF lower(p_asserted)<v_now::date --should we allow this precision?...
    OR upper(p_asserted)< 'infinity'
 THEN RAISE EXCEPTION'Asserted interval starts in the past or has a finite end: %', p_asserted
  ; 
  RETURN v_rowcount;
 END IF;  

v_table_attr := bitemporal_internal.ll_bitemporal_list_of_fields(v_table);
IF  array_length(v_table_attr,1)=0
      THEN RAISE EXCEPTION 'Empty list of fields for a table: %', v_table; 
  RETURN v_rowcount;
 END IF;
v_list_of_fields_to_insert_excl_effective:= array_to_string(v_table_attr, ',','');
v_list_of_fields_to_insert:= v_list_of_fields_to_insert_excl_effective||',effective';

--end assertion period for the old record(s)

EXECUTE format($u$ WITH updt AS (UPDATE %s SET asserted =
            temporal_relationships.timeperiod(lower(asserted), lower(%L::temporal_relationships.timeperiod))
                    WHERE ( %s )=( %s ) AND (temporal_relationships.is_overlaps(effective, %L)
                                       OR 
                                       temporal_relationships.is_meets(effective::temporal_relationships.timeperiod, %L)
                                       OR 
                                       temporal_relationships.has_finishes(effective::temporal_relationships.timeperiod, %L))
                                      AND now()<@ asserted  returning %s )
                                      SELECT array_agg(%s) FROM updt
                                      $u$  
          , v_table
          , p_asserted
          , p_search_fields
          , p_search_values
          , p_effective
          , p_effective
          , p_effective
          , v_serial_key
          , v_serial_key) into v_keys_old;

 --insert new assertion rage with old values and effective-ended
EXECUTE format($i$INSERT INTO %s ( %s, effective, asserted )
                SELECT %s ,temporal_relationships.timeperiod(lower(effective), lower(%L::temporal_relationships.timeperiod)) ,%L
                  FROM %s WHERE ( %s )in ( %s )  $i$
          , v_table
          , v_list_of_fields_to_insert_excl_effective
          , v_list_of_fields_to_insert_excl_effective
          , p_effective
          , p_asserted
          , v_table
          , v_serial_key
          ,coalesce(array_to_string(v_keys_old,','), 'NULL')
         
);


---insert new assertion rage with old values and new effective range
 
 EXECUTE 
  format($i$ WITH inst AS (INSERT INTO %s ( %s, effective, asserted )
                  SELECT %s ,%L, %L
                   FROM %s WHERE ( %s )in (%s )  returning %s )
                                    SELECT array_agg(%s) FROM inst
                                      $i$
          , v_table
          , v_list_of_fields_to_insert_excl_effective
          , v_list_of_fields_to_insert_excl_effective
          , p_effective
          , p_asserted
          , v_table
          , v_serial_key
          , coalesce(array_to_string(v_keys_old,','), 'NULL')
          , v_serial_key
          , v_serial_key
) 
into v_keys;

--update new record(s) in new assertion rage with new values                                  
                                  
EXECUTE 
--v_sql :=
format($u$ UPDATE %s SET (%s) = ( SELECT %s) 
                    WHERE ( %s )in ( %s ) $u$  
          , v_table
          , p_list_of_fields
          , p_list_of_values
          , v_serial_key
          ,coalesce(array_to_string(v_keys,','), 'NULL'));
          
GET DIAGNOSTICS v_rowcount:=ROW_COUNT;  

RETURN v_rowcount;
END;    
$BODY$ LANGUAGE plpgsql;
