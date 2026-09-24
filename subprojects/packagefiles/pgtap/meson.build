project('pgtap', version: '1.3.4')

ver_parts = meson.project_version().split('.')
num_version = ver_parts[0] + '.' + ver_parts[1]

pgtap_sql = custom_target(
    'pgtap_sql',
    input: 'sql/pgtap.sql.in',
    output: 'pgtap.sql',
    command: [
        'sed',
        '-e', 's/__VERSION__/' + num_version + '/g',
        '-e', 's/__OS__/' + build_machine.system() + '/g',
        '@INPUT@',
    ],
    capture: true,
)
