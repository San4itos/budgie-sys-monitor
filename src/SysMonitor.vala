// src/SysMonitor.vala
using Gtk;
using Budgie;
// Додаємо using для File API
using GLib;

namespace SysMonitor {

    // ... (Решта коду до load_config_from_json) ...
     public class Plugin : Budgie.Plugin, Peas.ExtensionBase {
        public Budgie.Applet get_panel_widget(string uuid) {
            return new Applet(uuid);
        }
    }

     public class Applet : Budgie.Applet {
        private Gtk.EventBox widget;
        private Gtk.Label label;
        private string plugin_dir;
        private string config_dir;
        private double current_interval = 1.0;
        private uint timer_id = 0;

        public Applet(string uuid) {
            plugin_dir = get_plugin_dir();
            config_dir = get_config_dir();

            var config = load_config_from_json();
            this.current_interval = config.interval;

            widget = new Gtk.EventBox();
            label = new Gtk.Label(config.text);
            widget.add(label);

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

            widget.button_press_event.connect(on_button_press);
            start_or_restart_timer();

            this.add(widget);
            this.show_all();
        }

        private bool on_button_press(Gtk.Widget widget, Gdk.EventButton event) {
            if (event.button != 1) {
                return Gdk.EVENT_PROPAGATE;
            }

            var config = load_config_from_json();
            var commands = load_commands_from_json();

            var dialog = new SysMonitorWindow(this, plugin_dir, config.text, commands, config.interval);
            dialog.show_all();

            return Gdk.EVENT_STOP;
        }

        public void update_label_with_commands(string new_text, GenericArray<CommandData?> commands, double interval) {
            label.set_text(new_text);
            this.current_interval = interval;
            save_text_to_json(new_text, commands, interval);
            start_or_restart_timer();
            stdout.printf("Settings saved. New interval: %.1f seconds\n", interval);
        }

        private string get_plugin_dir() {
             string[] possible_paths = {
                GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".local", "share", "budgie-desktop", "plugins", "sysmonitor"),
                "/usr/share/budgie-desktop/plugins/sysmonitor",
                "/usr/local/share/budgie-desktop/plugins/sysmonitor",
                GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "budgie-desktop", "plugins", "sysmonitor")
            };

