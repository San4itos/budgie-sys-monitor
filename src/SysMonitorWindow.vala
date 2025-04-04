using Gtk;

namespace SysMonitor {

    public class SysMonitorWindow : Gtk.Window {
        private SysMonitor.Applet applet;
        private Gtk.Entry main_entry;
        private Gtk.Box commands_box;
        private const int MAX_COMMANDS = 10;

        public SysMonitorWindow(SysMonitor.Applet parent, string plugin_dir, string initial_text, GenericArray<CommandData?> initial_commands) {
            this.applet = parent;
            set_title("Sys Monitor");
            set_default_size(400, 300);
            set_position(Gtk.WindowPosition.CENTER);

            var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            main_box.margin = 10;
            main_box.get_style_context().add_class("dialog-box");

            main_entry = new Gtk.Entry();
            main_entry.set_placeholder_text("Введіть текст...");
            main_entry.set_text(initial_text);
            main_box.pack_start(main_entry, false, false, 0);

            commands_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 5);
            main_box.pack_start(commands_box, true, true, 0);

            if (initial_commands.length > 0) {
                for (int i = 0; i < initial_commands.length && i < MAX_COMMANDS; i++) {
                    var cmd = initial_commands[i];
                    if (cmd != null) {
                        bool is_locked = (i < MAX_COMMANDS - 1 || initial_commands.length >= MAX_COMMANDS);
                        add_command_row_with_data(cmd.tag, cmd.command, is_locked);
                    }
                }
            }
            if (commands_box.get_children().length() < MAX_COMMANDS) {
                add_empty_row();
            }

            var save_button = new Gtk.Button.with_label("Зберегти");
            save_button.clicked.connect(() => {
                var commands = new GenericArray<CommandData?>();
                foreach (var child in commands_box.get_children()) {
                    var row = child as Gtk.Box;
                    var children = row.get_children();
                    var tag_entry = children.nth_data(0) as Gtk.Entry;
                    var command_entry = children.nth_data(1) as Gtk.Entry;
                    if (tag_entry.get_text().length > 0 && command_entry.get_text().length > 0) {
                        commands.add(CommandData() {
                            tag = tag_entry.get_text(),
                            command = command_entry.get_text()
                        });
                    }
                }
                applet.update_label_with_commands(main_entry.get_text(), commands);
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
            var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);

            var tag_entry = new Gtk.Entry();
            tag_entry.set_placeholder_text("Тег");
            tag_entry.set_width_chars(10);
            tag_entry.set_text(tag);
            row.pack_start(tag_entry, false, false, 0);

            var command_entry = new Gtk.Entry();
            command_entry.set_placeholder_text("Команда");
            command_entry.set_width_chars(20);
            command_entry.set_text(command);
            row.pack_start(command_entry, true, true, 0);

            var button = new Gtk.Button.with_label(is_locked ? "-" : "+");
            if (is_locked) {
                button.clicked.connect(() => remove_command_row(row));
            } else {
                button.clicked.connect(on_add_button_clicked);
                button.set_data<Gtk.Entry>("tag_entry", tag_entry);
                button.set_data<Gtk.Entry>("command_entry", command_entry);
                button.set_data<Gtk.Box>("row", row);
            }
            row.pack_start(button, false, false, 0);

            commands_box.pack_start(row, false, false, 0);
            commands_box.show_all();
        }

        private void on_add_button_clicked(Gtk.Button button) {
            var tag_entry = button.get_data<Gtk.Entry>("tag_entry");
            var command_entry = button.get_data<Gtk.Entry>("command_entry");
            var row = button.get_data<Gtk.Box>("row");

            string tag_text = tag_entry.get_text();
            string command_text = command_entry.get_text();

            if (tag_text.length > 0 && command_text.length > 0) {
                // Очищаємо стиль перед перевіркою
                tag_entry.get_style_context().remove_class("empty-entry");

                if (is_valid_tag(tag_text)) {
                    button.set_label("-");
                    button.clicked.disconnect(on_add_button_clicked);
                    button.clicked.connect(() => remove_command_row(row));
                    if (commands_box.get_children().length() < MAX_COMMANDS) {
                        add_empty_row();
                    }
                } else {
                    // Якщо тег невалідний, позначаємо його червоним
                    tag_entry.get_style_context().add_class("empty-entry");
                }
            }
        }

        private void remove_command_row(Gtk.Box row) {
            commands_box.remove(row);
            if (commands_box.get_children().length() < MAX_COMMANDS && !has_empty_row()) {
                add_empty_row();
            }
        }

        private bool has_empty_row() {
            foreach (var child in commands_box.get_children()) {
                var row = child as Gtk.Box;
                var children = row.get_children();
                var tag_entry = children.nth_data(0) as Gtk.Entry;
                var command_entry = children.nth_data(1) as Gtk.Entry;
                if (tag_entry.get_text().length == 0 && command_entry.get_text().length == 0) {
                    return true;
                }
            }
            return false;
        }

        private bool is_valid_tag(string tag) {
            if (!tag.has_prefix("[") || !tag.has_suffix("]")) {
                return false;
            }

            foreach (var child in commands_box.get_children()) {
                var row = child as Gtk.Box;
                var children = row.get_children();
                var existing_tag_entry = children.nth_data(0) as Gtk.Entry;
                if (existing_tag_entry.get_text() == tag && existing_tag_entry != null) {
                    return false;
                }
            }
            return true;
        }
    }
}