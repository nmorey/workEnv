module WorkEnvs
    # Hostname of the current machine
    WORK_ENV_HOSTNAME= ENV["HOSTNAME"].to_s != "" ? ENV["HOSTNAME"] :
                             (File.exist?("/usr/bin/hostname") ? `/usr/bin/hostname`.chomp() : "")

    # Dir where workEnv scripts are
    WORK_ENV_SCRIPTS_DIR=File.dirname(File.dirname(File.dirname(File.dirname(__FILE__))))

    # Directory for global configuration
    WORK_ENV_GLOBAL_DIR = (ENV["XDG_CONFIG_HOME"] != nil) ?
                                File.expand_path("#{ENV["XDG_CONFIG_HOME"]}/workEnv/"):
                                File.expand_path("~/.config/workEnv/")

    # Per host cache directory within the global config directory
    WORK_ENV_CACHE_DIR = WORK_ENV_GLOBAL_DIR + "/" + WORK_ENV_HOSTNAME

    # Global flag to enable verbosity
    VERBOSE = (ENV["VERBOSE"].to_s != "") ? true: false

end
