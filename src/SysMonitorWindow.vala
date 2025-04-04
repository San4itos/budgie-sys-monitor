// src/SysMonitorWindow.vala

using Gtk;

namespace SysMonitor {

    public class SysMonitorWindow : Gtk.Window {
        private SysMonitor.Applet applet;
        private Gtk.Entry main_entry;
        private Gtk.Box commands_box;
        private const int MAX_COMMANDS = 10;

        public SysMonitorWindow(SysMonitor.Applet parent, string plugin_dir, string initial_text, GenericArray<CommandData?> initial_commands) {
            Object(
                window_position: Gtk.WindowPosition.CENTER,
                default_width: 400,
                default_height: 300,
                title: "Sys Monitor Settings"
            );
            this.applet = parent;

            var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            main_box.margin = 10;
            main_box.get_style_context().add_class("dialog-box"); // Переконайтесь, що клас визначено в CSS

            main_entry = new Gtk.Entry();
            main_entry.set_placeholder_text("Введіть текст для відображення...");
            main_entry.set_text(initial_text);
            main_box.pack_start(main_entry, false, false, 0);

            var commands_label = new Gtk.Label("<b>Команди (тег -> команда):</b>");
            commands_label.use_markup = true;
            commands_label.xalign = 0;
            main_box.pack_start(commands_label, false, false, 5);

            commands_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5);
            main_box.pack_start(commands_box, true, true, 0);

            // Завантажуємо початкові команди
            if (initial_commands.length > 0) {
                for (int i = 0; i < initial_commands.length && i < MAX_COMMANDS; i++) {
                    var cmd = initial_commands[i];
                    // Перевірка на null та порожній рядок
                    if (cmd != null && cmd.tag != null && cmd.tag.length > 0 && cmd.command != null && cmd.command.length > 0) {
                        add_command_row_with_data(cmd.tag, cmd.command, true); // Завантажені команди заблоковані
                    }
                }
            }
            // Додаємо порожній рядок, якщо є місце
            if (commands_box.get_children().length() < MAX_COMMANDS) {
                add_empty_row();
            }

            var save_button = new Gtk.Button.with_label("Зберегти");
            save_button.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
            save_button.clicked.connect(() => {
                var commands = new GenericArray<CommandData?>();
                foreach (var child in commands_box.get_children()) {
                    var row = child as Gtk.Box;
                    if (row == null) continue;
                    var children = row.get_children();
                    if (children.length() < 3) continue; // Має бути tag, command, button

                    var tag_entry = children.nth_data(0) as Gtk.Entry;
                    var command_entry = children.nth_data(1) as Gtk.Entry;
                    var button = children.nth_data(2) as Gtk.Button;

                    // Перевірка на null та порожній рядок
                    if (tag_entry != null && command_entry != null && button != null &&
                        tag_entry.get_text() != null && tag_entry.get_text().length > 0 &&
                        command_entry.get_text() != null && command_entry.get_text().length > 0)
                    {
                        // Зберігаємо тільки ті рядки, які були підтверджені (кнопка "-")
                        if (button.get_label() == "-") {
                             commands.add(CommandData() {
                                tag = tag_entry.get_text(),
                                command = command_entry.get_text()
                            });
                        }
                    }
                }
                // Обрізаємо масив, якщо якимось чином додалося більше MAX_COMMANDS (про всяк випадок)
                if (commands.length > MAX_COMMANDS) {
                    commands.remove_range(MAX_COMMANDS, commands.length - MAX_COMMANDS);
                }

                applet.update_label_with_commands(main_entry.get_text(), commands);
                this.destroy();
            });
            main_box.pack_start(save_button, false, false, 0);

            add(main_box);
        }

        // Додає порожній рядок для введення нової команди
        private void add_empty_row() {
            if (commands_box.get_children().length() >= MAX_COMMANDS) {
                return; // Не додаємо, якщо досягнуто ліміту
            }
            // Додаємо рядок з порожніми полями та кнопкою "+"
            add_command_row_with_data("", "", false); // is_locked = false для нового рядка
        }

