# SQL schema files tracked for dependency changes
sql_files = files(
    '_load_all.sql',
    'bitemporal_internal_schema.sql',
    'extensions.sql',
    'get_column_type.sql',
    'll_add_fk.sql',
    'll_bitemporal_correction_hist.sql',
    'll_bitemporal_correction_select.sql',
    'll_bitemporal_correction.sql',
    'll_bitemporal_delete_select.sql',
    'll_bitemporal_delete.sql',
    'll_bitemporal_inactivate_select.sql',
    'll_bitemporal_inactivate.sql',
    'll_bitemporal_insert_select.sql',
    'll_bitemporal_insert.sql',
    'll_bitemporal_list_of_fields.sql',
    'll_bitemporal_update_select.sql',
    'll_bitemporal_update.sql',
    'll_check_bitemporal_update_conditions.sql',
    'll_create_bitemporal_table.sql',
    'll_create_bitemporal_view.sql',
    'll_generate_bitemp_for_schema.sql',
    'll_generate_fk_trigger_function.sql',
    'll_generate_fk_validate.sql',
    'll_is_bitemporal_table.sql',
    'll_lookup_validation_function.sql',
    'metadata.sql',
    'relationships.sql',
    'RI_BT_FKey_check_ins_device_id.sql',
    'RI_BT_FKey_check_ins.sql',
    't_RI_bt_insert.sql',
)

# Custom target that tracks sql_files and re-executes psql when any SQL file changes
load_target = custom_target(
    'load_db',
    input: sql_files,
    output: 'load_db.stamp',
    command: [
        psql_cli,
        '-q',
        '-P',
        'pager=off',
        ['-v', 'VERBOSITY=terse'],
        ['-v', 'ON_ERROR_STOP=on'],
        ['-h', pghost],
        ['-p', pgport],
        ['-U', pguser],
        ['-d', pgdatabase],
        ['-f', files('_load_all.sql')],
    ],
    build_by_default: false,
)

# Alias target for manual database loading
run_target(
    'load',
    command: [psql_base, '-f', files('_load_all.sql')],
)
