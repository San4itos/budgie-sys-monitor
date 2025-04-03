using Gtk;

namespace SysMonitor {

    public class SysMonitorWindow : Gtk.Window {
        private SysMonitor.Applet applet;

        public SysMonitorWindow(SysMonitor.Applet parent, string plugin_dir, string initial_text) {
            this.applet = parent;
            set_title("Sys Monitor");
            set_default_size(300, 150);
            set_position(Gtk.WindowPosition.CENTER);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 10);
            box.margin = 10;
            box.get_style_context().add_class("dialog-box");

            var entry = new Gtk.Entry();
            entry.set_placeholder_text("Введіть текст...");
            entry.set_text(initial_text); // Встановлюємо початковий текст із JSON
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