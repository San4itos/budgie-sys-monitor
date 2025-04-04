// src/SysMonitorWindow.vala
using Gtk;

namespace SysMonitor {
    public class SysMonitorWindow : Gtk.Window {
        // ... (поля класу без змін) ...
        private SysMonitor.Applet applet;
        private Gtk.Entry main_entry;
        // !!! ЗМІНЕНО: Перейменовано commands_box на custom_commands_box для ясності
        private Gtk.Box custom_commands_box;
        private Gtk.SpinButton refresh_interval_spin;
        private const int MAX_COMMANDS = 10;

        // Структура для зручного опису вбудованих тегів
        private struct HardcodedTagInfo {
            public string tag;
            public string description;
        }

        // Список вбудованих тегів
        private const HardcodedTagInfo[] hardcoded_tags = {
            { "[CPU]",    "Відсоток використання ЦП (з libgtop)" },
            { "[MEM]",    "Використання пам'яті (Вик/Заг МБ, з libgtop)" }, // Потрібно буде додати в SysInfo
            { "[SWAP]",   "Використання Swap (Вик/Заг МБ, з libgtop)" },  // Потрібно буде додати в SysInfo
            { "[UPTIME]", "Час роботи системи (з libgtop)" },           // Потрібно буде додати в SysInfo
            { "[LOAD]",   "Середнє навантаження (1хв, з libgtop)" },   // Потрібно буде додати в SysInfo
            { "[CPU_FREQ]", "Макс. частота ЦП (ГГц, з /sys)" }
            // Додавай сюди інші за потреби
        };


        // Конструктор
        public SysMonitorWindow(SysMonitor.Applet parent, string plugin_dir, string initial_text, GenericArray<CommandData?> initial_commands, double initial_interval = 1.0) {
            Object(
                window_position: Gtk.WindowPosition.CENTER,
                default_width: 400,
                // Трохи збільшимо висоту за замовчуванням
                default_height: 450,
                title: "Налаштування Sys Monitor" // Змінено заголовок
            );
            this.applet = parent;

            var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            main_box.margin = 10;
            main_box.get_style_context().add_class("dialog-box");

            // --- Блок Налаштування оновлення ---
            var refresh_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var refresh_label = new Gtk.Label("Час оновлення (сек.):");
            refresh_box.pack_start(refresh_label, false, false, 0);
            var refresh_adjustment = new Gtk.Adjustment (initial_interval, 0.1, 10.0, 0.1, 1.0, 0.0);
            refresh_interval_spin = new Gtk.SpinButton (refresh_adjustment, 0.1, 1);
            refresh_interval_spin.set_numeric(true);
            refresh_interval_spin.set_tooltip_text("Інтервал оновлення даних в секундах (0.1 - 10.0)");
            refresh_box.pack_start(refresh_interval_spin, false, false, 0);
            main_box.pack_start(refresh_box, false, false, 0);

            // --- Блок Шаблону виводу ---
            main_entry = new Gtk.Entry();
            main_entry.set_placeholder_text("Введіть текст для відображення (використовуйте теги)...");
            main_entry.set_text(initial_text);
            main_box.pack_start(main_entry, false, false, 0);

            // --- Роздільник ---
            main_box.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL), false, false, 5);

            // --- Блок Вбудованих тегів ---
            var hardcoded_tags_label = new Gtk.Label("<b>Вбудовані теги (для копіювання):</b>");
            hardcoded_tags_label.use_markup = true;
            hardcoded_tags_label.xalign = 0;
            main_box.pack_start(hardcoded_tags_label, false, false, 5);

