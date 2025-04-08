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
        public SysInfo () {
        }

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

        public double get_cpu_frequency_khz() {
            bool sysfs_success;
            // Спробуємо основний, більш сучасний метод через SysFS
            double freq = read_max_freq_from_sysfs(out sysfs_success);
    
            if (sysfs_success) {
                // Успіх з /sys, повертаємо результат
                return freq;
            } else {
                // Невдача з /sys, пробуємо резервний метод через ProcFS
                bool proc_success; // Результат цієї змінної нам тут не потрібен
                // Попередження про помилку /sys буде виведено всередині read_max_freq_from_sysfs (якщо є)
                warning("Could not get frequency from SysFS, falling back to ProcFS.");
                return read_max_freq_from_proc_cpuinfo(out proc_success);
            }
        }
    
        // --- Приватні методи для читання частоти ---
    
        /**
         * Читає поточні частоти з /sys/devices/system/cpu/cpuX/cpufreq/scaling_cur_freq
         * і повертає максимальну знайдену в КГц.
         * @param success Встановлюється в true, якщо вдалося прочитати хоча б одну частоту.
         * @return Максимальна частота в КГц або 0.0 при помилці отримання кількості CPU.
         */
        private double read_max_freq_from_sysfs(out bool success) {
            success = false;
            double max_freq_khz_sys = 0.0;
    
            uint64 num_cpus = this.get_num_processors();
            if (num_cpus == 0) {
                // Попередження про помилку get_num_processors буде всередині самого методу
                return 0.0; // Не можемо продовжити
            }
    
            int num_cpus_int = (int)num_cpus;
            if (num_cpus_int < 1) num_cpus_int = 1; // Про всяк випадок
    
            for (int i = 0; i < num_cpus_int; i++) {
                var cpuinfo_path = "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq".printf(i);
                try {
                    string contents;
                    // FileUtils.get_contents поверне false, якщо файл не існує або немає прав
                    if (FileUtils.get_contents(cpuinfo_path, out contents)) {
                        // Намагаємося розпарсити значення
                        double current_freq_khz = double.parse(contents.strip());
                        // Оновлюємо максимум
                        if (current_freq_khz > max_freq_khz_sys) {
                            max_freq_khz_sys = current_freq_khz;
                        }
                        // Позначаємо успіх, якщо хоча б одне ядро прочитано
                        success = true;
                    }
                    // Якщо get_contents повернув false, мовчки ігноруємо (файл може бути відсутній для офлайн ядер)
                } catch (Error e) {
                    // Помилка парсингу або інша помилка GLib
                    warning("Error reading/parsing SysFS frequency file %s: %s", cpuinfo_path, e.message);
                    // Продовжуємо цикл, можливо, інші ядра вдасться прочитати
                }
            }
            // Повертаємо знайдений максимум (буде 0.0, якщо success залишився false)
            return max_freq_khz_sys;
        }
    
        /**
         * Читає частоти з /proc/cpuinfo (рядки 'cpu MHz')
         * і повертає максимальну знайдену, переведену в КГц.
         * Використовується як резервний метод.
         * @param success Встановлюється в true, якщо вдалося прочитати і розпарсити хоча б одну частоту.
         * @return Максимальна частота в КГц або 0.0 при помилці.
         */
        private double read_max_freq_from_proc_cpuinfo(out bool success) {
             success = false;
             double max_mhz = 0.0;
             var cpuinfo_path = "/proc/cpuinfo";
             bool found_any_valid_line = false;
    
              try {
                  string contents;
                  if (FileUtils.get_contents(cpuinfo_path, out contents)) {
                      foreach (var line in contents.split("\n")) {
                          // Шукаємо рядки, що починаються з "cpu MHz"
                          if (line.has_prefix("cpu MHz")) {
                              var parts = line.split(":");
                              if (parts.length == 2) {
                                  try {
                                      // Парсимо значення після двокрапки
                                      string mhz_str = parts[1].strip();
                                      var current_mhz = double.parse(mhz_str);
                                      // Оновлюємо максимум
                                      if (current_mhz > max_mhz) {
                                          max_mhz = current_mhz;
                                      }
                                      // Відмічаємо, що хоч один рядок оброблено
                                      found_any_valid_line = true;
                                  }
                                  catch (Error parse_err) {
                                      // Помилка парсингу конкретного рядка, ігноруємо його
                                      warning("Failed to parse ProcFS MHz value from line '%s': %s", line.strip(), parse_err.message);
                                  }
                              }
                          }
                      }
                      // Встановлюємо загальний успіх, якщо обробили хоча б один рядок
                      if (found_any_valid_line) {
                          success = true;
                      } else {
                          warning("No valid 'cpu MHz' lines found or parsed in %s", cpuinfo_path);
                      }
                  } else {
                       // Помилка читання файлу /proc/cpuinfo
                       warning("Could not read ProcFS fallback file: %s", cpuinfo_path);
                       // success залишається false
                       return 0.0;
                  }
              } catch (Error e) {
                    // Інша помилка при роботі з файлом
                    warning("Error processing ProcFS fallback file %s: %s", cpuinfo_path, e.message);
                    // success залишається false
                    return 0.0;
              }
    
              // Повертаємо максимальну знайдену частоту, переведену в КГц
              return max_mhz * 1000.0;
        }
 
    } // Кінець класу SysInfo
} // Кінець namespace SysMonitor