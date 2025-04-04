using GLib;
using GTop;

namespace SysMonitor {

    public class SysInfo : Object {
        private float last_total_cpu_time = 0;
        private float last_used_cpu_time = 0;

        public int get_cpu_percentage() {
            try {
                var cpu_times = GTop.glibtop_cpu ();

                GTop.glibtop.get_cpu (cpu_times);

                // Тепер структура cpu_times заповнена даними, продовжуємо розрахунки
                var current_used = (float)(cpu_times.user + cpu_times.nice + cpu_times.sys);
                var current_total = (float)cpu_times.total;
                var difference_used = current_used - this.last_used_cpu_time;
                var difference_total = current_total - this.last_total_cpu_time;

                this.last_used_cpu_time = current_used;
                this.last_total_cpu_time = current_total;

                double usage_ratio_double = 0.0;
                if (difference_total > 0) {
                    usage_ratio_double = (double)difference_used / (double)difference_total;
                } else {
                    return 0;
                }

                // Тимчасова заміна GLib.Math
                if (usage_ratio_double < 0.0) { usage_ratio_double = 0.0; }
                if (usage_ratio_double > 1.0) { usage_ratio_double = 1.0; }
                int percentage = (int)(usage_ratio_double * 100.0 + 0.5);
                return percentage;

            } catch (Error e) {
                printerr("Error in get_cpu_percentage() using libgtop: %s\n", e.message);
                return -1;
            }
        }

        // Функція get_num_processors вже використовує правильний підхід (отримує вказівник)
        private uint64 get_num_processors() {
             try {
                 unowned GTop.glibtop_sysinfo? sysinfo_ptr = GTop.glibtop.get_sysinfo ();
                 if (sysinfo_ptr != null) {
                     return sysinfo_ptr.ncpu;
                 } else {
                     printerr("Error in get_num_processors(): GTop.glibtop.get_sysinfo() returned null\n");
                     return 1;
                 }
            } catch (Error e) {
                printerr("Error in get_num_processors() calling libgtop: %s\n", e.message);
                return 1;
            }
        }

        // Метод для частоти CPU (без змін)
        public double get_cpu_frequency_khz() {
           double max_freq_khz = 0.0;
            uint64 num_cpus = get_num_processors();
            if (num_cpus == 0) return 0.0;

            int num_cpus_int = (int)num_cpus;
            if (num_cpus_int < 1) num_cpus_int = 1;

            for (int i = 0; i < num_cpus_int; i++) {
                var cpuinfo_path = "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_max_freq".printf(i);
                try {
                    string contents;
                    if (FileUtils.get_contents(cpuinfo_path, out contents)) {
                        double freq_khz = double.parse(contents.strip());
                        if (freq_khz > max_freq_khz) {
                            max_freq_khz = freq_khz;
                        }
                    }
                } catch (Error e) { /* Ігноруємо помилку для одного ядра */ }
            }

            // Резервний варіант через /proc/cpuinfo
            if (max_freq_khz == 0.0) {
                 var cpuinfo_path = "/proc/cpuinfo";
                 try {
                     string contents;
                     if (FileUtils.get_contents(cpuinfo_path, out contents)) {
                         foreach (var line in contents.split("\n")) {
                             if (line.has_prefix("cpu MHz")) {
                                 var parts = line.split(":");
                                 if (parts.length == 2) {
                                     max_freq_khz = double.parse(parts[1].strip()) * 1000.0; // MHz в KHz
                                     break;
                                 }
                             }
                         }
                     }
                 } catch (Error e) {
                     printerr("Error reading %s: %s\n", cpuinfo_path, e.message);
                 }
            }
            return max_freq_khz;
        }
    } // Кінець класу SysInfo
} // Кінець namespace