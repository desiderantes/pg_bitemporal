project(
    'pg_bitemporal',
    version: '0.1.0',
    meson_version: '>=1.1.0',
)

# Programs
psql_cli = find_program('psql', required: true)

# Detect if cdosborn/lit (literate programming tool) is installed
litc = find_program('lit', required: false)
lit_valid = false
if litc.found()
    res = run_command(litc, '--help', check: false)
    if res.stdout().contains('--code-dir') or res.stderr().contains('--code-dir')
        lit_valid = true
    else
        message(
            'Found lit executable at ' + litc.full_path() + ' but it does not appear to be cdosborn/lit. Skipping .lit targets.',
        )
    endif
endif

if lit_valid
    relationships_sql = custom_target(
        'relationships_sql',
        input: 'relationships.sql.lit',
        output: 'relationships.sql',
        command: [litc, '-c', '--code-dir=@OUTDIR@', '@INPUT@'],
        build_by_default: true,
    )

    relationships_doc = custom_target(
        'relationships_doc',
        input: 'relationships.sql.lit',
        output: 'relationships.sql.md',
        command: [litc, '-m', '--docs-dir=@OUTDIR@', '@INPUT@'],
        build_by_default: true,
    )
endif

# Database environment setup from meson options
pgdatabase = get_option('pgdatabase')
pghost = get_option('pghost')
pgport = get_option('pgport')
pguser = get_option('pguser')
pgversion = get_option('pgversion')

env = environment()
env.set('PGDATABASE', pgdatabase)
env.set('PGHOST', pghost)
env.set('PGPORT', pgport)
env.set('PGUSER', pguser)

# Common psql CLI arguments
psql_base = [
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
]

subdir('sql')

# Subdirectories
subdir('tests')
