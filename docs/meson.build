pymod = import('python')
py = pymod.find_installation(
    'python3',
    required: true,
)

summary(
    {
        'Python Installation': py.full_path() + ' (' + py.language_version() + ')',
    },
    section: 'Documentation',
)
fsmod = import('fs')
req_lines = fsmod.read('requirements.txt').strip().split('\n')

pydeps = {}
foreach line : req_lines
    clean_line = line.strip()
    if clean_line != '' and not clean_line.startswith('#')
        foreach op : ['>=', '==', '<=']
            if clean_line.contains(op)
                pydep = clean_line.split(op)[0].strip()
                pyversion = clean_line.split(op)[1].strip()
                # Query installed version via importlib.metadata.version()
                res = run_command(
                    py,
                    '-c',
                    'import importlib.metadata as m; print(m.version("@0@"))'.format(
                        pydep,
                    ),
                    check: false,
                )

                if res.returncode() != 0
                    error(
                        'Required Python package "@0@" is not installed.'.format(
                            pydep,
                        ),
                    )
                endif

                installed_ver = res.stdout().strip()

                # Compare version using Meson native version_compare
                if not installed_ver.version_compare(op + pyversion)
                    error(
                        'Package "@0@" version @1@ does not satisfy requirement @2@@3@'.format(
                            pydep,
                            installed_ver,
                            op,
                            pyversion,
                        ),
                    )
                endif

                summary(
                    {
                        'Python Dependency: ' + pydep: '@0@ (satisfies @1@@2@)'.format(
                            installed_ver,
                            op,
                            pyversion,
                        ),
                    },
                    section: 'Documentation',
                )
            endif
        endforeach
    endif
endforeach

foreach pydep, pyversion : pydeps

endforeach


doxygen = find_program('doxygen', required: true)

sphinx = find_program('sphinx-build', required: false)

summary(
    {
        'Doxygen': doxygen.full_path() + ' (' + doxygen.version() + ')',
        'Sphinx': sphinx.full_path() + ' (' + sphinx.version() + ')',
    },
    section: 'Documentation',
)

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

sphinx_conf = configuration_data()
sphinx_conf.set('PROJECT_NAME', meson.project_name())
sphinx_conf.set('PROJECT_VERSION', meson.project_version())
sphinx_conf.set('DOXYGEN_XML_DIR', meson.current_build_dir() / 'xml')

conf_py = configure_file(
    input: 'conf.py.in',
    output: 'conf.py',
    configuration: sphinx_conf,
)

doxygen_target = custom_target(
    'doxygen_out',
    input: [sql_files, doxyfile],
    output: ['xml', 'html'],
    command: [doxygen, doxyfile],
    build_by_default: true,
)

docs = custom_target(
    'sphinx_out',
    input: [doxygen_target, conf_py],
    output: 'sphinx',
    command: [
        sphinx,
        '-b',
        'html',
        '-c',
        meson.current_build_dir(),
        meson.project_source_root() / 'docs',
        meson.current_build_dir() / 'sphinx',
    ],
    build_by_default: false,
)