        // Додає рядок команди (новий або з даними)
        private void add_command_row_with_data(string tag, string command, bool is_locked) {
             // Перевірка на null та порожній рядок
             bool tag_is_empty = (tag == null || tag.length == 0);
             bool command_is_empty = (command == null || command.length == 0);

             // Перевірка перед додаванням, щоб не перевищити ліміт (стосується тільки додавання нового порожнього рядка)
             if (commands_box.get_children().length() >= MAX_COMMANDS && !is_locked && tag_is_empty && command_is_empty) {
                 return;
             }

            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);

            var tag_entry = new Gtk.Entry();
            tag_entry.set_placeholder_text("Тег ([tag])");
            tag_entry.set_width_chars(10);
            tag_entry.set_text(tag);
            row.pack_start(tag_entry, false, false, 0);

            var command_entry = new Gtk.Entry();
            command_entry.set_placeholder_text("Команда");
            command_entry.hexpand = true; // Дозволяємо розширюватись
            command_entry.set_text(command);
            row.pack_start(command_entry, true, true, 0);

            var button = new Gtk.Button();
            row.pack_start(button, false, false, 0);

            // Налаштовуємо рядок залежно від того, чи він заблокований (вже існує/завантажений) чи новий
            if (is_locked) {
                button.set_label("-");
                button.get_style_context().add_class(Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
                button.clicked.connect(() => remove_command_row(row));
                // Робимо поля нередагованими для існуючих/заблокованих команд
                tag_entry.set_editable(false);
                command_entry.set_editable(false);
            } else {
                button.set_label("+");
                button.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                // Зберігаємо посилання на елементи рядка в даних кнопки для обробника '+'
                button.set_data<Gtk.Entry>("tag_entry", tag_entry);
                button.set_data<Gtk.Entry>("command_entry", command_entry);
                button.set_data<Gtk.Box>("row", row);
                button.clicked.connect(on_add_button_clicked); // Підключаємо обробник для кнопки '+'
            }

            commands_box.pack_start(row, false, false, 0);
            commands_box.show_all(); // Оновлюємо відображення
        }

        // Оновлений обробник натискання кнопки "+"
        private void on_add_button_clicked(Gtk.Button button) {
            var tag_entry = button.get_data<Gtk.Entry>("tag_entry");
            var command_entry = button.get_data<Gtk.Entry>("command_entry");
            var row = button.get_data<Gtk.Box>("row");

            if (tag_entry == null || command_entry == null || row == null) {
                printerr("Error: Could not retrieve row data from button.\n");
                return;
            }

            string tag_text = tag_entry.get_text().strip(); // Обрізаємо пробіли
            string command_text = command_entry.get_text().strip(); // Обрізаємо пробіли

            // Скидаємо стилі помилок та підказку перед новою перевіркою
            tag_entry.get_style_context().remove_class("error");
            command_entry.get_style_context().remove_class("error");
            tag_entry.set_tooltip_text(null);

            bool is_tag_ok = false; // Початково вважаємо тег невалідним
            bool is_command_ok = false; // Початково вважаємо команду невалідною

            // --- Перевірка Тегу ---
            if (tag_text == null || tag_text.length == 0) {
                // Тег порожній - помилка
                tag_entry.get_style_context().add_class("error");
                is_tag_ok = false;
            } else {
                // Тег не порожній, перевіряємо формат та унікальність
                if (is_valid_tag(tag_text, tag_entry)) {
                    // Тег заповнений і валідний
                    is_tag_ok = true;
                } else {
                    // Тег заповнений, але НЕ валідний (формат/дублікат) - помилка
                    tag_entry.get_style_context().add_class("error");
                    tag_entry.set_tooltip_text("Тег має бути у форматі [tag] та унікальним");
                    is_tag_ok = false;
                }
            }

            // --- Перевірка Команди ---
            if (command_text == null || command_text.length == 0) {
                // Команда порожня - помилка
                command_entry.get_style_context().add_class("error");
                is_command_ok = false;
            } else {
                // Команда заповнена
                is_command_ok = true;
            }

            // --- Фіксація Рядка ---
            // Фіксуємо рядок, тільки якщо ОБИДВА поля пройшли перевірку (tag_ok І command_ok)
            if (is_tag_ok && is_command_ok) {
                // Змінюємо кнопку на "-"
                button.set_label("-");
                button.get_style_context().remove_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                button.get_style_context().add_class(Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);

                // Від'єднуємо старий обробник (+) і під'єднуємо новий (-)
                button.clicked.disconnect(on_add_button_clicked);
                button.clicked.connect(() => remove_command_row(row));

                // Блокуємо редагування полів
                tag_entry.set_editable(false);
                command_entry.set_editable(false);

                // Очищаємо дані, що зберігалися в кнопці (використовуємо nullable типи)
                button.set_data<Gtk.Entry?>("tag_entry", null);
                button.set_data<Gtk.Entry?>("command_entry", null);
                button.set_data<Gtk.Box?>("row", null);

                // Додаємо новий порожній рядок, якщо є місце
                if (commands_box.get_children().length() < MAX_COMMANDS) {
                    add_empty_row();
                }
            }
            // Якщо is_tag_ok або is_command_ok є false, рядок НЕ фіксується,
            // а відповідні поля вже підсвічені як помилкові завдяки логіці вище.
        }


