/**
 * @file ll_bitemporal_insert.sql
 * @ingroup bitemporal_dml
 * @brief Inserts a new tuple into a bitemporal table with explicit effective and asserted time periods.
 * @param[in] p_table text Fully qualified bitemporal table name (`<schema>.<table_name>`).
 * @param[in] p_list_of_fields text Comma-separated column names to insert.
 * @param[in] p_list_of_values text Comma-separated literal values for the columns.
 * @param[in] p_effective temporal_relationships.timeperiod Business effective interval for the record.
 * @param[in] p_asserted temporal_relationships.timeperiod System assertion interval for the record.
 * @return integer Number of inserted records (1 if successful).
 * @pre Target table must exist and be bitemporal.
 * @post Inserts a new record into `p_table` with `effective` and `asserted` ranges set.
 * @sa ll_bitemporal_insert_select, ll_bitemporal_update
 * @example
 * SELECT * FROM bitemporal_internal.ll_bitemporal_insert(
 *     'bitemp_tables.devices',
 *     'device_id, device_descr',
 *     $$1, 'description_1'$$,
 *     '[now(), infinity)'::tstzrange,
 *     '[now(), infinity)'::tstzrange
 * );
 */
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_insert(p_table text
,p_list_of_fields text
,p_list_of_values TEXT
,p_effective temporal_relationships.timeperiod 
,p_asserted temporal_relationships.timeperiod ) 
RETURNS INTEGER
AS
 $BODY$
DECLARE
v_rowcount INTEGER;
BEGIN
 EXECUTE format ($i$INSERT INTO %s (%s, effective, asserted )  
                 VALUES (%s,%L,%L) RETURNING * $i$
                ,p_table
                ,p_list_of_fields
                ,p_list_of_values
                ,p_effective
                ,p_asserted) ;
     GET DIAGNOSTICS v_rowcount:=ROW_COUNT; 
     RETURN v_rowcount;         
     END;    
$BODY$ LANGUAGE plpgsql;