            var hardcoded_tags_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5);
            // Можна додати рамку або фон для візуального виділення
            // hardcoded_tags_box.get_style_context().add_class("frame");
            hardcoded_tags_box.margin_bottom = 10; // Відступ знизу
            main_box.pack_start(hardcoded_tags_box, false, false, 0);

            foreach (var tag_info in hardcoded_tags) {
                add_hardcoded_tag_row(hardcoded_tags_box, tag_info.tag, tag_info.description);
            }

             // --- Роздільник ---
            main_box.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL), false, false, 5);


            // --- Блок Користувацьких команд ---
            var custom_commands_label = new Gtk.Label("<b>Команди користувача (тег -> команда):</b>");
            custom_commands_label.use_markup = true;
            custom_commands_label.xalign = 0;
            main_box.pack_start(custom_commands_label, false, false, 5);

            // Використовуємо перейменовану змінну
            custom_commands_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5);
            main_box.pack_start(custom_commands_box, true, true, 0); // Дозволяємо розширюватись

            // Заповнюємо користувацькі команди
            if (initial_commands.length > 0) {
                for (int i = 0; i < initial_commands.length && i < MAX_COMMANDS; i++) {
                    var cmd = initial_commands[i];
                    if (cmd != null && cmd.tag != null && cmd.tag.length > 0 && cmd.command != null && cmd.command.length > 0) {
                        add_command_row_with_data(cmd.tag, cmd.command, true);
                    }
                }
            }
            // Додаємо порожній рядок для користувацьких команд, якщо є місце
            if (custom_commands_box.get_children().length() < MAX_COMMANDS) {
                add_empty_row();
            }

            // --- Кнопка Зберегти ---
            var save_button = new Gtk.Button.with_label("Зберегти");
            save_button.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
            save_button.clicked.connect(() => {
                // Збираємо ТІЛЬКИ користувацькі команди з UI (підтверджені)
                var commands_from_ui = new GenericArray<CommandData?>();
                // !!! ЗМІНЕНО: Ітеруємо по custom_commands_box !!!
                foreach (var child in custom_commands_box.get_children()) {
                    var row = child as Gtk.Box;
                    if (row == null) continue;
                    var children = row.get_children();
                    if (children.length() < 3) continue;

                    var tag_entry = children.nth_data(0) as Gtk.Entry;
                    var command_entry = children.nth_data(1) as Gtk.Entry;
                    var button = children.nth_data(2) as Gtk.Button;

                    if (tag_entry != null && command_entry != null && button != null &&
                        tag_entry.get_text() != null && tag_entry.get_text().length > 0 &&
                        command_entry.get_text() != null && command_entry.get_text().length > 0)
                    {
                        if (button.get_label() == "-") {
                             commands_from_ui.add(CommandData() {
                                tag = tag_entry.get_text(),
                                command = command_entry.get_text()
                            });
                        }
                    }
                }
                if (commands_from_ui.length > MAX_COMMANDS) {
                    commands_from_ui.remove_range(MAX_COMMANDS, commands_from_ui.length - MAX_COMMANDS);
                }

                string current_text = main_entry.get_text();
                double current_interval = refresh_interval_spin.get_value();

                // Викликаємо оновлений метод Applet
                applet.update_configuration(current_text, commands_from_ui, current_interval);

                this.destroy();
            });
            // Додаємо кнопку в самий кінець головного контейнера
            main_box.pack_end(save_button, false, false, 0); // Використовуємо pack_end

            add(main_box);

            this.destroy.connect (() => {
                applet.on_settings_window_destroyed ();
            });
        }

        // --- Допоміжна функція для додавання рядка вбудованого тегу ---
        private void add_hardcoded_tag_row(Gtk.Box container, string tag, string description) {
            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);

            var tag_entry = new Gtk.Entry();
            tag_entry.set_text(tag);
            tag_entry.set_editable(false); // Не можна редагувати
            tag_entry.set_can_focus(false); // Можна прибрати фокус
            tag_entry.set_width_chars(12); // Задаємо ширину для вирівнювання
            tag_entry.set_tooltip_text("Натисніть Ctrl+C, щоб скопіювати тег");
            row.pack_start(tag_entry, false, false, 0);

            var desc_label = new Gtk.Label(description);
            desc_label.xalign = 0; // Вирівнювання тексту зліва
            desc_label.hexpand = true; // Дозволяємо розтягуватися по горизонталі
            desc_label.set_line_wrap(true); // Перенос рядків, якщо опис довгий
            row.pack_start(desc_label, true, true, 0);

            container.pack_start(row, false, false, 0);
        }


        // --- Методи для користувацьких команд ---

        // Додає порожній рядок для введення користувацької команди
        private void add_empty_row() {
             // !!! ЗМІНЕНО: Перевіряємо custom_commands_box !!!
            if (custom_commands_box.get_children().length() >= MAX_COMMANDS) {
                return;
            }
            add_command_row_with_data("", "", false);
        }

        // Додає рядок для користувацької команди (з даними або порожній)
        private void add_command_row_with_data(string tag, string command, bool is_locked) {
             bool tag_is_empty = (tag == null || tag.length == 0);
             bool command_is_empty = (command == null || command.length == 0);

              // !!! ЗМІНЕНО: Перевіряємо custom_commands_box !!!
             if (custom_commands_box.get_children().length() >= MAX_COMMANDS && !is_locked && tag_is_empty && command_is_empty) {
                 return;
             }

            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);

            var tag_entry = new Gtk.Entry();
            tag_entry.set_placeholder_text("Тег ([tag])");
            // Зробимо трохи ширшим для узгодження з вбудованими
            tag_entry.set_width_chars(12);
            tag_entry.set_tooltip_text("Унікальний тег у форматі [my_tag]");
            row.pack_start(tag_entry, false, false, 0);
            tag_entry.set_text(tag);

            var command_entry = new Gtk.Entry();
            command_entry.set_placeholder_text("Команда оболонки (shell)");
            command_entry.hexpand = true;
            command_entry.set_text(command);
            row.pack_start(command_entry, true, true, 0);

            var button = new Gtk.Button();
            row.pack_start(button, false, false, 0);

            if (is_locked) {
                button.set_label("-");
                button.get_style_context().add_class(Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
                button.clicked.connect(() => remove_command_row(row));
                tag_entry.set_editable(false);
                command_entry.set_editable(false);
            } else {
                button.set_label("+");
                button.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                button.set_tooltip_text("Додати/підтвердити команду");

                // Зберігаємо посилання на елементи рядка в кнопці
                button.set_data<Gtk.Entry>("tag_entry", tag_entry);
                button.set_data<Gtk.Entry>("command_entry", command_entry);
                button.set_data<Gtk.Box>("row", row);
                button.clicked.connect(on_add_button_clicked);

                // Зберігаємо посилання на кнопку в полях вводу (для активації по Enter)
                tag_entry.set_data<Gtk.Button>("add_button", button);
                command_entry.set_data<Gtk.Button>("add_button", button);

                tag_entry.activate.connect(on_entry_activate);
                command_entry.activate.connect(on_entry_activate);
            }

            // !!! ЗМІНЕНО: Додаємо до custom_commands_box !!!
            custom_commands_box.pack_start(row, false, false, 0);
            custom_commands_box.show_all();
        }

        // Обробник натискання Enter у полях введення нового рядка
        private void on_entry_activate(Gtk.Entry entry) {
            var button = entry.get_data<Gtk.Button?>("add_button");
            if (button != null && button.get_label() == "+") {
                button.clicked (); // Імітуємо натискання кнопки "+"
            }
        }

        // Обробник натискання кнопки "+"
        private void on_add_button_clicked(Gtk.Button button) {
            var tag_entry = button.get_data<Gtk.Entry>("tag_entry");
            var command_entry = button.get_data<Gtk.Entry>("command_entry");
            var row = button.get_data<Gtk.Box>("row");

            if (tag_entry == null || command_entry == null || row == null) {
                printerr("Error: Could not retrieve row data from button.\n");
                return;
            }

            string tag_text = tag_entry.get_text().strip();
            string command_text = command_entry.get_text().strip();

            // Очищення попередніх стилів помилок
            tag_entry.get_style_context().remove_class("error");
            command_entry.get_style_context().remove_class("error");
            tag_entry.set_tooltip_text("Унікальний тег у форматі [my_tag]"); // Повертаємо стандартний tooltip

            bool is_tag_ok = false;
            bool is_command_ok = (command_text != null && command_text.length > 0); // Команда не може бути порожньою

            // Валідація тегу
            if (tag_text == null || tag_text.length == 0) {
                is_tag_ok = false;
                tag_entry.get_style_context().add_class("error");
                tag_entry.set_tooltip_text("Тег не може бути порожнім");
            } else {
                is_tag_ok = is_valid_tag(tag_text, tag_entry); // is_valid_tag тепер додає стиль та tooltip при помилці
            }

            // Підсвітка помилки для команди, якщо вона порожня
            if (!is_command_ok) {
                 var captured_command_entry = command_entry;
                 GLib.Idle.add (() => {
                    if (captured_command_entry.get_window() != null) {
                        captured_command_entry.get_style_context().add_class("error");
                    }
                    return GLib.Source.REMOVE;
                });
            }


            // Якщо все гаразд, "блокуємо" рядок
            if (is_tag_ok && is_command_ok) {
                button.set_label("-");
                button.get_style_context().remove_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                button.get_style_context().add_class(Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
                button.set_tooltip_text("Видалити команду"); // Оновлюємо tooltip

                // Відключаємо старий обробник і підключаємо новий (видалення)
                button.clicked.disconnect(on_add_button_clicked);
                button.clicked.connect(() => remove_command_row(row));

                tag_entry.set_editable(false);
                command_entry.set_editable(false);

                // Очищуємо дані, пов'язані з кнопкою "+"
                button.set_data<Gtk.Entry?>("tag_entry", null);
                button.set_data<Gtk.Entry?>("command_entry", null);
                button.set_data<Gtk.Box?>("row", null);

                tag_entry.set_data<Gtk.Button?>("add_button", null);
                command_entry.set_data<Gtk.Button?>("add_button", null);
                tag_entry.set_tooltip_text(null); // Прибираємо tooltip у заблокованого тега

                // Додаємо новий порожній рядок, якщо є місце
                // !!! ЗМІНЕНО: Перевіряємо custom_commands_box !!!
                if (custom_commands_box.get_children().length() < MAX_COMMANDS) {
                    add_empty_row();
                }
            }
        }

        // Видаляє рядок користувацької команди
        private void remove_command_row(Gtk.Box row) {
            // !!! ЗМІНЕНО: Видаляємо з custom_commands_box !!!
            custom_commands_box.remove(row);
            // Додаємо порожній рядок, якщо їх стало менше MAX і немає іншого порожнього
            if (custom_commands_box.get_children().length() < MAX_COMMANDS && !has_empty_row()) {
                add_empty_row();
            }
             custom_commands_box.show_all();
        }

        // Перевіряє, чи є вже порожній рядок для введення користувацької команди
        private bool has_empty_row() {
            // !!! ЗМІНЕНО: Перевіряємо custom_commands_box !!!
            foreach (var child in custom_commands_box.get_children()) {
                var row = child as Gtk.Box;
                 if (row == null) continue;
                var children = row.get_children();
                 if (children.length() < 3) continue;
                var button = children.nth_data(2) as Gtk.Button;
                if (button != null && button.get_label() == "+") {
                    return true; // Знайдено рядок з кнопкою "+"
                }
            }
            return false; // Порожнього рядка немає
        }

        // Перевіряє валідність тегу користувача (формат, унікальність)
        private bool is_valid_tag(string tag, Gtk.Entry entry_being_checked) {
            bool is_ok = true;
            string tooltip_message = "Унікальний тег у форматі [my_tag]"; // Повідомлення за замовчуванням

            // Перевірка формату [tag]
            if (tag == null || !tag.has_prefix("[") || !tag.has_suffix("]") || tag.length <= 2) {
                is_ok = false;
                tooltip_message = "Тег має бути у форматі [текст]";
            } else {
                // Перевірка на унікальність серед користувацьких команд
                // !!! ЗМІНЕНО: Перевіряємо custom_commands_box !!!
                foreach (var child in custom_commands_box.get_children()) {
                    var row = child as Gtk.Box;
                    if (row == null) continue;
                    var children = row.get_children();
                    if (children.length() < 1) continue;
                    var existing_tag_entry = children.nth_data(0) as Gtk.Entry;

                    // Не порівнюємо поле саме з собою
                    if (existing_tag_entry == entry_being_checked) {
                        continue;
                    }

                    // Порівнюємо тільки з "заблокованими" тегами (які вже додані)
                    if (existing_tag_entry != null && !existing_tag_entry.get_editable()) {
                        string existing_tag_text = existing_tag_entry.get_text();
                        if (existing_tag_text != null && existing_tag_text == tag) {
                            is_ok = false;
                            tooltip_message = "Цей тег вже використовується";
                            break; // Знайшли дублікат, далі не шукаємо
                        }
                    }
                }
                 // Перевірка на співпадіння з вбудованими тегами
                 if (is_ok) {
                     foreach (var hardcoded in hardcoded_tags) {
                         if (tag == hardcoded.tag) {
                             is_ok = false;
                             tooltip_message = "Цей тег є вбудованим";
                             break;
                         }
                     }
                 }
            }

            // Застосовуємо стиль та tooltip, якщо є помилка
            if (!is_ok) {
                var captured_entry = entry_being_checked;
                var captured_tooltip = tooltip_message;
                GLib.Idle.add (() => {
                    if (captured_entry.get_window() != null) {
                        captured_entry.get_style_context().add_class("error");
                        captured_entry.set_tooltip_text(captured_tooltip);
                    }
                    return GLib.Source.REMOVE;
                });
            }

            return is_ok;
        }

    } // Кінець класу SysMonitorWindow
} // Кінець namespace SysMonitor