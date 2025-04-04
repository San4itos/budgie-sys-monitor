# Зберігаємо твою назву проєкту
project('budgie-sysmonitor',
        ['c', 'vala'], # Мова 'c' може бути потрібна для залежностей Vala
        version: '0.1.0',
        meson_version: '>= 0.40.0', # Зберігаємо твою версію Meson
)

# --- Залежності ---
deps = [
    dependency('gtk+-3.0', version: '>= 3.18.0'),
    # Зберігаємо твою версію Budgie
    dependency('budgie-1.0', version: '>= 2'),
    dependency('libpeas-1.0', version: '>= 1.8.0'),
    dependency('json-glib-1.0'),
    # !!! ДОДАНО: Необхідно для SysInfo.vala
    dependency('libgtop-2.0')
]

# --- Шлях встановлення ---
# Зберігаємо твій шлях встановлення
install_dir = join_paths(get_option('prefix'), 'share', 'budgie-desktop', 'plugins', 'sysmonitor')
# Важливо: Budgie має бути налаштований шукати плагіни і в цій директорії.
# Він знайде плагін завдяки .plugin файлу, але .so бібліотека теж опиниться тут.

# --- Обробка VAPI ---
# !!! ДОДАНО: Вказуємо Meson шукати VAPI файли (libgtop-2.0.vapi) у директорії 'vapi'
add_project_arguments('--vapidir=' + meson.current_source_dir() + '/vapi', language : 'vala')

# --- Вихідні файли ---
sources = [
    'src/SysMonitor.vala',
    'src/SysMonitorWindow.vala',
    # !!! ДОДАНО: SysInfo.vala має бути включений до списку джерел
    'src/SysInfo.vala'
]

# --- Конфігурація файлу плагіна (.plugin) ---
# !!! ЗМІНЕНО: Використовуємо шаблон .plugin.in
conf_data = configuration_data()
# conf_data.set('VERSION', meson.project_version()) # Можна додати, якщо в шаблоні є @VERSION@

# Важливо: Вміст файлу 'data/SysMonitor.plugin.in' має вказувати 'Module=sysmonitor',
# щоб відповідати назві бібліотеки нижче.
plugin_filename = 'SysMonitor.plugin' # Зберігаємо твою назву файлу

plugin_file_configured = configure_file(
  input : 'data/SysMonitor.plugin.in', # Переконайся, що ти перейменував файл!
  output : plugin_filename,
  configuration : conf_data,
  install : false # Встановимо явно нижче
)

# --- Компіляція модуля плагіна ---
# Зберігаємо твою назву бібліотеки 'sysmonitor' (має відповідати Module= у .plugin файлі)
shared_library(
    'sysmonitor',
    sources, # Використовуємо змінну sources
    dependencies: deps,
    install: true,
    # Зберігаємо твій шлях встановлення
    install_dir: install_dir
)

# --- Встановлення даних ---
# Встановлюємо згенерований .plugin файл та CSS
install_data(
    plugin_file_configured, # Встановлюємо згенерований файл
    'data/style.css',
    # !!! ВИДАЛЕНО: Не встановлюємо config.json
    # 'data/config.json',
    install_dir: install_dir # Встановлюємо у твою директорію
)

# --- Інформаційне повідомлення ---
message('Plugin files (.so, .plugin, .css) will be installed to: ' + install_dir)