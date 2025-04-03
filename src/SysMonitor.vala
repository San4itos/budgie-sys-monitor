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
        private string install_dir; // Зберігаємо шлях до директорії встановлення

        public Applet(string uuid) {
            // Отримуємо шлях до директорії плагіну
            install_dir = get_install_dir();
            widget = new Gtk.EventBox();
            label = new Gtk.Label(load_text_from_json());
            widget.add(label);

            widget.button_press_event.connect(on_button_press);

            this.add(widget);
            this.show_all();
        }

        private bool on_button_press(Gtk.Widget widget, Gdk.EventButton event) {
            if (event.button != 1) {
                return Gdk.EVENT_PROPAGATE;
            }

            var dialog = new SysMonitorWindow(this, install_dir);
            dialog.show_all();

            return Gdk.EVENT_STOP;
        }

        // Метод для оновлення тексту
        public void update_label(string new_text) {
            label.set_text(new_text);
            save_text_to_json(new_text);
        }

        // Отримуємо шлях до директорії плагіну
        private string get_install_dir() {
            return GLib.Path.get_dirname(GLib.Path.get_dirname(__FILE__));
        }

        // Зчитування тексту з JSON
        private string load_text_from_json() {
            var json_path = GLib.Path.build_filename(install_dir, "config.json");
            var file = File.new_for_path(json_path);
            if (!file.query_exists()) {
                return "Hello, World!"; // Якщо файл зник, повертаємо за замовчуванням
            }

            try {
                var dis = new DataInputStream(file.read());
                string json_data = dis.read_line(null);
                Json.Parser parser = new Json.Parser();
                parser.load_from_data(json_data);
                var root = parser.get_root().get_object();
                return root.get_string_member("text");
            } catch (Error e) {
                stderr.printf("Error loading JSON: %s\n", e.message);
                return "Hello, World!";
            }
        }

        // Збереження тексту в JSON
        private void save_text_to_json(string text) {
            var json_path = GLib.Path.build_filename(install_dir, "config.json");
            var file = File.new_for_path(json_path);

            try {
                var builder = new Json.Builder();
                builder.begin_object();
                builder.set_member_name("text");
                builder.add_string_value(text);
                builder.end_object();

                var generator = new Json.Generator();
                generator.set_root(builder.get_root());
                generator.set_pretty(true);
                generator.to_file(json_path);
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