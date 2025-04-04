// src/SysMonitorWindow.vala
using Gtk;

namespace SysMonitor {
    public class SysMonitorWindow : Gtk.Window {
        // ... (поля класу без змін) ...
        private SysMonitor.Applet applet;
        private Gtk.Entry main_entry;
        private Gtk.Box commands_box;
        private Gtk.SpinButton refresh_interval_spin;
        private const int MAX_COMMANDS = 10;


        // ... (конструктор, add_empty_row, add_command_row_with_data, on_entry_activate, on_add_button_clicked, etc. без змін) ...
         public SysMonitorWindow(SysMonitor.Applet parent, string plugin_dir, string initial_text, GenericArray<CommandData?> initial_commands, double initial_interval = 1.0) {
            Object(
                window_position: Gtk.WindowPosition.CENTER,
                default_width: 400,
                default_height: 300,
                title: "Sys Monitor Settings"
            );
            this.applet = parent;

            var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            main_box.margin = 10;
            main_box.get_style_context().add_class("dialog-box");
            var refresh_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            var refresh_label = new Gtk.Label("Час оновлення (сек.):");
            refresh_box.pack_start(refresh_label, false, false, 0);
            var refresh_adjustment = new Gtk.Adjustment (initial_interval, 0.1, 10.0, 0.1, 1.0, 0.0);
            refresh_interval_spin = new Gtk.SpinButton (refresh_adjustment, 0.1, 1);
            refresh_interval_spin.set_numeric(true);
            refresh_interval_spin.set_tooltip_text("Інтервал оновлення даних в секундах (0.1 - 10.0)");
            refresh_box.pack_start(refresh_interval_spin, false, false, 0);
            main_box.pack_start(refresh_box, false, false, 0);

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

            if (initial_commands.length > 0) {
                for (int i = 0; i < initial_commands.length && i < MAX_COMMANDS; i++) {
                    var cmd = initial_commands[i];
                    if (cmd != null && cmd.tag != null && cmd.tag.length > 0 && cmd.command != null && cmd.command.length > 0) {
                        add_command_row_with_data(cmd.tag, cmd.command, true);
                    }
                }
            }
            if (commands_box.get_children().length() < MAX_COMMANDS) {
                add_empty_row();
            }

            var save_button = new Gtk.Button.with_label("Зберегти");
            save_button.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
            // <<< ЗМІНЕНО: Обробник кнопки Зберегти >>>
            save_button.clicked.connect(() => {
                // 1. Збираємо команди з UI (тільки підтверджені)
                var commands_from_ui = new GenericArray<CommandData?>();
                foreach (var child in commands_box.get_children()) {
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
                        // Додаємо до списку тільки ті команди, що мають кнопку "-"
                        if (button.get_label() == "-") {
                             commands_from_ui.add(CommandData() {
                                tag = tag_entry.get_text(),
                                command = command_entry.get_text()
                            });
                        }
                    }
                }
                // Обрізаємо масив, якщо якимось чином додалося більше MAX_COMMANDS
                if (commands_from_ui.length > MAX_COMMANDS) {
                    commands_from_ui.remove_range(MAX_COMMANDS, commands_from_ui.length - MAX_COMMANDS);
                }

                // 2. Отримуємо текст та інтервал з UI
                string current_text = main_entry.get_text();
                double current_interval = refresh_interval_spin.get_value();

                // 3. Викликаємо оновлений метод Applet, передаючи всі дані з UI
                applet.update_configuration(current_text, commands_from_ui, current_interval);

                // 4. Закриваємо вікно
                this.destroy();
            });
            main_box.pack_start(save_button, false, false, 0);

            add(main_box);
        }
        private void add_empty_row() {
            if (commands_box.get_children().length() >= MAX_COMMANDS) {
                return;
            }
            add_command_row_with_data("", "", false);
        }
        private void add_command_row_with_data(string tag, string command, bool is_locked) {
             bool tag_is_empty = (tag == null || tag.length == 0);
             bool command_is_empty = (command == null || command.length == 0);

             if (commands_box.get_children().length() >= MAX_COMMANDS && !is_locked && tag_is_empty && command_is_empty) {
                 return;
             }

            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);

            var tag_entry = new Gtk.Entry();
            tag_entry.set_placeholder_text("Тег ([tag])");
            tag_entry.set_width_chars(7);
            row.pack_start(tag_entry, false, false, 0);
            tag_entry.set_text(tag);

            var command_entry = new Gtk.Entry();
            command_entry.set_placeholder_text("Команда");
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

