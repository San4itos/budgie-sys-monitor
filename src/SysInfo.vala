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
            double total_freq_khz = 0.0;
            uint64 num_cpus = this.get_num_processors(); // Отримуємо кількість логічних CPU
            if (num_cpus == 0) return 0.0;

            int num_cpus_int = (int)num_cpus;
            if (num_cpus_int < 1) num_cpus_int = 1;

            int valid_cores_found = 0; // Лічильник ядер, для яких вдалося прочитати частоту

            // Перебираємо всі логічні процесори
            for (int i = 0; i < num_cpus_int; i++) {
                // Шлях до файлу поточної частоти для ядра 'i'
                var cpuinfo_path = "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq".printf(i);
                try {
                    string contents;
                    if (FileUtils.get_contents(cpuinfo_path, out contents)) {
                        // Парсимо частоту (вона вже в KHz)
                        double freq_khz = double.parse(contents.strip());
                        total_freq_khz += freq_khz; // Додаємо до суми
                        valid_cores_found++;      // Збільшуємо лічильник успішних читань
                    }
                    // Якщо файл не знайдено для ядра, просто пропускаємо його
                } catch (Error e) {
                    // Можна додати лог помилки читання для конкретного ядра, якщо потрібно
                    // printerr("Warning: Could not read scaling_cur_freq for cpu%d: %s\n", i, e.message);
                }
            }

            // Розраховуємо середнє, якщо вдалося прочитати хоча б для одного ядра
            if (valid_cores_found > 0) {
                double average_freq_khz = total_freq_khz / valid_cores_found;
                 // Лог для відладки (можна потім прибрати)
                 // stdout.printf("SysInfo: get_cpu_frequency_khz() calculated average freq = %.0f KHz from %d cores\n", average_freq_khz, valid_cores_found);
                return average_freq_khz;
            } else {
                // Якщо не вдалося прочитати жодного файлу з /sys, спробуємо резервний /proc/cpuinfo
                 // printerr("SysInfo: Could not read scaling_cur_freq from any core. Falling back to /proc/cpuinfo.\n");
                 // Викликаємо допоміжний метод (який ми визначали раніше)
                 return read_freq_from_proc_cpuinfo();
            }
        }

        // Допоміжний метод для читання з /proc/cpuinfo (залишається корисним як резервний)
        private double read_freq_from_proc_cpuinfo() {
            double total_mhz = 0.0;     // Сума частот в MHz
            int core_count = 0;         // Кількість знайдених значень
            var cpuinfo_path = "/proc/cpuinfo";

             try {
                 string contents;
                 if (FileUtils.get_contents(cpuinfo_path, out contents)) {
                     // Перебираємо всі рядки у файлі
                     foreach (var line in contents.split("\n")) {
                         // Шукаємо рядки, що містять частоту
                         if (line.has_prefix("cpu MHz")) {
                             var parts = line.split(":");
                             if (parts.length == 2) {
                                 try {
                                     // Парсимо значення MHz і додаємо до суми
                                     total_mhz += double.parse(parts[1].strip());
                                     core_count++; // Збільшуємо лічильник ядер
                                 } catch (Error parse_err) {
                                     // Ігноруємо помилки парсингу для окремого рядка
                                      printerr("Warning: Could not parse MHz value in line: %s\n", line);
                                 }
                             }
                         }
                     } // кінець foreach
                 } else {
                      printerr("Error: Could not read contents of %s\n", cpuinfo_path);
                 }
             } catch (Error e) {
                 printerr("Error reading %s: %s\n", cpuinfo_path, e.message);
                 return 0.0; // Повертаємо 0 при помилці читання файлу
             }

             // Розраховуємо середнє і переводимо в KHz
             if (core_count > 0) {
                 double average_khz = (total_mhz / core_count) * 1000.0;
                 // stdout.printf("SysInfo: read_freq_from_proc_cpuinfo() calculated average = %.0f KHz from %d cores\n", average_khz, core_count);
                 return average_khz;
             } else {
                 // stdout.printf("SysInfo: read_freq_from_proc_cpuinfo() did not find any 'cpu MHz' lines.\n");
                 return 0.0; // Повертаємо 0, якщо не знайдено жодного значення
             }
        } // Кінець read_freq_from_proc_cpuinfo


    } // Кінець класу SysInfo
} // Кінець namespace SysMonitor