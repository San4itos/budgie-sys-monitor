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
        private string plugin_dir; // Єдина директорія для всього аплету

        public Applet(string uuid) {
            // Визначаємо шлях до директорії встановлення аплету
            plugin_dir = get_plugin_dir();
            
            widget = new Gtk.EventBox();
            label = new Gtk.Label(load_text_from_json());
            widget.add(label);

            // Завантажуємо CSS, якщо він є
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

            var dialog = new SysMonitorWindow(this, plugin_dir);
            dialog.show_all();

            return Gdk.EVENT_STOP;
        }

        // Метод для оновлення тексту
        public void update_label(string new_text) {
            label.set_text(new_text);
            save_text_to_json(new_text);
        }

        // Отримуємо шлях до директорії плагіну
        private string get_plugin_dir() {
            // Спочатку шукаємо серед відомих шляхів інсталяції Budgie плагінів
            string[] possible_paths = {
                // Визначаємо поточну директорію програми
                GLib.Environment.get_current_dir(),
                // Типові шляхи інсталяції Budgie плагінів
                "/usr/lib/budgie-desktop/plugins/budgie-sys-monitor",
                "/usr/local/lib/budgie-desktop/plugins/budgie-sys-monitor",
                GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "budgie-desktop/plugins/budgie-sys-monitor")
            };
            
            foreach (string path in possible_paths) {
                // Перевіряємо наявність індикатора файлу, наприклад libsysmonitor.so 
                string indicator_file = GLib.Path.build_filename(path, "libsysmonitor.so");
                if (FileUtils.test(indicator_file, FileTest.EXISTS)) {
                    return path;
                }
                
                // Також перевіряємо наявність style.css як альтернативного індикатора
                string css_file = GLib.Path.build_filename(path, "style.css");
                if (FileUtils.test(css_file, FileTest.EXISTS)) {
                    return path;
                }
            }
            
            // Якщо нічого не знайдено, повертаємо перший варіант як запасний
            return possible_paths[0];
        }

        // Зчитування тексту з JSON
        private string load_text_from_json() {
            var json_path = GLib.Path.build_filename(plugin_dir, "config.json");
            
            if (!FileUtils.test(json_path, FileTest.EXISTS)) {
                // Перевіряємо чи можемо записувати в директорію
                try {
                    var test_file = GLib.Path.build_filename(plugin_dir, "write_test");
                    FileUtils.set_contents(test_file, "test");
                    FileUtils.unlink(test_file);
                    
                    // Якщо дійшли сюди, запис можливий - створюємо дефолтний конфіг
                    save_text_to_json("Hello, World!");
                    return "Hello, World!";
                } catch (Error e) {
                    // Запис неможливий - використовуємо дефолтне значення без збереження
                    stderr.printf("Cannot write to plugin directory: %s\n", e.message);
                    return "Hello, World!";
                }
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

        // Збереження тексту в JSON
        private void save_text_to_json(string text) {
            var json_path = GLib.Path.build_filename(plugin_dir, "config.json");
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
                stderr.printf("Error saving JSON to plugin dir: %s\n", e.message);
                
                // Якщо не можемо записати в директорію аплету, використовуємо XDG_CONFIG_HOME
                try {
                    string fallback_dir = GLib.Path.build_filename(
                        GLib.Environment.get_user_config_dir(),
                        "budgie-sys-monitor"
                    );
                    
                    var dir = File.new_for_path(fallback_dir);
                    if (!dir.query_exists()) {
                        dir.make_directory_with_parents();
                    }
                    
                    var fallback_path = GLib.Path.build_filename(fallback_dir, "config.json");
                    FileUtils.set_contents(fallback_path, json_data);
                    stderr.printf("Config saved to fallback location: %s\n", fallback_path);
                } catch (Error e2) {
                    stderr.printf("Error saving to fallback location: %s\n", e2.message);
                }
            }
        }
    }
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SysMonitor.Plugin));
}