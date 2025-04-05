// src/SysMonitor.vala
using Gtk;
using Budgie;
using GLib;

[CCode (cname = "GETTEXT_PACKAGE")] extern const string GETTEXT_PACKAGE;

namespace SysMonitor {

    // Структура для збереження базової конфігурації
    public struct AppConfig {
        public string text;
        public double interval;
    }

    // Структура для збереження даних користувацької команди
    public struct CommandData {
        public string tag;
        public string command;
    }

    // Клас плагіна для Budgie/Peas
    public class Plugin : Budgie.Plugin, Peas.ExtensionBase {
        // Метод, що викликається Budgie для отримання віджету аплету
        public Budgie.Applet get_panel_widget(string uuid) {
            return new Applet(uuid);
        }
    }

    // Основний клас аплету
    public class Applet : Budgie.Applet {

        private Gtk.EventBox widget; // Контейнер для кліків
        private Gtk.Label label;     // Мітка для відображення тексту
        private string plugin_dir;   // Шлях до директорії плагіна (для CSS)
        private string config_dir;   // Шлях до директорії конфігурації
        private double current_interval = 1.0; // Поточний інтервал оновлення
        private uint timer_id = 0;   // ID таймера для його зупинки
        private string template_text = "..."; // Шаблон тексту для відображення
        private GenericArray<CommandData?> current_commands = new GenericArray<CommandData?>(); // Масив користувацьких команд
        private bool is_destroyed = false; // Прапорець, що аплет знищено

        // Поле для зберігання посилання на вікно налаштувань
        private SysMonitorWindow? settings_window = null;

        // Екземпляр SysInfo для отримання системних даних
        private SysInfo sys_info = new SysInfo();

        // Конструктор аплету
        public Applet(string uuid) {
            // !!! ДОДАНО/ПЕРЕВІРЕНО ЛОГ У КОНСТРУКТОР !!!
            stdout.printf("<<<<< Applet CONSTRUCTOR CALLED (UUID: %s) >>>>>\n", uuid);

            // !!! ВИПРАВЛЕНА ІНІЦІАЛІЗАЦІЯ Gettext (версія 3) !!!
            try {
                // 1. Встановлюємо локаль з системних налаштувань
                string? current_locale = Intl.setlocale (LocaleCategory.ALL, "");
                stdout.printf("Gettext: Locale set to %s\n", current_locale ?? "(null)");

                // 2. Визначаємо шлях до .mo файлів
                string? data_home = Environment.get_user_data_dir (); // -> ~/.local/share
                string localedir_user = "";
                string localedir_system = "/usr/share/locale"; // Стандартний системний
                string final_localedir;

                // Формуємо шлях до користувацької директорії локалей
                if (data_home != null) {
                    localedir_user = GLib.Path.build_filename(data_home, "locale");
                }

                // Перевіряємо, чи існує користувацька директорія локалей
                // І використовуємо її, якщо вона існує
                if (localedir_user != "" && FileUtils.test(localedir_user, FileTest.IS_DIR)) {
                    final_localedir = localedir_user;
                }
                // В іншому випадку використовуємо системний шлях
                else {
                    final_localedir = localedir_system;
                }

                stdout.printf("Gettext: Binding textdomain '%s' to dir '%s'\n", GETTEXT_PACKAGE, final_localedir);

                // 3. Прив'язуємо текстовий домен до знайденої директорії
                Intl.bindtextdomain(GETTEXT_PACKAGE, final_localedir);
                // 4. Вказуємо кодування (зазвичай UTF-8)
                Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "UTF-8");
                // 5. Активуємо наш текстовий домен
                Intl.textdomain(GETTEXT_PACKAGE);
                stdout.printf("Gettext initialized for domain '%s'.\n", GETTEXT_PACKAGE);

            } catch (Error e) {
                printerr("Error initializing Gettext: %s\n", e.message);
            }
            // !!! Кінець ініціалізації Gettext !!!

            // Визначаємо шляхи та завантажуємо конфігурацію
            plugin_dir = get_plugin_dir();
            config_dir = get_config_dir();
            load_full_config();

