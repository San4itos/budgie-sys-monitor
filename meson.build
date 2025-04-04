project('budgie-sysmonitor',
        ['c', 'vala'],
        version: '0.1.0',
        meson_version: '>= 0.50.0',
)

gnome = import('gnome')

deps = [
    dependency('gtk+-3.0', version: '>= 3.18.0'),
    dependency('budgie-1.0'),
    dependency('libpeas-1.0', version: '>= 1.8.0'),
    dependency('json-glib-1.0'),
    dependency('libgtop-2.0')
]

# Визначаємо правильний шлях для плагінів Budgie
plugindir = join_paths(get_option('prefix'), 'share', 'budgie-desktop', 'plugins', meson.project_name())

add_project_arguments('--vapidir=' + meson.current_source_dir() + '/vapi', language: 'vala')

sources = [
    'src/SysMonitor.vala',
    'src/SysMonitorWindow.vala',
    'src/SysInfo.vala'
]

conf_data = configuration_data()
plugin_filename = meson.project_name() + '.plugin'
plugin_file_configured = configure_file(
    input: 'data/SysMonitor.plugin.in',
    output: plugin_filename,
    configuration: conf_data,
    install: false
)

add_project_link_arguments('-lm', language: 'c')

# Компіляція і установка .so файлу
shared_module(
    meson.project_name(),
    sources,
    dependencies: deps,
    install: true,
    install_dir: plugindir
)

# Установка .plugin і .css файлів
install_data(plugin_file_configured, install_dir: plugindir)
install_data('data/style.css', install_dir: plugindir)

message('Plugin library (.so) and metadata (.plugin, .css) will be installed to: ' + plugindir)