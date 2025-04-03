project('budgie-sysmonitor',
        ['c', 'vala'],
        version: '0.1.0',
        meson_version: '>= 0.40.0',
)

deps = [
    dependency('gtk+-3.0', version: '>= 3.18.0'),
    dependency('budgie-1.0', version: '>= 2'),
    dependency('libpeas-1.0', version: '>= 1.8.0'),
    dependency('json-glib-1.0'),
]

install_dir = join_paths(get_option('prefix'), 'share', 'budgie-desktop', 'plugins', 'sysmonitor')

shared_library(
    'sysmonitor',
    [
        'src/SysMonitor.vala',
        'src/SysMonitorWindow.vala',
    ],
    dependencies: deps,
    install: true,
    install_dir: install_dir
)

install_data(
    'data/SysMonitor.plugin',
    'data/style.css',
    'data/config.json',  # Додаємо JSON
    install_dir: install_dir
)