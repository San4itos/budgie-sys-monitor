// src/SysMonitor.vala
using Gtk;
using Budgie;
using GLib;

namespace SysMonitor {

    public struct AppConfig {
        public string text;
        public double interval;
    }

    public struct CommandData {
        public string tag;
        public string command;
    }

    public class Plugin : Budgie.Plugin, Peas.ExtensionBase {
        public Budgie.Applet get_panel_widget(string uuid) {
            return new Applet(uuid);
        }
    }

    public class Applet : Budgie.Applet {
        // ... (поля класу без змін) ...
        private Gtk.EventBox widget;
        private Gtk.Label label;
        private string plugin_dir;
        private string config_dir;
        private double current_interval = 1.0;
        private uint timer_id = 0;
        private string template_text = "...";
        private GenericArray<CommandData?> current_commands = new GenericArray<CommandData?>();
        private bool is_destroyed = false;


        // ... (конструктор, on_button_press без змін) ...
        public Applet(string uuid) {
            plugin_dir = get_plugin_dir();
            config_dir = get_config_dir();
            load_full_config();

            widget = new Gtk.EventBox();
            label = new Gtk.Label("...");
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
            // Передаємо поточні збережені дані
            var dialog = new SysMonitorWindow(this, plugin_dir, this.template_text, this.current_commands, this.current_interval);
            dialog.show_all();
            return Gdk.EVENT_STOP;
        }

        // <<< ЗМІНЕНО: Перейменовано та виправлено логіку оновлення команд >>>
        // Цей метод тепер приймає повний стан з UI і оновлює внутрішній стан Applet
        public void update_configuration(string new_text, GenericArray<CommandData?> commands_from_ui, double new_interval) {
            // 1. Оновлюємо текст та інтервал
            this.template_text = new_text;
            this.current_interval = new_interval;

            // 2. Оновлюємо список команд:
            // Повністю замінюємо внутрішній список `current_commands` на той,
            // що прийшов з вікна налаштувань (`commands_from_ui`).
            // Вікно налаштувань відповідає за те, щоб зібрати АКТУАЛЬНИЙ список
            // команд, які користувач хоче зберегти (тобто ті, що підтверджені кнопкою "-").
            this.current_commands = commands_from_ui; // Просто присвоюємо новий масив

            // 3. Зберігаємо оновлену конфігурацію в файл
            save_config_to_json();

            // 4. Перезапускаємо таймер і одразу оновлюємо мітку
            start_or_restart_timer(true); // true - оновити негайно

            stdout.printf("Configuration updated. Interval: %.1f seconds. Commands: %d\n", this.current_interval, this.current_commands.length);
        }

