project('sysmonitor',
        ['c', 'vala'],
        version: '0.1.0',
        meson_version: '>= 0.40.0',
)

deps = [
    dependency('gtk+-3.0', version: '>= 3.18.0'),
    dependency('budgie-1.0', version: '>= 2'),
    dependency('libpeas-1.0', version: '>= 1.8.0'),
    dependency('json-glib-1.0'),
    dependency('libgtop-2.0')
]

install_dir = join_paths(get_option('prefix'), 'share', 'budgie-desktop', 'plugins', 'sysmonitor')

add_project_arguments('--vapidir=' + meson.current_source_dir() + '/vapi', language: 'vala')

sources = [
    'src/SysMonitor.vala',
    'src/SysMonitorWindow.vala',
    'src/SysInfo.vala'
]

conf_data = configuration_data()
plugin_filename = 'SysMonitor.plugin'
plugin_file_configured = configure_file(
    input: 'data/SysMonitor.plugin.in',
    output: plugin_filename,
    configuration: conf_data,
    install: false
)

# Додаємо -lm для математичних функцій
add_project_link_arguments('-lm', language: 'c')

shared_library(
    'sysmonitor',
    sources,
    dependencies: deps,
    install: true,
    install_dir: install_dir
)

install_data(
    plugin_file_configured,
    'data/style.css',
    install_dir: install_dir
)

message('Plugin files (.so, .plugin, .css) will be installed to: ' + install_dir)