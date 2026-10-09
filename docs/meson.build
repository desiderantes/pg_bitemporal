pymod = import('python')
py = pymod.find_installation(
    'python3',
    modules: ['sqlparse', 'breathe', 'myst_parser'],
    required: true,
)

doxygen = find_program('doxygen', required: true)

doxygen_conf = configuration_data()
doxygen_conf.set('PROJECT_NAME', meson.project_name())
doxygen_conf.set('PROJECT_VERSION', meson.project_version())
doxygen_conf.set('INPUT_DIR', meson.project_source_root() / 'sql')
doxygen_conf.set('OUTPUT_DIR', meson.current_build_dir())
doxygen_conf.set(
    'SQL_FILTER',
    meson.project_source_root() / 'tools' / 'doxygen_sql_filter.py',
)

doxyfile = configure_file(
    input: 'Doxyfile.in',
    output: 'Doxyfile',
    configuration: doxygen_conf,
)

doxygen_target = custom_target(
    'doxygen_out',
    input: [sql_files, doxyfile],
    output: ['xml', 'html'],
    command: [doxygen, doxyfile],
    build_by_default: true,
)