        // Видаляє рядок команди
        private void remove_command_row(Gtk.Box row) {
            commands_box.remove(row);
            // Додаємо порожній рядок, якщо після видалення їх стало менше ліміту
            // і якщо порожнього рядка ще немає (щоб уникнути дублювання порожніх рядків)
            if (commands_box.get_children().length() < MAX_COMMANDS && !has_empty_row()) {
                add_empty_row();
            }
             commands_box.show_all(); // Перемальовуємо контейнер
        }

        // Перевіряє, чи існує вже порожній рядок (з кнопкою "+")
        private bool has_empty_row() {
            foreach (var child in commands_box.get_children()) {
                var row = child as Gtk.Box;
                 if (row == null) continue;
                var children = row.get_children();
                 if (children.length() < 3) continue; // Потрібен віджет кнопки
                var button = children.nth_data(2) as Gtk.Button;
                // Порожній рядок для введення має кнопку "+"
                if (button != null && button.get_label() == "+") {
                    return true;
                }
            }
            return false;
        }

        // Оновлена функція перевірки валідності тегу
        // Перевіряє формат [tag] та унікальність серед ВСІХ інших рядків
        private bool is_valid_tag(string tag, Gtk.Entry entry_being_checked) {
            // 1. Перевірка на null та формат
            if (tag == null) { // Додаткова перевірка на null перед викликом методів рядка
                return false;
            }
            if (!tag.has_prefix("[") || !tag.has_suffix("]")) {
                return false;
            }
            // Перевірка, що між дужками щось є
            if (tag.length <= 2) {
                 return false;
            }

            // 2. Перевірка на унікальність серед *інших* полів вводу тегів
            foreach (var child in commands_box.get_children()) {
                var row = child as Gtk.Box;
                 if (row == null) continue;
                var children = row.get_children();
                 // Потрібен принаймні віджет Gtk.Entry для тегу
                 if (children.length() < 1) continue;
                var existing_tag_entry = children.nth_data(0) as Gtk.Entry;

                // Пропускаємо поле, яке ми зараз перевіряємо, щоб не порівнювати його саме з собою
                if (existing_tag_entry == entry_being_checked) {
                    continue;
                }

                // Порівнюємо текст в іншому полі вводу тегу.
                if (existing_tag_entry != null) {
                    string existing_tag_text = existing_tag_entry.get_text();
                    // Якщо інше поле має такий самий текст тегу, то це дублікат
                    if (existing_tag_text != null && existing_tag_text == tag) {
                        return false; // Знайдено дублікат
                    }
                }
            }

            // Якщо перевірка формату пройдена і дублікатів не знайдено серед інших полів, тег валідний
            return true;
        }
    }
}