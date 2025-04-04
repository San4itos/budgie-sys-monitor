// src/SysInfo.vala
using GLib;
using GTop; 

namespace SysMonitor {

    public class SysInfo : Object {
        private float last_total_cpu_time = 0;
        private float last_used_cpu_time = 0;

        public int get_cpu_percentage() {
            try {
                // <<< ЗМІНЕНО: Використовуємо тип зі згенерованого VAPI >>>
                GTop.glibtop_cpu cpu_times; 
                // <<< ЗМІНЕНО: Перевіряємо, чи функція у VAPI називається так само >>>
                // Зазвичай vapigen зберігає C-назву функції
                gtop_get_cpu (out cpu_times); 

                // Розрахунки використовують поля структури, які мають бути однакові
                var current_used = (float)(cpu_times.user + cpu_times.nice + cpu_times.sys);
                var current_total = (float)cpu_times.total;
                var difference_used = current_used - this.last_used_cpu_time;
                var difference_total = current_total - this.last_total_cpu_time;

                this.last_used_cpu_time = current_used;
                this.last_total_cpu_time = current_total;

                float usage_ratio = 0.0f;
                if (difference_total > 0) {
                    usage_ratio = difference_used / difference_total;
                } else {
                    return 0;
                }

                usage_ratio = Math.max(0.0f, Math.min(1.0f, usage_ratio));
                return (int)Math.round (usage_ratio * 100);

            } catch (Error e) {
                printerr("Error getting CPU info from libgtop: %s\n", e.message);
                return -1;
            }
        }

        // Допоміжна функція для отримання кількості процесорів
        private uint get_num_processors() {
            try {
                 // <<< ЗМІНЕНО: Використовуємо структуру зі згенерованого VAPI >>>
                 // Перевірте назву функції та структури у вашому VAPI
                 GTop.glibtop_sysinfo sysinfo; 
                 gtop_get_sysinfo(out sysinfo); // Припускаємо таку функцію
                 return sysinfo.ncpu;
            } catch (Error e) {
                printerr("Error getting number of CPUs: %s\n", e.message);
                return 1;
            }
        }

        // Метод для частоти CPU (без змін, бо він читає /sys)
        public double get_cpu_frequency_khz() {
            double max_freq_khz = 0;
            uint num_cpus = get_num_processors(); 
            // ... (решта коду методу без змін) ...
            return max_freq_khz; 
        }
    } // Кінець класу SysInfo
} // Кінець namespace