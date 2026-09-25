# Detect Doxygen documentation generator
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

docs = custom_target(
    'docs',
    input: [sql_files, doxyfile],
    output: 'html',
    command: [doxygen, doxyfile],
    build_by_default: true,
)