            // Створюємо віджети
            widget = new Gtk.EventBox();
            label = new Gtk.Label("..."); // Початковий текст
            label.get_style_context().add_class("sys-monitor-label"); // Додаємо клас для CSS
            widget.add(label);

            // Завантажуємо CSS, якщо є
            var css_path = GLib.Path.build_filename(plugin_dir, "style.css");
            if (FileUtils.test(css_path, FileTest.EXISTS)) {
                var provider = new Gtk.CssProvider();
                try {
                    provider.load_from_path(css_path);
                    Gtk.StyleContext.add_provider_for_screen(
                        Gdk.Screen.get_default(),
                        provider,
                        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                    );
                } catch (Error e) {
                    stderr.printf("Error loading CSS: %s\n", e.message);
                }
            }

            // Підключаємо обробник кліку по аплету
            widget.button_press_event.connect(on_button_press);
            // Запускаємо таймер оновлення
            start_or_restart_timer();

            // Додаємо віджет до аплету та показуємо все
            this.add(widget);
            this.show_all();
        }

        // Обробник натискання кнопки миші на аплеті
        private bool on_button_press(Gtk.Widget widget, Gdk.EventButton event) {
            // Реагуємо тільки на ліву кнопку миші (button 1)
            if (event.button != 1) {
                return Gdk.EVENT_PROPAGATE; // Інші кнопки ігноруємо
            }

            // Перевіряємо, чи вікно налаштувань вже відкрито
            if (this.settings_window != null) {
                // Якщо так, виводимо його на передній план і даємо фокус
                stdout.printf("Settings window already open. Presenting.\n");
                this.settings_window.present();
            } else {
                // Якщо ні, створюємо новий екземпляр вікна
                stdout.printf("No settings window found. Creating new.\n");
                this.settings_window = new SysMonitorWindow(
                    this, // Передаємо посилання на себе (Applet)
                    plugin_dir,
                    this.template_text, // Поточний шаблон
                    this.current_commands, // Поточні команди
                    this.current_interval // Поточний інтервал
                );
                // Показуємо створене вікно
                this.settings_window.show_all();
            }

            return Gdk.EVENT_STOP; // Зупиняємо подальшу обробку події кліку
        }

        // Метод, що викликається вікном налаштувань при його закритті (сигнал destroy)
        public void on_settings_window_destroyed() {
            stdout.printf("Settings window destroyed signal received. Clearing reference.\n");
            this.settings_window = null; // Скидаємо посилання, щоб можна було створити нове вікно
        }

        // Метод для оновлення конфігурації з вікна налаштувань
        public void update_configuration(string new_text, GenericArray<CommandData?> commands_from_ui, double new_interval) {
            // Оновлюємо внутрішні дані аплету
            this.template_text = new_text;
            this.current_interval = new_interval;
            this.current_commands = commands_from_ui; // Повністю замінюємо масив команд

            // Зберігаємо нову конфігурацію в JSON файл
            save_config_to_json();

            // Перезапускаємо таймер і негайно оновлюємо мітку
            start_or_restart_timer(true); // true - оновити одразу

            stdout.printf("Configuration updated. Interval: %.1f seconds. Commands: %d\n", this.current_interval, this.current_commands.length);
        }

