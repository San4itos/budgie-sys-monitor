# po/meson.build

langs = ['en']
potfiles_sources_paths = [ meson.project_source_root() + '/src/SysMonitor.vala', meson.project_source_root() + '/src/SysMonitorWindow.vala' ]
domain = 'sysmonitor'
gettext_package_name = domain

xgettext = find_program('xgettext', required : true)
msgfmt = find_program('msgfmt', required : true)
msgmerge = find_program('msgmerge', required : true)
msginit = find_program('msginit', required : true)

# Генеруємо pot файл
vala_files_for_pot = files(potfiles_sources_paths) # Створюємо об'єкти файлів Vala
pot_target = custom_target(domain + '.pot',
    input: vala_files_for_pot, # Явна залежність від .vala файлів
    output: domain + '.pot',
    command: [ xgettext, '--package-name=' + meson.project_name(), '--package-version=' + meson.project_version(), '--default-domain=' + domain, '--language=Vala', '--from-code=UTF-8', '--output=@OUTPUT@', '--keyword=_', '--add-comments=TRANSLATORS:', vala_files_for_pot ],
    build_by_default: true
)

# Оновлюємо/створюємо та компілюємо/встановлюємо
po_targets = [] # Для цілі update-po
foreach lang : langs
    po_file = lang + '.po'
    po_path = meson.current_source_dir() / po_file
    po_file_obj = files(po_file) # Об'єкт файлу po/en.po

    po_exists = run_command('test', '-f', po_path, check: false).returncode() == 0

    # Цілі для оновлення/ініціалізації (виконуються вручну через 'update-po')
    if po_exists
        update_po = custom_target(lang + '_po_update',
            input: pot_target, # Залежить від .pot
            output: lang + '.po.update', # Фіктивний вихід
            command: [ msgmerge, '--update', '--quiet', '--backup=none', po_path, '@INPUT@' ], # Оновлюємо po_path
            build_by_default: false # Не виконувати за замовчуванням
        )
        po_targets += update_po
        dependency_for_mo = update_po # .mo залежить від результату оновлення
    else
        init_po = custom_target(lang + '_po_init',
            input: pot_target, # Залежить від .pot
            output: lang + '.po.init', # Фіктивний вихід
            command: [ msginit, '--input=@INPUT@', '--output-file=' + po_path, '--locale=' + lang ], # Створюємо po_path
            build_by_default: false # Не виконувати за замовчуванням
        )
        po_targets += init_po
        dependency_for_mo = init_po # .mo залежить від результату ініціалізації
    endif

    # Компіляція MO файлів
    mo_target = custom_target(lang + '_mo',
        input: po_file_obj, # Залежить від існування/змісту po/en.po
        # !!! ВАЖЛИВО: Залежить від цілі оновлення/ініціалізації !!!
        # Щоб .mo компілювався ПІСЛЯ того, як .po міг бути змінений
        depends: dependency_for_mo,
        output: gettext_package_name + '.mo', # Правильне ім'я файлу у builddir
        command: [
            msgfmt,
            '--output-file=@OUTPUT@',
            '@INPUT@' # !!! Використовуємо @INPUT@, що посилається на po_file_obj !!!
        ],
        install: true,
        install_dir: join_paths(get_option('prefix'), get_option('datadir'), 'locale', lang, 'LC_MESSAGES'),
        build_by_default: true # Компілювати .mo під час ninja
    )
endforeach

if po_targets.length() > 0 # Перевірка, що список цілей не порожній
    run_target('update-po',
        # !!! ПОВЕРТАЄМО просту команду echo !!!
        command: ['echo', 'Manual PO update/init targets triggered.'],
        # Залежність від цілей оновлення/ініціалізації
        depends: po_targets
    )
endif