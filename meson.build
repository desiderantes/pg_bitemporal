project(
    'pg_bitemporal',
    version: '0.1.0',
    meson_version: '>=1.1.0',
)

# Programs
psql_cli = find_program('psql', required: true)

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
# Subdirectories
subdir('sql')
if get_option('generate_docs').enabled()
    subdir('docs')
endif

if get_option('tests')
    subdir('tests')
endif