            foreach (string path in possible_paths) {
                string css_file = GLib.Path.build_filename(path, "style.css");
                if (FileUtils.test(css_file, FileTest.EXISTS)) {
                    return path;
                }
            }
            // Якщо нічого не знайдено, повертаємо шлях за замовчуванням у home
             var default_path = GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".local", "share", "budgie-desktop", "plugins", "sysmonitor");
            // Переконаємось, що директорія існує або створюємо її
            var file = File.new_for_path (default_path);
            try {
                if (!file.query_exists ()) {
                   file.make_directory_with_parents ();
                   stdout.printf("Created plugin directory: %s\n", default_path);
                }
            } catch (Error e) {
                stderr.printf("Warning: Could not create plugin directory %s: %s\n", default_path, e.message);
            }
            return default_path;
        }

        private string get_config_dir() {
            string primary_path = plugin_dir; // Використовуємо директорію плагіна як основну
            string config_path = GLib.Path.build_filename(primary_path, "config.json");

             // Перевіряємо доступ на запис у директорію плагіна
             var primary_dir_file = File.new_for_path(primary_path);
            try {
                 // Спробуємо створити тестовий файл
                var test_file = primary_dir_file.get_child("write_test.tmp");
                 OutputStream stream = test_file.replace(null, false, FileCreateFlags.REPLACE_DESTINATION);
                stream.close(); // Закриваємо одразу
                test_file.delete(); // Видаляємо тестовий файл
                stdout.printf("Using config directory: %s\n", primary_path);
                return primary_path; // Доступ є, використовуємо директорію плагіна
            } catch (Error e) {
                 // Якщо запис не вдався, використовуємо директорію конфігурації користувача
                var user_config_path = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(), "budgie-sys-monitor");
                 stdout.printf("Write access denied to %s, using config directory: %s\n", primary_path, user_config_path);
                 // Переконуємось, що ця директорія існує
                 var user_config_file = File.new_for_path(user_config_path);
                try {
                    if (!user_config_file.query_exists()) {
                        user_config_file.make_directory_with_parents();
                    }
                } catch (Error dir_err) {
                     stderr.printf("Warning: Could not create user config directory %s: %s\n", user_config_path, dir_err.message);
                }
                return user_config_path;
            }
        }

        private struct AppConfig {
            public string text;
            public double interval;
        }

        // <<< ЗМІНЕНО: Виправлена логіка перевірки типу для JsonNode >>>
        private AppConfig load_config_from_json() {
            var config = AppConfig() { text = "...", interval = 1.0 };
            var json_path = GLib.Path.build_filename(config_dir, "config.json");

            if (!FileUtils.test(json_path, FileTest.EXISTS)) {
                save_text_to_json(config.text, new GenericArray<CommandData?>(), config.interval);
                return config;
            }

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

                if (root.has_member("text")) {
                    config.text = root.get_string_member("text");
                } else {
                    stderr.printf("Warning: 'text' member missing in config.json, using default.\n");
                }

                if (root.has_member("refresh_interval")) {
                    // Спочатку отримуємо JsonNode
                    var interval_node = root.get_member("refresh_interval");
                    // Перевіряємо, що це вузол типу VALUE і його значення є double
                    if (interval_node != null && interval_node.get_node_type() == Json.NodeType.VALUE && interval_node.get_value_type() == typeof(double)) {
                        // Тільки тепер безпечно отримуємо double
                        config.interval = root.get_double_member("refresh_interval");
                        if (config.interval < 0.1) config.interval = 0.1;
                        if (config.interval > 10.0) config.interval = 10.0;
                     } else {
                        stderr.printf("Warning: 'refresh_interval' is not a number or missing in config.json, using default.\n");
                     }
                } else {
                    stderr.printf("Warning: 'refresh_interval' member missing in config.json, using default.\n");
                }

            } catch (Error e) {
                stderr.printf("Error loading config JSON: %s\n", e.message);
            }
            return config;
        }


        private GenericArray<CommandData?> load_commands_from_json() {
            // ... (код без змін) ...
            var json_path = GLib.Path.build_filename(config_dir, "config.json");
            var commands = new GenericArray<CommandData?>();

            if (!FileUtils.test(json_path, FileTest.EXISTS)) {
                return commands;
            }

            try {
                string contents;
                FileUtils.get_contents(json_path, out contents);
                Json.Parser parser = new Json.Parser();
                parser.load_from_data(contents);
                var root_node = parser.get_root();
                 if (root_node == null || root_node.get_node_type() != Json.NodeType.OBJECT) {
                    return commands;
                }
                var root = root_node.get_object();

                if (root.has_member("commands")) {
                     var commands_array = root.get_array_member("commands");
                     if (commands_array != null) {
                        for (int i = 0; i < commands_array.get_length(); i++) {
                            var cmd_obj = commands_array.get_object_element(i);
                            if (cmd_obj != null && cmd_obj.has_member("tag") && cmd_obj.has_member("command")) {
                                commands.add(CommandData() {
                                    tag = cmd_obj.get_string_member("tag"),
                                    command = cmd_obj.get_string_member("command")
                                });
                            }
                        }
                     }
                }
            } catch (Error e) {
                stderr.printf("Error loading commands from JSON: %s\n", e.message);
            }
            return commands;
        }


        // <<< ЗМІНЕНО: Використання GLib.File для створення директорії >>>
        private void save_text_to_json(string text, GenericArray<CommandData?> commands, double interval) {
            var json_path = GLib.Path.build_filename(config_dir, "config.json");
            string json_data = "";

            try {
                 // Переконуємось, що директорія існує
                var dir_path = Path.get_dirname(json_path);
                var dir_file = File.new_for_path(dir_path);
                if (!dir_file.query_exists(null)) {
                    // Використовуємо метод об'єкта File
                    dir_file.make_directory_with_parents(null);
                     stdout.printf("Created config directory: %s\n", dir_path);
                }


                var builder = new Json.Builder();
                builder.begin_object();

                builder.set_member_name("text");
                builder.add_string_value(text);

                builder.set_member_name("refresh_interval");
                builder.add_double_value(interval);

                builder.set_member_name("commands");
                builder.begin_array();
                for (int i = 0; i < commands.length; i++) {
                    var cmd = commands[i];
                    if (cmd != null) {
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

                var generator = new Json.Generator();
                generator.set_root(builder.get_root());
                generator.set_pretty(true);
                json_data = generator.to_data(null);

                FileUtils.set_contents(json_path, json_data);
            } catch (Error e) {
                stderr.printf("Error saving JSON: %s\n", e.message);
            }
        }

        // --- Методи таймера і решта класу ---
        private void start_or_restart_timer() {
            if (timer_id > 0) {
                Source.remove (timer_id);
                timer_id = 0;
            }
            uint interval_ms = (uint)(this.current_interval * 1000.0);
             if (interval_ms < 100) interval_ms = 100;
             if (interval_ms > 10000) interval_ms = 10000;

            stdout.printf("Starting timer with interval: %u ms (%.1f s)\n", interval_ms, this.current_interval);
            timer_id = Timeout.add (interval_ms, () => {
                update_label_content();
                return Source.CONTINUE;
            });
        }

        private void update_label_content() {
            // Поки що тестове оновлення
            label.set_text(label.get_text() + ".");
        }

        public override void destroy () {
            if (timer_id > 0) {
                Source.remove (timer_id);
                timer_id = 0;
            }
            base.destroy ();
        }

    } // Кінець класу Applet

     public struct CommandData {
        public string tag;
        public string command;
    }

} // Кінець namespace SysMonitor

[ModuleInit]
public void peas_register_types(TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SysMonitor.Plugin));
}