// src/SysInfo.vala
using GLib;
using GTop; // Використовуємо типи та функції з цього простору імен

namespace SysMonitor {

    // Структура для повернення швидкостей мережі
    public struct NetworkSpeeds {
        public double dl_kibps; // Download KiB/s
        public double ul_kibps; // Upload KiB/s
    }

    // Клас для отримання системної інформації
    public class SysInfo : Object {

        // --- Статичні члени для збереження стану між викликами ---
        // Для CPU %
        private static float cpu_last_total = 0.0f;
        private static float cpu_last_used = 0.0f;
        // Для Network Speed
        private static int64 net_last_check_time_us = 0; // Монотонний час в мікросекундах
        private static uint64 net_last_total_bytes_in = 0;
        private static uint64 net_last_total_bytes_out = 0;
        // Прапорець ініціалізації libgtop
        private static bool gtop_initialized = false;

        // Оголошення extern функції для ініціалізації (беремо з C API)
        // Припускаємо, що VAPI не надає зручного Vala-методу GTop.init()
        [CCode (cname = "glibtop_init", cheader_filename = "glibtop/global.h")]
        private static extern void gtop_init();

        // Статичний конструктор для одноразової ініціалізації libgtop при завантаженні класу
        static construct {
            try {
                gtop_init(); // Викликаємо C-функцію ініціалізації
                gtop_initialized = true;
                stdout.printf("SysInfo: libgtop initialized via static construct.\n");
                // Ініціалізуємо час для мережі
                net_last_check_time_us = GLib.get_monotonic_time();
            } catch (Error e) {
                // Малоймовірно для extern, але про всяк випадок
                printerr("SysInfo: FATAL: Failed to initialize libgtop in static construct: %s\n", e.message);
            }
        }

        // --- Статичні методи отримання даних ---
        // Ми НЕ додаємо [CCode] тут, бо VAPI для типів (Cpu, Memory...)
        // має правильні cheader_filename, що змусить valac включити потрібні заголовки.

        public static int get_cpu_percentage() {
            if (!gtop_initialized) {
                 printerr("SysInfo: get_cpu_percentage - gtop not initialized!\n");
                 return -1;
            }
             try {
                // Використовуємо тип і виклик з нового VAPI
                GTop.Cpu cpu_times;
                GTop.get_cpu (out cpu_times); // Статичний виклик з out

                // Розрахунок 'used'
                var used = cpu_times.user + cpu_times.nice + cpu_times.sys;
                // Розрахунок різниці (використовуємо float і static поля)
                var difference_used = (float)used - cpu_last_used;
                var difference_total = (float)cpu_times.total - cpu_last_total;

                // Оновлення статичних полів
                cpu_last_used = (float)used;
                cpu_last_total = (float)cpu_times.total;

                // Обробка першого запуску / незмінності total
                if (difference_total <= 0.0f) { return 0; }

                // Розрахунок відсотка
                var pre_percentage = difference_used.abs() / difference_total.abs();
                 if (pre_percentage < 0.0f) { pre_percentage = 0.0f; }
                 if (pre_percentage > 1.0f) { pre_percentage = 1.0f; }
                int percentage = (int)Math.round (pre_percentage * 100.0f); // Потребує -lm
                return percentage;
            } catch (Error e) {
                 printerr("!!! ERROR CPU: %s !!!\n", e.message);
                 return -1;
            }
        }

        public static int get_mem_percentage() {
            if (!gtop_initialized) {
                printerr("SysInfo: get_mem_percentage - gtop not initialized!\n");
                return -1;
            }
            try {
                // Використовуємо тип і виклик з нового VAPI
                GTop.Memory mem_info;
                GTop.get_mem(out mem_info);

                if (mem_info.total == 0) { return 0; }

                // Використовуємо поле 'user'
                double user_mem = (double)mem_info.user;
                double total_mem = (double)mem_info.total;
                double usage_ratio = user_mem / total_mem;

                if (usage_ratio < 0.0) { usage_ratio = 0.0; } if (usage_ratio > 1.0) { usage_ratio = 1.0; }
                int percentage = (int)Math.round(usage_ratio * 100.0); // Потребує -lm
                return percentage;
            } catch (Error e) {
                 printerr("!!! ERROR MEM: %s !!!\n", e.message);
                 return -1;
            }
        }

