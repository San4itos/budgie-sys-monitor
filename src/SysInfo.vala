using GLib;
using GTop;

namespace SysMonitor {
    public class SysInfo : Object {
        private static float last_total = 0.0f;
        private static float last_used = 0.0f;

        [CCode (cname = "glibtop_init", cheader_filename = "glibtop/global.h")]
        private static extern void gtop_init();

        [CCode (cname = "glibtop_close", cheader_filename = "glibtop/global.h")]
        private static extern void gtop_close();

        public static int get_cpu_percentage() {
            stdout.printf("Entering get_cpu_percentage\n");
            gtop_init();
            stdout.printf("libgtop initialized\n");

            GTop.Cpu cpu_times = GTop.Cpu();
            stdout.printf("Before GTop.get_cpu\n");
            GTop.get_cpu(out cpu_times);
            stdout.printf("After GTop.get_cpu\n");

            stdout.printf("CPU Raw Data: User=%llu, Nice=%llu, Sys=%llu, Total=%llu\n", 
                          cpu_times.user, cpu_times.nice, cpu_times.sys, cpu_times.total);

            if (cpu_times.user == 0 && cpu_times.nice == 0 && cpu_times.sys == 0 && cpu_times.total == 0) {
                stdout.printf("WARNING: All CPU values are 0!\n");
            }

            var used = cpu_times.user + cpu_times.nice + cpu_times.sys;
            var difference_used = (float)used - last_used;
            var difference_total = (float)cpu_times.total - last_total;

            last_used = (float)used;
            last_total = (float)cpu_times.total;

            if (difference_total <= 0.0f) {
                stdout.printf("CPU Calc Warning: difference_total <= 0 (%.2f), returning 0\n", difference_total);
                return 0;
            }

            var pre_percentage = difference_used.abs() / difference_total.abs();
            if (pre_percentage < 0.0f) pre_percentage = 0.0f;
            if (pre_percentage > 1.0f) pre_percentage = 1.0f;

            int percentage = (int)Math.round(pre_percentage * 100.0f);

            stdout.printf("CPU Calc: DiffT=%.2f, DiffU=%.2f, Ratio=%.4f, Perc=%d\n",
                          difference_total, difference_used, pre_percentage, percentage);

            return percentage;
        }

        static construct {
            gtop_init();
            stdout.printf("GTop initialized via static construct\n");
        }

        public SysInfo() {
            stdout.printf("SysInfo instance created\n");
        }

        ~SysInfo() {
            stdout.printf("SysInfo instance destroyed\n");
            gtop_close();
        }

        public uint64 get_num_processors() {
            try {
                unowned GTop.SysInfo? sysinfo_ptr = GTop.glibtop_get_sysinfo();
                if (sysinfo_ptr != null) {
                    stdout.printf("Number of CPUs detected: %llu\n", sysinfo_ptr.ncpu);
                    return sysinfo_ptr.ncpu + 1;
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
            uint64 num_cpus = this.get_num_processors();
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
    }
}