using Gtk;
using Budgie;

namespace SysMonitor {

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

        public Applet(string uuid) {
            plugin_dir = get_plugin_dir();
            config_dir = get_config_dir();

            widget = new Gtk.EventBox();
            label = new Gtk.Label(load_text_from_json());
            widget.add(label);

            // Завантажуємо CSS один раз тут
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

            this.add(widget);
            this.show_all();
        }

        private bool on_button_press(Gtk.Widget widget, Gdk.EventButton event) {
            if (event.button != 1) {
                return Gdk.EVENT_PROPAGATE;
            }

            var dialog = new SysMonitorWindow(this, plugin_dir, load_text_from_json()); // Передаємо поточний текст
            dialog.show_all();

            return Gdk.EVENT_STOP;
        }

        public void update_label(string new_text) {
            label.set_text(new_text);
            save_text_to_json(new_text);
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
            return possible_paths[0];
        }

        private string get_config_dir() {
            string primary_path = plugin_dir;
            string config_path = GLib.Path.build_filename(primary_path, "config.json");
            
            try {
                string test_file = GLib.Path.build_filename(primary_path, "write_test");
                FileUtils.set_contents(test_file, "test");
                FileUtils.unlink(test_file);
                return primary_path;
            } catch (Error e) {
                return GLib.Path.build_filename(GLib.Environment.get_user_config_dir(), "budgie-sys-monitor");
            }
        }

        private string load_text_from_json() {
            var json_path = GLib.Path.build_filename(config_dir, "config.json");
            if (!FileUtils.test(json_path, FileTest.EXISTS)) {
                save_text_to_json("Hello, World!");
                return "Hello, World!";
            }

            try {
                string contents;
                FileUtils.get_contents(json_path, out contents);
                Json.Parser parser = new Json.Parser();
                parser.load_from_data(contents);
                var root = parser.get_root().get_object();
                return root.get_string_member("text");
            } catch (Error e) {
                stderr.printf("Error loading JSON: %s\n", e.message);
                return "Hello, World!";
            }
        }

        private void save_text_to_json(string text) {
            var json_path = GLib.Path.build_filename(config_dir, "config.json");
            string json_data = "";

            try {
                var builder = new Json.Builder();
                builder.begin_object();
                builder.set_member_name("text");
                builder.add_string_value(text);
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
    }
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SysMonitor.Plugin));
}