        public static int get_swap_percentage() {
            if (!gtop_initialized) {
                printerr("SysInfo: get_swap_percentage - gtop not initialized!\n");
                return -1;
            }
            try {
                // Використовуємо тип і виклик з нового VAPI
                GTop.Swap swap_info;
                GTop.get_swap(out swap_info);

                if (swap_info.total == 0) { return 0; } // Swap може бути вимкнено

                // Використовуємо поля used і total
                double usage_ratio = (double)swap_info.used / (double)swap_info.total;

                if (usage_ratio < 0.0) { usage_ratio = 0.0; } if (usage_ratio > 1.0) { usage_ratio = 1.0; }
                int percentage = (int)Math.round(usage_ratio * 100.0); // Потребує -lm
                return percentage;
            } catch (Error e) {
                 printerr("!!! ERROR SWAP: %s !!!\n", e.message);
                 return -1;
            }
        }

        public static NetworkSpeeds get_network_speeds() {
            NetworkSpeeds speeds = NetworkSpeeds(); // Ініціалізуємо нулями
            if (!gtop_initialized) {
                printerr("SysInfo: get_network_speeds - gtop not initialized!\n");
                return speeds;
            }

            uint64 current_total_bytes_in = 0;
            uint64 current_total_bytes_out = 0;
            int64 current_time_us = GLib.get_monotonic_time(); // Використовуємо монотонний час

            try {
                // Використовуємо типи і виклики з нового VAPI
                GTop.NetList netlist;
                string[] interfaces = GTop.get_netlist(out netlist);

                if (interfaces == null) {
                     printerr("SysInfo: get_netlist returned null interfaces array.\n");
                     return speeds;
                 }

                foreach (var iface_name in interfaces) {
                    if (iface_name == "lo") { continue; } // Пропускаємо loopback
                    GTop.NetLoad netload_info;
                    GTop.get_netload(out netload_info, iface_name);
                    current_total_bytes_in += netload_info.bytes_in;
                    current_total_bytes_out += netload_info.bytes_out;
                }

                // Розрахунок різниці часу
                double time_diff_sec = (double)(current_time_us - net_last_check_time_us) / 1000000.0;

                // Обробка першого запуску / скидання / відсутності змін часу
                if (net_last_check_time_us == 0 || time_diff_sec <= 0 ||
                    current_total_bytes_in < net_last_total_bytes_in || // Перевірка скидання лічильників
                    current_total_bytes_out < net_last_total_bytes_out)
                {
                    if (net_last_check_time_us != 0 && time_diff_sec > 0) { // Логуємо тільки реальне скидання
                         stdout.printf("SysInfo: Network counters reset detected or time anomaly. Re-initializing.\n");
                    }
                    // Оновлюємо стан і повертаємо нульові швидкості
                    net_last_total_bytes_in = current_total_bytes_in;
                    net_last_total_bytes_out = current_total_bytes_out;
                    net_last_check_time_us = current_time_us;
                    return speeds;
                }

                // Розрахунок різниці байтів
                uint64 diff_bytes_in = current_total_bytes_in - net_last_total_bytes_in;
                uint64 diff_bytes_out = current_total_bytes_out - net_last_total_bytes_out;

                // Розрахунок швидкості в байтах/сек
                double dl_bps = diff_bytes_in / time_diff_sec;
                double ul_bps = diff_bytes_out / time_diff_sec;

                // Конвертація в КіБ/с
                speeds.dl_kibps = dl_bps / 1024.0;
                speeds.ul_kibps = ul_bps / 1024.0;

                // Зберігаємо поточний стан
                net_last_total_bytes_in = current_total_bytes_in;
                net_last_total_bytes_out = current_total_bytes_out;
                net_last_check_time_us = current_time_us;

                return speeds;

            } catch (Error e) {
                printerr("!!! ERROR NET: %s !!!\n", e.message);
                net_last_check_time_us = 0; // Скидаємо час при помилці
                return speeds; // Повертаємо нулі
            }
        }