                button.set_data<Gtk.Entry>("tag_entry", tag_entry);
                button.set_data<Gtk.Entry>("command_entry", command_entry);
                button.set_data<Gtk.Box>("row", row);
                button.clicked.connect(on_add_button_clicked);

                tag_entry.set_data<Gtk.Button>("add_button", button);
                command_entry.set_data<Gtk.Button>("add_button", button);

                tag_entry.activate.connect(on_entry_activate);
                command_entry.activate.connect(on_entry_activate);
            }

            commands_box.pack_start(row, false, false, 0);
            commands_box.show_all();
        }
        private void on_entry_activate(Gtk.Entry entry) {
            var button = entry.get_data<Gtk.Button?>("add_button");
            if (button != null && button.get_label() == "+") {
                button.clicked ();
            }
        }
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

            tag_entry.get_style_context().remove_class("error");
            command_entry.get_style_context().remove_class("error");
            tag_entry.set_tooltip_text(null);

            bool is_tag_ok = false;
            bool is_command_ok = false;

            if (tag_text == null || tag_text.length == 0) {
                is_tag_ok = false;
            } else {
                is_tag_ok = is_valid_tag(tag_text, tag_entry);
            }

            if (command_text == null || command_text.length == 0) {
                is_command_ok = false;
            } else {
                is_command_ok = true;
            }

            if (!is_tag_ok || !is_command_ok) {
                var captured_tag_entry = tag_entry;
                var captured_command_entry = command_entry;
                bool apply_tag_error = !is_tag_ok;
                bool apply_command_error = !is_command_ok;
                string captured_tag_text_for_tooltip = tag_text;

                GLib.Idle.add (() => {
                    if (captured_tag_entry.get_window() != null) {
                        if (apply_tag_error) {
                            captured_tag_entry.get_style_context().add_class("error");
                            if (captured_tag_text_for_tooltip != null && captured_tag_text_for_tooltip.length > 0) {
                                captured_tag_entry.set_tooltip_text("Тег має бути у форматі [tag] та унікальним");
                            }
                        }
                    }
                    if (captured_command_entry.get_window() != null) {
                         if (apply_command_error) {
                            captured_command_entry.get_style_context().add_class("error");
                         }
                    }
                    return GLib.Source.REMOVE;
                });
            }

            if (is_tag_ok && is_command_ok) {
                button.set_label("-");
                button.get_style_context().remove_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
                button.get_style_context().add_class(Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);

                button.clicked.disconnect(on_add_button_clicked);
                button.clicked.connect(() => remove_command_row(row));

                tag_entry.set_editable(false);
                command_entry.set_editable(false);

                button.set_data<Gtk.Entry?>("tag_entry", null);
                button.set_data<Gtk.Entry?>("command_entry", null);
                button.set_data<Gtk.Box?>("row", null);

                tag_entry.set_data<Gtk.Button?>("add_button", null);
                command_entry.set_data<Gtk.Button?>("add_button", null);

                if (commands_box.get_children().length() < MAX_COMMANDS) {
                    add_empty_row();
                }
            }
        }
        private void remove_command_row(Gtk.Box row) {
            commands_box.remove(row);
            if (commands_box.get_children().length() < MAX_COMMANDS && !has_empty_row()) {
                add_empty_row();
            }
             commands_box.show_all();
        }
        private bool has_empty_row() {
            foreach (var child in commands_box.get_children()) {
                var row = child as Gtk.Box;
                 if (row == null) continue;
                var children = row.get_children();
                 if (children.length() < 3) continue;
                var button = children.nth_data(2) as Gtk.Button;
                if (button != null && button.get_label() == "+") {
                    return true;
                }
            }
            return false;
        }
        private bool is_valid_tag(string tag, Gtk.Entry entry_being_checked) {
            if (tag == null) {
                return false;
            }
            if (!tag.has_prefix("[") || !tag.has_suffix("]")) {
                return false;
            }
            if (tag.length <= 2) {
                 return false;
            }

            foreach (var child in commands_box.get_children()) {
                var row = child as Gtk.Box;
                 if (row == null) continue;
                var children = row.get_children();
                 if (children.length() < 1) continue;
                var existing_tag_entry = children.nth_data(0) as Gtk.Entry;

                if (existing_tag_entry == entry_being_checked) {
                    continue;
                }

                if (existing_tag_entry != null) {
                    string existing_tag_text = existing_tag_entry.get_text();
                    if (existing_tag_text != null && existing_tag_text == tag) {
                        return false;
                    }
                }
            }
            return true;
        }

    } // Кінець класу SysMonitorWindow
} // Кінець namespace SysMonitor