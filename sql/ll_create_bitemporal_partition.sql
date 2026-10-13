/**
 * @file ll_create_bitemporal_partition.sql
 * @ingroup bitemporal_ddl
 * @brief Creates a partition for a partitioned bitemporal table, including the GiST exclusion constraint.
 * @param[in] p_schema text Schema name where table and partition reside.
 * @param[in] p_table text Base partitioned table name.
 * @param[in] p_partition_name text Partition table name to create.
 * @param[in] p_range text Value range for partition (e.g. `FROM ('2023-01-01') TO ('2023-02-01')`).
 * @return boolean True if partition creation and constraint setup succeeded, false otherwise.
 * @sa ll_create_bitemporal_table_partitioned
 */
CREATE OR REPLACE FUNCTION bitemporal_internal.ll_create_bitemporal_partition(
	p_schema text,
	p_table text,
	p_partition_name text,
	p_range text)
    RETURNS boolean
    LANGUAGE 'plpgsql'
 AS $BODY$
DECLARE
v_business_key text;
v_business_key_name text;
v_business_key_gist text;
v_error text;
v_business_key_array text[];
v_sql text;
BEGIN
v_business_key :=
      (select array_to_string(array_agg(a.attname), ',')
       from pg_attribute a
	                where attrelid::regclass= (p_schema||'.'||p_table)::regclass
					        and attnum>1 and attnum in (
	                             select unnest(conkey) as attnum 
	                             from pg_constraint 
	                             where conrelid::regclass= (p_schema||'.'||p_table)::regclass 
		                                 and contype='p') 
		   );
v_business_key_name :=substr(p_partition_name||'_'||translate(
translate(v_business_key, '
',''), ', ','_'),1,47)||'_assert_eff_excl';
v_business_key_gist :=replace(v_business_key, ',',' WITH =,')||' WITH =, asserted WITH &&, effective WITH &&';
--raise notice 'gist %',v_business_key_gist;
--EXECUTE
v_sql :=format($create$
CREATE TABLE %s.%s PARTITION OF
                 %s.%s FOR VALUES %s;
ALTER TABLE %s.%s ADD CONSTRAINT
             %s EXCLUDE
                   USING gist (%s)
                 $create$
                 ,p_schema
                 ,p_partition_name
                 ,p_schema
                 ,p_table
                 ,p_range
				 ,p_schema
				 , p_partition_name
                 ,v_business_key_name
                 ,v_business_key_gist
                 ) ;
  raise notice '%', v_sql;
  execute v_sql;
 RETURN ('true');
 EXCEPTION WHEN OTHERS THEN
GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
raise notice '%', v_error;
RETURN ('false');
END;
$BODY$;
