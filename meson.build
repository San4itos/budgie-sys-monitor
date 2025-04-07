project('sysmonitor',
        ['c', 'vala'],
        version: '0.1.0',
        meson_version: '>= 0.60.0',
        default_options: ['warning_level=2']
)

deps = [
    dependency('gtk+-3.0', version: '>= 3.18.0'),
    dependency('budgie-1.0'),
    dependency('libpeas-1.0', version: '>= 1.8.0'),
    dependency('json-glib-1.0'),
    dependency('libgtop-2.0')
]

# Визначаємо базову директорію залежно від префікса
prefix = get_option('prefix')
if prefix == '/usr'
    plugin_install_dir = join_paths(get_option('libdir'), 'budgie-desktop', 'plugins', 'sysmonitor')
else
    plugin_install_dir = join_paths(prefix, 'share', 'budgie-desktop', 'plugins', 'sysmonitor')
endif

add_project_arguments('--vapidir=' + meson.current_source_dir() + '/vapi', language : 'vala')

# Визначаємо змінні для gettext
gettext_package_name = 'sysmonitor'
localedir = join_paths(get_option('prefix'), get_option('datadir'), 'locale')
add_project_arguments('-DGETTEXT_PACKAGE="' + gettext_package_name + '"', language : 'c')

sources = [
    'src/SysMonitor.vala',
    'src/SysMonitorWindow.vala',
    'src/SysInfo.vala'
]

plugin_filename = 'SysMonitor.plugin'
plugin_file_configured = configure_file(
    input: 'data/SysMonitor.plugin.in',
    output: plugin_filename,
    copy: true,
    install: false
)

# Додаємо -lm для математичних функцій
add_project_link_arguments('-lm', language : 'c')

shared_library(
    'sysmonitor',
    sources,
    dependencies: deps,
    install: true,
    install_dir: plugin_install_dir
)

install_data(
    plugin_file_configured,
    'data/style.css',
    install_dir: plugin_install_dir
)

# Викликаємо subdir для po
subdir('po')

message('Plugin files (.so, .plugin, .css) will be installed to: ' + plugin_install_dir)
message('Locale files (.mo) will be installed to corresponding subdirs in: ' + localedir)

if get_option('prefix') == '/usr'
    message('Installation type: Global (system-wide)')
else
    message('Installation type: Local (user-specific)')
endif