        // Метод форматування швидкості
        public static string format_speed(double kibps) {
             if (kibps < 0) { kibps = 0; }
            if (kibps < 1000.0) {
                return "%.1f KiB/s".printf(kibps);
            } else if (kibps < 1024.0 * 1000.0) {
                return "%.1f MiB/s".printf(kibps / 1024.0);
            } else {
                return "%.1f GiB/s".printf(kibps / 1024.0 / 1024.0);
            }
        }

        // --- Нестатичні методи (для внутрішнього використання або майбутніх функцій) ---
        public SysInfo() { } // Порожній конструктор екземпляра

        // Метод отримання кількості процесорів (може бути потрібен для get_cpu_frequency_khz)
        // Прибираємо CCode, бо VAPI для struct SysInfo має правильний cheader_filename
        private uint64 get_num_processors() {
             try {
                 // Використовуємо C-назву функції з VAPI
                 unowned GTop.SysInfo? sysinfo_ptr = GTop.glibtop_get_sysinfo ();
                 if (sysinfo_ptr != null) {
                     return sysinfo_ptr.ncpu;
                 } else {
                     printerr("Error in get_num_processors(): GTop.glibtop_get_sysinfo() returned null\n");
                     return 1;
                 }
            } catch (Error e) {
                printerr("Error in get_num_processors() calling libgtop: %s\n", e.message);
                return 1;
            }
        }

        // Метод отримання частоти CPU (не залежить від libgtop VAPI)
        public double get_cpu_frequency_khz() {
           double total_freq_khz = 0.0;
           int valid_cores_found = 0;
           uint64 num_cpus = this.get_num_processors(); // Викликаємо нестатичний метод
           if (num_cpus == 0) return 0.0;
           int num_cpus_int = (int)num_cpus;
           if (num_cpus_int < 1) num_cpus_int = 1;
           for (int i = 0; i < num_cpus_int; i++) {
               var cpuinfo_path = "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq".printf(i);
               try {
                   string contents;
                   if (FileUtils.get_contents(cpuinfo_path, out contents)) {
                       double freq_khz = double.parse(contents.strip());
                       total_freq_khz += freq_khz; valid_cores_found++;
                   }
               } catch (Error e) { /* Ignore */ }
           }
            double avg_freq_khz;
            if (valid_cores_found > 0) {
                 avg_freq_khz = total_freq_khz / valid_cores_found;
            } else {
                 avg_freq_khz = read_freq_from_proc_cpuinfo(); // Резервний варіант
            }
           return avg_freq_khz;
        }

        // Допоміжний метод читання частоти з /proc/cpuinfo (усереднення)
        private double read_freq_from_proc_cpuinfo() {
             double total_mhz = 0.0; int core_count = 0;
             var cpuinfo_path = "/proc/cpuinfo";
              try {
                  string contents;
                  if (FileUtils.get_contents(cpuinfo_path, out contents)) {
                      foreach (var line in contents.split("\n")) {
                          if (line.has_prefix("cpu MHz")) {
                              var parts = line.split(":");
                              if (parts.length == 2) {
                                  try { total_mhz += double.parse(parts[1].strip()); core_count++; }
                                  catch (Error parse_err) { /* ignore */ }
                              }
                          }
                      }
                  }
              } catch (Error e) { return 0.0; }
              if (core_count > 0) { return (total_mhz / core_count) * 1000.0; }
              else { return 0.0; }
         }

    } // Кінець класу SysInfo
} // Кінець namespace SysMonitor