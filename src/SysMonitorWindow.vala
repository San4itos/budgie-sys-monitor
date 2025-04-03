using Gtk;

namespace SysMonitor {

    public class SysMonitorWindow : Gtk.Window {
        private SysMonitor.Applet applet;
        private string plugin_dir;

        public SysMonitorWindow(SysMonitor.Applet parent, string plugin_dir) {
            this.applet = parent;
            this.plugin_dir = plugin_dir;
            set_title("Sys Monitor");
            set_default_size(300, 150);
            set_position(Gtk.WindowPosition.CENTER);

            // Завантажуємо стилі
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

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            box.margin = 10;
            box.get_style_context().add_class("dialog-box");

            var entry = new Gtk.Entry();
            entry.set_placeholder_text("Введіть текст...");
            box.pack_start(entry, false, false, 0);

            var button = new Gtk.Button.with_label("Зберегти");
            button.clicked.connect(() => {
                applet.update_label(entry.get_text());
                this.destroy();
            });
            box.pack_start(button, false, false, 0);

            add(box);
        }
    }
}