        // ... (load_full_config, save_config_to_json, get_plugin_dir, get_config_dir без змін) ...
         private void load_full_config() {
            var config = AppConfig() { text = "...", interval = 1.0 };
            var commands = new GenericArray<CommandData?>();
            var json_path = GLib.Path.build_filename(config_dir, "config.json");

            if (!FileUtils.test(json_path, FileTest.EXISTS)) {
                this.template_text = config.text;
                this.current_interval = config.interval;
                this.current_commands = new GenericArray<CommandData?>();
                save_config_to_json();
                return;
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
                } else { stderr.printf("Warning: 'text' member missing, using default.\n"); }

                if (root.has_member("refresh_interval")) {
                    var interval_node = root.get_member("refresh_interval");
                    if (interval_node != null && interval_node.get_node_type() == Json.NodeType.VALUE && interval_node.get_value_type() == typeof(double)) {
                        config.interval = root.get_double_member("refresh_interval");
                        if (config.interval < 0.1) config.interval = 0.1;
                        if (config.interval > 10.0) config.interval = 10.0;
                     } else { stderr.printf("Warning: 'refresh_interval' invalid or missing, using default.\n"); }
                } else { stderr.printf("Warning: 'refresh_interval' member missing, using default.\n"); }
                 if (root.has_member("commands")) {
                     var commands_array = root.get_array_member("commands");
                     if (commands_array != null) {
                        for (int i = 0; i < commands_array.get_length(); i++) {
                            var cmd_obj = commands_array.get_object_element(i);
                            if (cmd_obj != null && cmd_obj.has_member("tag") && cmd_obj.has_member("command")) {
                                string tag = cmd_obj.get_string_member("tag");
                                string command = cmd_obj.get_string_member("command");
                                if(tag.length > 0 && command.length > 0) {
                                    commands.add(CommandData() { tag = tag, command = command });
                                }
                            }
                        }
                     }
                }
            } catch (Error e) {
                stderr.printf("Error loading full config JSON: %s\n Using defaults.\n", e.message);
            }
            this.template_text = config.text;
            this.current_interval = config.interval;
            this.current_commands = commands;
        }
        private void save_config_to_json() {
            var json_path = GLib.Path.build_filename(config_dir, "config.json");
            try {
                var dir_path = Path.get_dirname(json_path);
                var dir_file = File.new_for_path(dir_path);
                if (!dir_file.query_exists(null)) {
                    dir_file.make_directory_with_parents(null);
                    stdout.printf("Created config directory: %s\n", dir_path);
                }
                var builder = new Json.Builder();
                builder.begin_object();
                builder.set_member_name("text");
                builder.add_string_value(this.template_text);
                builder.set_member_name("refresh_interval");
                builder.add_double_value(this.current_interval);
                builder.set_member_name("commands");
                builder.begin_array();
                foreach (var cmd in this.current_commands) {
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
                string json_data = generator.to_data(null);
                FileUtils.set_contents(json_path, json_data);
            } catch (Error e) {
                stderr.printf("Error saving config JSON: %s\n", e.message);
            }
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
             var default_path = GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".local", "share", "budgie-desktop", "plugins", "sysmonitor");
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
             string primary_path = plugin_dir;
            string config_path = GLib.Path.build_filename(primary_path, "config.json");
             var primary_dir_file = File.new_for_path(primary_path);
            try {
                var test_file = primary_dir_file.get_child("write_test.tmp");
                 OutputStream stream = test_file.replace(null, false, FileCreateFlags.REPLACE_DESTINATION);
                stream.close();
                test_file.delete();
                stdout.printf("Using config directory: %s\n", primary_path);
                return primary_path;
            } catch (Error e) {
                var user_config_path = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(), "budgie-sys-monitor");
                 stdout.printf("Write access denied to %s, using config directory: %s\n", primary_path, user_config_path);
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

        // ... (start_or_restart_timer, update_label_content, destroy без змін) ...
         private void start_or_restart_timer(bool immediate_update = false) {
             if (timer_id > 0) {
                Source.remove (timer_id);
                timer_id = 0;
            }
            uint interval_ms = (uint)(this.current_interval * 1000.0);
            if (interval_ms < 100) interval_ms = 100;
            if (interval_ms > 10000) interval_ms = 10000;
            stdout.printf("Starting timer with interval: %u ms (%.1f s)\n", interval_ms, this.current_interval);
            if (immediate_update) {
                update_label_content();
            }
            timer_id = Timeout.add (interval_ms, () => {
                update_label_content();
                return Source.CONTINUE;
            });
        }
        private void update_label_content() {
            stdout.printf("--- update_label_content called ---\n"); // Початок виконання
            string processed_text = this.template_text;
            stdout.printf("  Template: '%s'\n", processed_text);

            if (this.current_commands.length == 0) {
                 stdout.printf("  No commands configured.\n");
            }

            foreach (var cmd_data in this.current_commands) {
                 if (cmd_data == null || cmd_data.tag == null || cmd_data.command == null
                    || cmd_data.tag.length == 0 || cmd_data.command.length == 0) {
                    stdout.printf("  Skipping invalid command data.\n");
                    continue;
                }

                string tag = cmd_data.tag;
                string command_str = cmd_data.command;
                string replacement_text = "";

                stdout.printf("  Processing Tag: '%s', Command: '%s'\n", tag, command_str);

                // Перевіряємо, чи текст ВЖЕ містить тег ПЕРЕД заміною
                if (!processed_text.contains(tag)) {
                    stdout.printf("  Tag '%s' not found in current processed text. Skipping command execution.\n", tag);
                    continue;
                }

                try {
                    string[] shell_argv = {"/bin/sh", "-c", command_str};

                    string standard_output;
                    string standard_error;
                    int exit_status;

                    stdout.printf("    Spawning: /bin/sh -c \"%s\"\n", command_str);
                    GLib.Process.spawn_sync( null, shell_argv, null, 0, null,
                        out standard_output, out standard_error, out exit_status );

                    // Виводимо результат незалежно від успіху
                    stdout.printf("    Exit Status: %d\n", exit_status);
                    stdout.printf("    Raw Stdout: '%s'\n", standard_output ?? "<null>"); // Використовуємо ?? для обробки null
                    stdout.printf("    Raw Stderr: '%s'\n", standard_error ?? "<null>"); // Використовуємо ?? для обробки null

                    if (exit_status != 0) {
                        replacement_text = "[ERR:%d]".printf(exit_status);
                        if (standard_error != null && standard_error.length > 0) {
                             stderr.printf("    Shell/Cmd '%s' err (exit %d): %s\n", command_str, exit_status, standard_error.strip());
                        } else {
                             stderr.printf("    Shell/Cmd '%s' failed with exit %d (no stderr)\n", command_str, exit_status);
                        }
                    } else if (standard_output != null) {
                        replacement_text = standard_output.strip();
                         stdout.printf("    Using stripped stdout for replacement: '%s'\n", replacement_text);
                    } else {
                        replacement_text = ""; // Успіх, але виводу немає
                         stdout.printf("    Command succeeded but stdout was null. Replacing with empty string.\n");
                    }

                } catch (SpawnError e) {
                     stderr.printf("    Failed to spawn shell for cmd '%s': %s\n", command_str, e.message);
                     replacement_text = "[SPAWN ERR]";
                } catch (Error e) {
                     stderr.printf("    Error processing cmd '%s': %s\n", command_str, e.message);
                     replacement_text = "[PROC ERR]";
                }

                stdout.printf("    Replacing '%s' with '%s'\n", tag, replacement_text);
                processed_text = processed_text.replace(tag, replacement_text);
                stdout.printf("    Text after replace: '%s'\n", processed_text);

            } // Кінець foreach

            stdout.printf("  Final text before Idle.add: '%s'\n", processed_text);

            Idle.add(() => {
                 stdout.printf("    Idle.add: Setting label text (destroyed=%s)\n", is_destroyed.to_string());
                if (!is_destroyed) {
                    label.set_text(processed_text);
                }
                return Source.REMOVE;
            });
             stdout.printf("--- update_label_content finished ---\n"); // Кінець виконання
        }

         public override void destroy () {
            this.is_destroyed = true;
            if (timer_id > 0) {
                Source.remove (timer_id);
                timer_id = 0;
            }
            base.destroy ();
        }

    } // Кінець класу Applet

} // Кінець namespace SysMonitor

// Ініціалізація Peas (без змін)
[ModuleInit]
public void peas_register_types(TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SysMonitor.Plugin));
}