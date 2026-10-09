# Test definitions for pgTAP SQL tests

pgtap_sub = subproject('pgtap')
pgtap_sql = pgtap_sub.get_variable('pgtap_sql')

run_target(
    'load_pgtap',
    command: [psql_base, ['-f', pgtap_sql]],
)

test_files = [
    '00_pgtap_working.sql',
    '05_ll_functions.sql',
    '06_privs.sql',
    '10_relationships.sql',
    '15_metadata.sql',
    '16_metadata.sql',
    '20_ll_update.sql',
    '25_ll_view.sql',
]

foreach t : test_files
    test(
        t,
        psql_cli,
        args: [
            '-q',
            '-X',
            '-A',
            '-t',
            ['-v', 'VERBOSITY=terse'],
            ['-v', 'ON_ERROR_STOP=on'],
            ['-h', pghost],
            ['-p', pgport],
            ['-U', pguser],
            ['-d', pgdatabase],
            ['-f', files(t)],
        ],
        protocol: 'tap',
        env: env,
    )
endforeach
