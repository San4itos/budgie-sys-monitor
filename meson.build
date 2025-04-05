# meson.build

project('sysmonitor', # Або 'budgie-sysmonitor', як у тебе
        ['c', 'vala'],
        version: '0.1.0',
        meson_version: '>= 0.60.0', # Або '>= 0.50.0'
        # default_options: ['warning_level=2'] # Можна додати
)

# i18n = import('i18n') # Імпорт потрібен для po/meson.build, але не тут

deps = [
    dependency('gtk+-3.0', version: '>= 3.18.0'),
    dependency('budgie-1.0'), # Без версії
    dependency('libpeas-1.0', version: '>= 1.8.0'),
    dependency('json-glib-1.0'),
    dependency('libgtop-2.0')
]

# Твій шлях встановлення
install_dir = join_paths(get_option('prefix'), 'share', 'budgie-desktop', 'plugins', 'sysmonitor')

add_project_arguments('--vapidir=' + meson.current_source_dir() + '/vapi', language : 'vala')
# add_project_arguments('--enable-experimental-non-null', language : 'vala') # Якщо потрібно

# !!! ДОДАНО: Визначаємо змінні для gettext !!!
gettext_package_name = 'sysmonitor' # Назва твого текстового домену
localedir = join_paths(get_option('prefix'), get_option('datadir'), 'locale')
add_project_arguments('-DGETTEXT_PACKAGE="' + gettext_package_name + '"', language : 'c')
# !!! Кінець доданих змінних !!!

sources = [
    'src/SysMonitor.vala',
    'src/SysMonitorWindow.vala',
    'src/SysInfo.vala'
]

plugin_filename = 'SysMonitor.plugin'
plugin_file_configured = configure_file(
    input: 'data/SysMonitor.plugin.in',
    output: plugin_filename,
    # configuration: conf_data, # Замінено на copy: true
    copy: true, # Просте копіювання, якщо немає змінних для заміни
    install: false
)

# Додаємо -lm для математичних функцій
add_project_link_arguments('-lm', language : 'c')

# Використовуй або shared_library, або shared_module
shared_library( # Або shared_module(meson.project_name(), ... )
    'sysmonitor',
    sources,
    dependencies: deps,
    install: true,
    install_dir: install_dir # Твій шлях
)

install_data(
    plugin_file_configured,
    'data/style.css',
    install_dir: install_dir # Твій шлях
)

# Викликаємо subdir для po
subdir('po')

message('Plugin files (.so, .plugin, .css) will be installed to: ' + install_dir)
message('Locale files (.mo) will be installed to corresponding subdirs in: ' + localedir)