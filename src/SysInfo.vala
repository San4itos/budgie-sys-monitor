// src/SysInfo.vala
using GLib;
using GTop;

namespace SysMonitor {

    public class SysInfo : Object {

        // --- Статичні члени для розрахунку CPU % ---
        private static float last_total = 0.0f;
        private static float last_used = 0.0f;
        private static bool gtop_initialized = false;

        [CCode (cname = "glibtop_init", cheader_filename = "glibtop/global.h")]
        private static extern void gtop_init();

        static construct {
            try {
                gtop_init();
                gtop_initialized = true;
            } catch (Error e) {
                printerr("SysInfo: FATAL: Failed to initialize libgtop in static construct: %s\n", e.message);
            }
        }

        public static int get_cpu_percentage() {
            if (!gtop_initialized) { return -1; }
             try {
                GTop.Cpu cpu_times;
                GTop.get_cpu (out cpu_times);

                if (cpu_times.user == 0 && cpu_times.nice == 0 && cpu_times.sys == 0 && cpu_times.total == 0) {
                    // Попередження може бути корисним, якщо проблема повернеться
                    // printerr("SysInfo WARNING: All raw CPU values received from libgtop are 0!\n");
                }

                var used = cpu_times.user + cpu_times.nice + cpu_times.sys;
                var difference_used = (float)used - last_used;
                var difference_total = (float)cpu_times.total - last_total;

                last_used = (float)used;
                last_total = (float)cpu_times.total;

                if (difference_total <= 0.0f) {
                    return 0;
                }

                var pre_percentage = difference_used.abs() / difference_total.abs();
                 if (pre_percentage < 0.0f) { pre_percentage = 0.0f; }
                 if (pre_percentage > 1.0f) { pre_percentage = 1.0f; }
                int percentage = (int)Math.round (pre_percentage * 100.0f);

                return percentage;

            } catch (Error e) {
                 printerr("!!! ERROR in static get_cpu_percentage() catch block: %s !!!\n", e.message);
                 return -1;
            }
        }

        // Метод для MEM % (використовуємо поле 'user')
        [CCode(cheader_filename="glibtop/mem.h")]
        public static int get_mem_percentage() {
            if (!gtop_initialized) { return -1; }
            try {
                GTop.Memory mem_info;
                GTop.get_mem(out mem_info);

                if (mem_info.total == 0) { return 0; }

                // !!! ЗМІНЕНО: Використовуємо поле 'user' як в прикладі !!!
                double user_mem = (double)mem_info.user; // Пам'ять програм користувача
                double total_mem = (double)mem_info.total;

                // Розраховуємо відсоток саме цієї пам'яті
                double usage_ratio = user_mem / total_mem;

                // Обмеження і округлення
                if (usage_ratio < 0.0) { usage_ratio = 0.0; }
                if (usage_ratio > 1.0) { usage_ratio = 1.0; }
                int percentage = (int)Math.round(usage_ratio * 100.0);

                return percentage;

            } catch (Error e) {
                printerr("!!! ERROR in static get_mem_percentage() catch block: %s !!!\n", e.message);
                return -1;
            }
        }

        // !!! НОВИЙ СТАТИЧНИЙ МЕТОД для SWAP % !!!
        // Потребує cheader_filename, якщо його немає у VAPI для get_swap/Swap
        [CCode(cheader_filename="glibtop/swap.h")]
        public static int get_swap_percentage() {
            if (!gtop_initialized) { return -1; }
            try {
                // !!! УВАГА: Перевір тип GTop.Swap у твоєму VAPI !!!
                GTop.Swap swap_info;
                // !!! УВАГА: Перевір виклик GTop.get_swap у твоєму VAPI !!!
                GTop.get_swap(out swap_info);

                // !!! УВАГА: Перевір імена полів total, used у твоєму VAPI !!!
                if (swap_info.total == 0) { // Перевірка ділення на нуль
                    return 0; // Якщо swap вимкнено, total буде 0
                }

                // Розраховуємо відсоток
                double usage_ratio = (double)swap_info.used / (double)swap_info.total;

                // Обмеження і округлення
                if (usage_ratio < 0.0) { usage_ratio = 0.0; }
                if (usage_ratio > 1.0) { usage_ratio = 1.0; }
                int percentage = (int)Math.round(usage_ratio * 100.0);

                return percentage;

            } catch (Error e) {
                printerr("!!! ERROR in static get_swap_percentage() catch block: %s !!!\n", e.message);
                return -1;
            }
        } // Кінець get_swap_percentage

        // --- Нестатичні методи ---
        public SysInfo() { } // Конструктор за замовчуванням

        // Деструктор закоментований
        /* ~SysInfo() { } */

        [CCode(cheader_filename="glibtop/sysinfo.h")]
        private uint64 get_num_processors() {
             try {
                 unowned GTop.SysInfo? sysinfo_ptr = GTop.glibtop_get_sysinfo ();
                 if (sysinfo_ptr != null) {
                     return sysinfo_ptr.ncpu; // Повертаємо значення без +1
                 } else {
                     printerr("Error in get_num_processors(): GTop.glibtop_get_sysinfo() returned null\n");
                     return 1;
                 }
            } catch (Error e) {
                printerr("Error in get_num_processors() calling libgtop: %s\n", e.message);
                return 1;
            }
        }

        public double get_cpu_frequency_khz() {
            double max_freq_khz = 0.0;
            uint64 num_cpus = this.get_num_processors(); // Викликаємо метод, який тепер логує

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
                } catch (Error e) { /* Ignore */ }
            }

            if (max_freq_khz == 0.0) {
                var cpuinfo_path = "/proc/cpuinfo";
                 try {
                     string contents;
                     if (FileUtils.get_contents(cpuinfo_path, out contents)) {
                         foreach (var line in contents.split("\n")) {
                             if (line.has_prefix("cpu MHz")) {
                                 var parts = line.split(":");
                                 if (parts.length == 2) {
                                     max_freq_khz = double.parse(parts[1].strip()) * 1000.0;
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
} // Кінець namespace SysMonitor