        // Завантаження повної конфігурації з JSON файлу
        private void load_full_config() {
            // Значення за замовчуванням
            var config = AppConfig() { text = _("Натисни мене та зміни цей текст..."), interval = 1.0 }; // Приклад дефолтного тексту
            var commands = new GenericArray<CommandData?>();
            var json_path = GLib.Path.build_filename(config_dir, "config.json");

            // Якщо файлу немає, створюємо його з дефолтними значеннями
            if (!FileUtils.test(json_path, FileTest.EXISTS)) {
                this.template_text = config.text;
                this.current_interval = config.interval;
                this.current_commands = new GenericArray<CommandData?>(); // Порожній масив команд
                stdout.printf("Config file not found. Creating default config at %s\n", json_path);
                save_config_to_json(); // Зберігаємо дефолтний конфіг
                return;
            }

            // Якщо файл є, намагаємося прочитати і розпарсити
            try {
                string contents;
                FileUtils.get_contents(json_path, out contents);
                Json.Parser parser = new Json.Parser();
                parser.load_from_data(contents);
                var root_node = parser.get_root();
                if (root_node == null || root_node.get_node_type() != Json.NodeType.OBJECT) {
                    throw new Error(Quark.from_string("JSON"), 1, "Root is not an object");
                }
                var root = root_node.get_object();

                // Читаємо текст шаблону
                if (root.has_member("text")) {
                    config.text = root.get_string_member("text");
                } else { stderr.printf("Warning: 'text' member missing in config, using default.\n"); }

                // Читаємо інтервал оновлення
                if (root.has_member("refresh_interval")) {
                    var interval_node = root.get_member("refresh_interval");
                    // Перевіряємо тип значення
                    if (interval_node != null && interval_node.get_node_type() == Json.NodeType.VALUE && interval_node.get_value_type() == typeof(double)) {
                        config.interval = root.get_double_member("refresh_interval");
                        // Обмежуємо інтервал розумними межами
                        if (config.interval < 0.1) config.interval = 0.1;
                        if (config.interval > 10.0) config.interval = 10.0;
                     } else { stderr.printf("Warning: 'refresh_interval' invalid or missing in config, using default.\n"); }
                } else { stderr.printf("Warning: 'refresh_interval' member missing in config, using default.\n"); }

                 // Читаємо масив команд
                 if (root.has_member("commands")) {
                     var commands_array = root.get_array_member("commands");
                     if (commands_array != null) {
                        for (int i = 0; i < commands_array.get_length(); i++) {
                            var cmd_obj = commands_array.get_object_element(i);
                            // Перевіряємо, чи це об'єкт і чи має він потрібні поля
                            if (cmd_obj != null && cmd_obj.has_member("tag") && cmd_obj.has_member("command")) {
                                string tag = cmd_obj.get_string_member("tag");
                                string command = cmd_obj.get_string_member("command");
                                // Додаємо тільки якщо тег і команда не порожні
                                if(tag != null && tag.length > 0 && command != null && command.length > 0) {
                                    commands.add(CommandData() { tag = tag, command = command });
                                }
                            }
                        }
                     }
                } else { stderr.printf("Warning: 'commands' member missing in config.\n"); }

            } catch (Error e) {
                stderr.printf("Error loading config from %s: %s\n Using defaults.\n", json_path, e.message);
                // У разі помилки використовуємо значення за замовчуванням
                config.text = "[CPU] | [MEM]";
                config.interval = 1.0;
                commands = new GenericArray<CommandData?>();
            }

            // Застосовуємо завантажену або дефолтну конфігурацію
            this.template_text = config.text;
            this.current_interval = config.interval;
            this.current_commands = commands;
            stdout.printf("Config loaded. Interval: %.1f, Text: '%s', Commands: %d\n",
                this.current_interval, this.template_text, this.current_commands.length);
        }

        // Збереження поточної конфігурації в JSON файл
        private void save_config_to_json() {
            var json_path = GLib.Path.build_filename(config_dir, "config.json");
            try {
                // Переконуємося, що директорія існує
                var dir_path = Path.get_dirname(json_path);
                var dir_file = File.new_for_path(dir_path);
                if (!dir_file.query_exists(null)) {
                    dir_file.make_directory_with_parents(null);
                    stdout.printf("Created config directory: %s\n", dir_path);
                }

                // Будуємо JSON об'єкт
                var builder = new Json.Builder();
                builder.begin_object();
                builder.set_member_name("text");
                builder.add_string_value(this.template_text ?? ""); // Зберігаємо порожній рядок, якщо null
                builder.set_member_name("refresh_interval");
                builder.add_double_value(this.current_interval);
                builder.set_member_name("commands");
                builder.begin_array();
                // Додаємо тільки валідні команди
                foreach (var cmd in this.current_commands) {
                    if (cmd != null && cmd.tag != null && cmd.tag.length > 0 && cmd.command != null && cmd.command.length > 0) {
                        builder.begin_object();
                        builder.set_member_name("tag");
                        builder.add_string_value(cmd.tag);
                        builder.set_member_name("command");
                        builder.add_string_value(cmd.command);
                        builder.end_object();
                    }
                }
                builder.end_array();
                builder.end_object();

                // Генеруємо рядок JSON з відступами
                var generator = new Json.Generator();
                generator.set_root(builder.get_root());
                generator.set_pretty(true); // Робимо файл читабельним
                string json_data = generator.to_data(null);

                // Записуємо в файл
                FileUtils.set_contents(json_path, json_data);
                stdout.printf("Configuration saved to %s\n", json_path);

            } catch (Error e) {
                stderr.printf("Error saving config to %s: %s\n", json_path, e.message);
            }
        }

