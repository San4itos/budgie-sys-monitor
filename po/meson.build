# po/meson.build

langs = ['uk']
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

    po_exists = run_command('test', '-f', po_path, check: false).returncode() == 0

    if po_exists
        po_file_obj = files(po_file)

        update_po = custom_target(lang + '_po_update',
            input: pot_target,
            output: lang + '.po.update',
            command: [ msgmerge, '--update', '--quiet', '--backup=none', po_path, '@INPUT@' ],
            build_by_default: false
        )
        po_targets += update_po
        dependency_for_mo = update_po
    else
        init_po = custom_target(lang + '_po_init',
            input: pot_target,
            output: lang + '.po.init',
            command: [ msginit, '--no-translator', '--input=@INPUT@', '--output-file=' + po_path, '--locale=' + lang ],
            build_by_default: false
        )
        
        po_targets += init_po
        dependency_for_mo = init_po

        # Генеруємо об'єкт, щоб msgfmt не зламався (тільки для .mo)
        po_file_obj = custom_target(lang + '_fake_po_for_mo',
            input: init_po,
            output: po_file,
            command: ['cat', po_path], # трюк — використовує вже створений po файл
        )
    endif

    mo_target = custom_target(lang + '_mo',
        input: po_file_obj,
        depends: dependency_for_mo,
        output: gettext_package_name + '.mo',
        command: [
            msgfmt,
            '--output-file=@OUTPUT@',
            '@INPUT@'
        ],
        install: true,
        install_dir: join_paths(get_option('prefix'), get_option('datadir'), 'locale', lang, 'LC_MESSAGES'),
        build_by_default: true
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