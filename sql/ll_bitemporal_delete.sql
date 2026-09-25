/**
 * @file ll_bitemporal_delete.sql
 * @ingroup bitemporal_dml
 * @brief Deletes (asserts out) matching records from a bitemporal table by closing their assertion interval.
 * @param[in] p_table text Qualified bitemporal table name (`<schema>.<table_name>`).
 * @param[in] p_search_fields text Comma-separated search column names for WHERE clause.
 * @param[in] p_search_values text Comma-separated search values.
 * @param[in] p_asserted temporal_relationships.timeperiod Assertion range closing record validity in system time.
 * @return integer Count of deleted (asserted-out) records.
 * @pre Target table must be bitemporal and contain active records matching `p_search_fields`.
 * @post Sets `upper(asserted)` boundary to lower bound of `p_asserted` for matching active records.
 * @sa ll_bitemporal_inactivate, ll_bitemporal_update
 */
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_delete(p_table text
, p_search_fields TEXT  -- search fields
, p_search_values TEXT  --  search values
, p_asserted temporal_relationships.timeperiod -- will be asserted
)
RETURNS INTEGER
AS
$BODY$
DECLARE
v_rowcount INTEGER:=0;
BEGIN 
--end assertion period for the current records record(s)

EXECUTE format($u$ UPDATE %s SET asserted =
temporal_relationships.timeperiod(lower(asserted), lower(%L::temporal_relationships.timeperiod))
                    WHERE ( %s )=( %s )AND lower(%L::temporal_relationships.timeperiod)<@ asserted  $u$
          , p_table
          , p_asserted
          , p_search_fields   
          , p_search_values
          , p_asserted
          );
          

GET DIAGNOSTICS v_rowcount:=ROW_COUNT; 
RETURN v_rowcount;
END;
$BODY$ LANGUAGE plpgsql;