        // Визначення директорії плагіна (де лежить CSS)
        private string get_plugin_dir() {
             // Перебираємо можливі стандартні шляхи
             string[] possible_paths = {
                // Шлях користувача (пріоритет)
                GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "budgie-desktop", "plugins", "sysmonitor"),
                // Системні шляхи
                "/usr/share/budgie-desktop/plugins/sysmonitor",
                "/usr/local/share/budgie-desktop/plugins/sysmonitor",
                // Старий шлях користувача (менш ймовірний)
                GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".local", "share", "budgie-desktop", "plugins", "sysmonitor")
            };

            foreach (string path in possible_paths) {
                // Перевіряємо наявність файлу, який точно має бути в директорії плагіна
                string check_file = GLib.Path.build_filename(path, "libsysmonitor.so"); // Або SysMonitor.plugin
                if (FileUtils.test(check_file, FileTest.EXISTS)) {
                    stdout.printf("Plugin directory found at: %s\n", path);
                    return path;
                }
            }

            // Якщо не знайшли, повертаємо стандартний шлях користувача як запасний варіант
            var default_path = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "budgie-desktop", "plugins", "sysmonitor");
            stdout.printf("Plugin directory not found in standard locations. Assuming: %s\n", default_path);
            // Спробуємо створити директорію, якщо її немає (на випадок ручного копіювання)
            var file = File.new_for_path (default_path);
            try {
                if (!file.query_exists (null)) {
                   file.make_directory_with_parents (null);
                   stdout.printf("Created potential plugin directory: %s\n", default_path);
                }
            } catch (Error e) {
                stderr.printf("Warning: Could not create potential plugin directory %s: %s\n", default_path, e.message);
            }
            return default_path;
         }

        // Визначення директорії для конфігураційного файлу
        private string get_config_dir() {
            // Пріоритет: директорія даних користувача (стандарт XDG)
            string user_config_path = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(), "budgie-sys-monitor");
            var user_config_dir = File.new_for_path(user_config_path);

            try {
                 // Перевіряємо, чи існує директорія, якщо ні - створюємо
                if (!user_config_dir.query_exists(null)) {
                    user_config_dir.make_directory_with_parents(null);
                    stdout.printf("Created config directory: %s\n", user_config_path);
                    return user_config_path; // Використовуємо щойно створену директорію
                }

                // Перевіряємо права на запис, створюючи тимчасовий файл
                 var test_file = user_config_dir.get_child("write_test.tmp");
                 OutputStream stream = test_file.replace(null, false, FileCreateFlags.REPLACE_DESTINATION);
                 stream.close(null); // Закриваємо потік
                 test_file.delete(null); // Видаляємо тестовий файл
                 stdout.printf("Using config directory: %s\n", user_config_path);
                 return user_config_path; // Права є, використовуємо цю директорію

            } catch (Error e) {
                 // Якщо сталася помилка (немає прав, не вдалося створити)
                 stderr.printf("Warning: Could not use or create %s: %s\n", user_config_path, e.message);
                 // Використовуємо директорію плагіна як запасний варіант
                 stdout.printf("Falling back to plugin directory for config: %s\n", plugin_dir);
                 // Тут також варто було б перевірити права на запис, але поки спрощуємо
                 return plugin_dir;
            }
        }


        // Запуск або перезапуск таймера оновлення
        private void start_or_restart_timer(bool immediate_update = false) {
             // Зупиняємо попередній таймер, якщо він був активний
             if (timer_id > 0) {
                Source.remove (timer_id);
                timer_id = 0;
            }
            // Розраховуємо інтервал в мілісекундах, обмежуємо межами
            uint interval_ms = (uint)(this.current_interval * 1000.0);
            if (interval_ms < 100) interval_ms = 100;     // Мінімум 0.1 сек
            if (interval_ms > 10000) interval_ms = 10000; // Максимум 10 сек
            stdout.printf("Starting timer with interval: %u ms (%.1f s)\n", interval_ms, this.current_interval);

            // Негайно оновлюємо мітку, якщо потрібно
            if (immediate_update) {
                update_label_content();
            }

            // Додаємо новий таймер
            timer_id = Timeout.add (interval_ms, () => {
                update_label_content(); // Функція, що викликається таймером
                return Source.CONTINUE; // Повертаємо true, щоб таймер продовжував працювати
            });
        }

       // Основна функція оновлення тексту мітки
       private void update_label_content() {
            // Перевіряємо, чи аплет не був знищений, поки чекали виконання таймера
            if (is_destroyed) return;

            string processed_text = this.template_text; // Починаємо з вихідного шаблону

            // --- ОБРОБКА ВБУДОВАНИХ ТЕГІВ ---
            try {
                // [CPU]
                if (processed_text.contains("[CPU]")) {
                    int cpu_perc = sys_info.get_cpu_percentage();
                    string cpu_text = (cpu_perc >= 0) ? cpu_perc.to_string() + "%" : "[CPU ERR]";
                    processed_text = processed_text.replace("[CPU]", cpu_text);
                }

                 // [CPU_FREQ]
                 if (processed_text.contains("[CPU_FREQ]")) {
                    double freq_khz = sys_info.get_cpu_frequency_khz();
                    string freq_text = (freq_khz > 0) ? "%.1f GHz".printf(freq_khz / 1000000.0) : "[FREQ ERR]";
                    processed_text = processed_text.replace("[CPU_FREQ]", freq_text);
                }

                // [MEM] !!!
                if (processed_text.contains("[MEM]")) {
                    int mem_perc = SysInfo.get_mem_percentage(); // Статичний метод
                    string mem_text = (mem_perc >= 0) ? mem_perc.to_string() + "%" : "[MEM ERR]";
                    processed_text = processed_text.replace("[MEM]", mem_text);
                }

                // [SWAP] !!!
                if (processed_text.contains("[SWAP]")) {
                    int swap_perc = SysInfo.get_swap_percentage(); // Статичний метод
                    // Якщо swap = 0%, можливо, він просто вимкнений або не використовується
                    string swap_text = (swap_perc >= 0) ? swap_perc.to_string() + "%" : "[SWAP ERR]";
                    processed_text = processed_text.replace("[SWAP]", swap_text);
                }

                bool has_dl = processed_text.contains("[DL]");
                bool has_up = processed_text.contains("[UP]");

                if (has_dl || has_up) {
                    // Отримуємо структуру зі швидкостями DL та UP в KiB/s
                    NetworkSpeeds speeds = SysInfo.get_network_speeds();

                    // Обробляємо [DL]
                    if (has_dl) {
                        string dl_text = SysInfo.format_speed(speeds.dl_kibps);
                        processed_text = processed_text.replace("[DL]", dl_text);
                    }

                    // Обробляємо [UP]
                    if (has_up) {
                        string up_text = SysInfo.format_speed(speeds.ul_kibps);
                        processed_text = processed_text.replace("[UP]", up_text);
                    }
                }

            } catch (Error e) {
                printerr("Error processing internal tags: %s\n", e.message);
                // Замінюємо потенційно проблемні теги на [ERR]
                processed_text = processed_text.replace("[CPU]", "[ERR]");
                processed_text = processed_text.replace("[CPU_FREQ]", "[ERR]");
                processed_text = processed_text.replace("[MEM]", "[ERR]");
                processed_text = processed_text.replace("[SWAP]", "[ERR]");
                processed_text = processed_text.replace("[DL]", "[NET ERR]");
                processed_text = processed_text.replace("[UP]", "[NET ERR]");
                // ... і т.д.
            }


            // --- ОБРОБКА КОРИСТУВАЦЬКИХ КОМАНД ---
            foreach (var cmd_data in this.current_commands) {
                 // Пропускаємо невалідні записи
                 if (cmd_data == null || cmd_data.tag == null || cmd_data.command == null
                    || cmd_data.tag.length == 0 || cmd_data.command.length == 0) {
                    continue;
                }

                string tag = cmd_data.tag;

                // Перевіряємо, чи цей тег ще існує в рядку (можливо, його замінив вбудований тег)
                if (!processed_text.contains(tag)) {
                    continue;
                }

                string command_str = cmd_data.command;
                string replacement_text = ""; // Текст для заміни тега

                // Виконуємо команду синхронно
                try {
                    string[] argv = {};
                    // Парсимо рядок команди на аргументи
                    if (!GLib.Shell.parse_argv(command_str, out argv)) {
                        throw new Error(Quark.from_string("SHELL"), 1, "Failed to parse command: " + command_str);
                    }

                    string standard_output;
                    string standard_error;
                    int exit_status;

                    // Запускаємо процес
                    // Це блокуючий виклик! Якщо команда виконується довго, панель може "зависнути".
                    GLib.Process.spawn_sync(
                        null,       // Робоча директорія (поточна)
                        argv,       // Масив аргументів
                        null,       // Змінні середовища (успадковуються)
                        GLib.SpawnFlags.SEARCH_PATH, // Шукати команду в PATH
                        null,       // Функція налаштування дочірнього процесу
                        out standard_output, // Сюди запишеться stdout
                        out standard_error,  // Сюди запишеться stderr
                        out exit_status      // Сюди запишеться код виходу
                    );

                    // Аналізуємо результат
                    if (exit_status != 0) {
                        // Якщо помилка, показуємо код помилки
                        replacement_text = "[ERR:%d]".printf(exit_status);
                        // Виводимо stderr в консоль панелі для діагностики
                        if (standard_error != null && standard_error.length > 0) {
                            stderr.printf("Cmd '%s' err (exit %d): %s\n", command_str, exit_status, standard_error.strip());
                        } else {
                            stderr.printf("Cmd '%s' failed with exit %d (no stderr)\n", command_str, exit_status);
                        }
                    } else if (standard_output != null) {
                        // Якщо успішно, використовуємо stdout (прибираємо зайві пробіли/переноси)
                        replacement_text = standard_output.strip();
                    } else {
                        // Якщо stdout порожній, замінюємо на порожній рядок
                        replacement_text = "";
                    }

                } catch (SpawnError e) { // Помилка запуску процесу
                     stderr.printf("Failed to spawn cmd '%s': %s\n", command_str, e.message);
                     replacement_text = "[SPAWN ERR]";
                } catch (Error e) { // Інші помилки (напр., парсингу команди)
                     stderr.printf("Error processing cmd '%s': %s\n", command_str, e.message);
                     replacement_text = "[PROC ERR]";
                }

                // Замінюємо тег результатом
                processed_text = processed_text.replace(tag, replacement_text);
            }


            // --- ОНОВЛЕННЯ МІТКИ НА ПАНЕЛІ ---
            // Робимо це через Idle.add, щоб гарантовано виконати в головному потоці GTK
            Idle.add(() => {
                // Ще раз перевіряємо, чи аплет не знищено за цей час
                if (!is_destroyed) {
                    label.set_text(processed_text); // Встановлюємо фінальний текст
                }
                return Source.REMOVE; // Виконати лямбду тільки один раз
            });
        }

        // Метод, що викликається при знищенні аплету
         public override void destroy () {
            stdout.printf("<<<<< Applet DESTROY CALLED >>>>>\n");
            this.is_destroyed = true; // Встановлюємо прапорець
            // Зупиняємо таймер
            if (timer_id > 0) {
                Source.remove (timer_id);
                timer_id = 0;
            }
            // Якщо вікно налаштувань було відкрито, закриваємо його
            if (this.settings_window != null) {
                stdout.printf("Applet destroying, also destroying settings window.\n");
                this.settings_window.destroy (); // Викликаємо знищення вікна
                this.settings_window = null; // Скидаємо посилання
            }
            // Викликаємо метод destroy базового класу
            base.destroy ();
            stdout.printf("Applet destroyed.\n");
        }

    } // Кінець класу Applet

} // Кінець namespace SysMonitor


// Ініціалізація модуля для Peas
[ModuleInit]
public void peas_register_types(TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    // Реєструємо наш клас Plugin як розширення для типу Budgie.Plugin
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SysMonitor.Plugin));
}