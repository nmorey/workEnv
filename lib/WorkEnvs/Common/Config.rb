#!/usr/bin/ruby

require 'yaml'
require_relative 'EnvOpts'

module WorkEnvs
    # Path to global configuration file
    WORK_ENV_DB_GLOBAL_CONF = WORK_ENV_GLOBAL_DIR + "/config-global"

    # Path to host specific configuration file
    WORK_ENV_DB_DEFAULT_CONF = WORK_ENV_CACHE_DIR + "/config"

    # Version of the settings has. Used for migration
    WORK_ENV_CONFIG_VERSION = 15

    # Default settings value
    @@BASE_SETTINGS = {
        :db => {
            :initialized           => false,
            :package_db            => "packages-db",
            :package_db_proto      => :mysql,
            :package_repos        => [ "http://packages:88" ],
            :maxcount              => 5,
            :package_db_user       => "workEnv",
            :package_db_passwd     => "workEnv",
            :package_db_db         => "repositories",
            :package_default_table => "package",
            :package_db_tables     => [ "package", "releases", "integration" ],
            :git_repo              => "git",

        },
        :arch => {
            :machine               => nil,
        },
        :global => {
            :check_updates         => true,
            :confirm_delete        => true,
            :config_file           => nil,
            :silent_update         => false,
            :version               => WORK_ENV_CONFIG_VERSION,
            :unthreaded            => false,
            :custom_env_dirs       => {},
        }
    }

    # Default settings has
    #
    # Filled during the first call to settings() by parsing options and config files
    @@settings = nil

    # Merge hash settings into settings
    #
    # Use to merge default, global and host settings
    def merge_settings(settings, hash)
        hash.each(){|top_key, sub_hash|
            next if settings[top_key] == nil
            sub_hash.each(){|key, val|
                settings[top_key][key] = val
            }
        }
    end
    module_function :merge_settings

    # Remove hash settings from settings
    #
    # Use to remove host, global or default settings value to generate the lightest config file
    def extract_settings(settings, hash)
        hash.each(){|top_key, sub_hash|
            next if settings[top_key] == nil
            sub_hash.each(){|key, val|
                next if top_key == :global and key == :version
                settings[top_key].delete(key) if settings[top_key][key] == val
            }
        }
    end
    module_function :extract_settings

    # Migrate config object to the latest version
    def config_migrate(settings)
        return {} if settings == {}
        case settings[:global][:version]
        when nil, 1
            settings[:global][:version] = 2
            config_migrate(settings)
        when 2
            settings[:global][:version] = 3
            settings[:global][:check_updates] = true
            config_migrate(settings)
       when 3
            settings[:global][:version] = 4
            settings[:global][:confirm_delete] = true
            config_migrate(settings)
        when 4
            settings[:global][:version] = 5
            settings[:global][:silent_update] = false
            config_migrate(settings)
        when 5
            settings[:global][:version] = 6
            config_migrate(settings)
        when 6
            settings[:db][:package_repo] = "packages:88" if settings[:db][:package_repo] == "hermes:88"
            settings[:global][:version] = 7
            config_migrate(settings)
       when 7
            settings[:db][:package_db] = "packages-db" if settings[:db][:package_db] == "redmine"
            settings[:global][:version] = 8
            config_migrate(settings)
        when 8
            settings[:db][:git_repo] = "git"
            settings[:global][:version] = 9
            config_migrate(settings)
        when 9
            settings[:global][:version] = 10
            config_migrate(settings)
        when 10
            settings[:global][:package_repos] = [
                settings[:global][:package_repo_proto] + "://" + settings[:global][:package_repo]
            ]
            settings[:global][:package_repo] = nil
            settings[:global][:package_repo_proto] = nil
            settings[:global][:version] = 11
             config_migrate(settings)
       when 11
           settings[:db][:package_db_proto] = :mysql
           settings[:global][:version] = 12
           config_migrate(settings)
       when 12
           settings[:global][:version] = 13
           config_migrate(settings)
       when 13
           settings[:global][:unthreaded] = false
           settings[:global][:version] = 14
           config_migrate(settings)
       when 14
           settings[:global][:custom_env_dirs] = {}
           settings[:global][:version] = 15
           config_migrate(settings)
       when WORK_ENV_CONFIG_VERSION
            return settings
        else
            raise("")
        end
    end
    module_function :config_migrate

    # Load and return a settings hash from a file
    #
    # Automatically migrate old version to the latest
    def config_load(path)
        begin
            return {} if !File.exist?(path)
            desc = File.open(path)
            settings = YAMLLoad(desc)
            desc.close()
            return config_migrate(settings)
        rescue => e
            STDERR.puts "Invalid settings file '#{path}'.\n#{e}\nIgnoring..."
            @@settings[:global].delete(:config_file)
            return {}
        end
    end
    module_function :config_load

    # Save settings to global settings file
    #
    # Remove default settings and only write the modified ones
    def save_global_config(settings)
        modified_settings = YAMLLoad(settings.to_yaml())
        extract_settings(modified_settings, @@BASE_SETTINGS)
        modified_settings[:global] = {}         if modified_settings[:global] == nil
        modified_settings[:global][:version] = WORK_ENV_CONFIG_VERSION

        runCmd("mkdir -p #{File.dirname(WORK_ENV_DB_GLOBAL_CONF)}", !VERBOSE)
        desc = File.open(WORK_ENV_DB_GLOBAL_CONF, "w+")
        desc.puts modified_settings.to_yaml()
        desc.close()
    end
    module_function :save_global_config

    # Save settings to host settings file
    #
    # Remove default and global settings and only write the modified ones
    def save_local_settings(settings, path = WORK_ENV_DB_DEFAULT_CONF)
        path = WORK_ENV_DB_DEFAULT_CONF if path.to_s == ""

        global_settings = config_load(WORK_ENV_DB_GLOBAL_CONF)
        modified_settings = YAMLLoad(settings.to_yaml())
        extract_settings(modified_settings, global_settings)
        extract_settings(modified_settings, @@BASE_SETTINGS)
        settings[:global][:version] = WORK_ENV_CONFIG_VERSION

        runCmd("mkdir -p #{File.dirname(path)}", !VERBOSE)
        desc = File.open(path, "w+")
        desc.puts modified_settings.to_yaml()
        desc.close()
    end
    module_function :save_local_settings

    # Fetch the settings hash
    #
    # Generate a setting hash from the default values, the global and the local settings files
    #
    # Store them in @@settings to avoid reparsing file every time
    def settings(options = {})
        return  @@settings if @@settings != nil &&
            ( options.empty? == true || options.values.inject({}){|q, c| q.merge(c)}.empty? == true)

        @@settings = YAMLLoad(@@BASE_SETTINGS.to_yaml())
        return @@settings if options[:control] != nil && options[:control][:reset] != nil

        config_file = options[:control] != nil ? options[:control][:config_file].to_s : ""
        if config_file == ""
            config_file = WORK_ENV_DB_DEFAULT_CONF
        else
            raise("Invalid config file #{config_file}") if !File.exist?(config_file)
        end
        # Load the global config
        if File.exist?(WORK_ENV_DB_GLOBAL_CONF) then
            settings = config_load(WORK_ENV_DB_GLOBAL_CONF)
            merge_settings(@@settings, settings)
        end

        # Try to load local config from home
        if (options[:control] == nil || options[:control][:globalOnly] != true) && File.exist?(config_file) then
            @@settings[:global][:config_file] = config_file
            settings = config_load(config_file)
            merge_settings(@@settings, settings)
            @@settings[:global][:config_file] = config_file if @@settings[:global][:config_file].to_s == ""
        end

        merge_settings(@@settings, options)
        @@settings[:global][:check_updates] = false if getArch()[:base] == "WINNT"

        return  @@settings
    end
    module_function :settings

    # Add setting options to opts Parser
    def configSelectorPrepare(opts, optsParser)
        opts[:settings] = { :db => {}, :arch =>{}, :global => {}, :control => {}}

        optsParser.separator "\nDatabase Connection Settings:"
        optsParser.on("--package-db <DB hostname:port|db.sqlite>", String,
                      "Package Database hostname (default is #{@@BASE_SETTINGS[:package_db]}).") {|val|
            opts[:settings][:db][:package_db] = val}
        optsParser.on("--package-db-proto <mysql|sqlite>", String,
                      "Protocol for package database  (default is #{@@BASE_SETTINGS[:package_db_proto]}).") {|val|
            opts[:settings][:db][:package_db_proto] = val.to_sym()}
        optsParser.on("--package-repo <(http|https)://repo hostname:port|file:///path/to/rpm>", String,
                      "Package Repository URI (default is #{@@BASE_SETTINGS[:package_repo]}).") {|val|
            opts[:settings][:db][:package_repos] = [] if opts[:settings][:db][:package_repos] == nil
            opts[:settings][:db][:package_repos] << val
        }
        optsParser.on("-T", "--table <table name> ", String,
                      "Select database table (conflicts with --release).") {|val|
            opts[:settings][:db][:package_default_table] = val}
        optsParser.on("--table-list <table name,table name,...> ", String,
                      "Select database table list (conflicts with --release).") {|val|
            opts[:settings][:db][:package_db_tables] = val.split(",")}
        optsParser.on("--rpc-host [user@]host[:/path/to/envs]", String, "Remote host to use RPC.") {|val|
            opts[:settings][:db][:rpc_host] = val
        }

        opts[:settings][:arch][:machine] = opts[:machine] if opts[:machine] != nil
        optsParser.separator "\nArch Settings:"
        optsParser.on("-m", "--machine <machinetype>", String,
                      "Machine type to use (Default = #{WorkEnvs::getArch(opts[:machine], true)[:label]}).") {|val|
            opts[:settings][:arch][:machine] = WorkEnvs::getArch(val, true)[:label]}

        optsParser.separator "\nGeneric Config Settings:"
        optsParser.on("--config-file </path/to/file>", String, "YAML config file do DB settings.") {|val|
            opts[:settings][:control][:config_file] = val}
        optsParser.on("--default-config", nil, "Ignore all config file and use the default config. Combine with --save-config to reset your config files.") {|val| opts[:settings][:control][:reset] = true}
        optsParser.on("--save-config [/path/to/save/file]", String,
                      "Save the current option set to destionation file  (default is #{WORK_ENV_DB_DEFAULT_CONF}).") {|val|
            opts[:settings][:control][:save_config_file] = val.to_s}
        optsParser.on("--show-config", nil, "Show the config used for DB connections.") {|val|
            opts[:settings][:control][:show_config] = true}
        optsParser.on("--clear-config", nil, "Remove default config file.") {|val|
            Confirm.new("Do you want to remove the config file: #{WORK_ENV_DB_DEFAULT_CONF}")
            runCmd("rm -f #{WORK_ENV_DB_DEFAULT_CONF}")
            exit 0
        }
        optsParser.on("--[no-]unthreaded", "Disable multithreaded package download") {|val|
            opts[:settings][:global][:unthreaded] = val}
        optsParser.on("-U", "--update", nil, "Look for workEnv updates.") {
            |val| opts[:settings][:control][:updateLookup] = true}
        optsParser.on("--no-auto-update", nil, "Disable auto updates.") {
            |val| opts[:settings][:global][:check_updates] = false}
        optsParser.on("--yes", nil, "Assume yes to all questions.") {
            |val| opts[:settings][:global][:alwaysYes] = true}
        optsParser.on("--no", nil, "Assume no to all questions.") {
            |val| opts[:settings][:global][:alwaysNo] = true}
        optsParser.on("-R", "--rpc <base64>", String, "RPC Base64 encoded parameters" ) {
            |val| opts[:settings][:control][:rSettings] = WorkEnvs::deserialize(val)[0]}
        optsParser.on("--custom-env-dirs [label1=path1,name2=path2]", String, "Add custom environment dirs" ) {
            |val|
            opts[:settings][:global][:custom_env_dirs] = {}
            val.to_s().split(",").each(){|dir|
                a = dir.split("=")
                raise("Invalid custom-env-dir format '#{dir}'") if a.length != 2
                opts[:settings][:global][:custom_env_dirs][a[0]] = a[1]
            }
        }

    end
    module_function :configSelectorPrepare

    # Post process settings passed to command line
    #
    # All the value are changed in the settings already
    #
    # This is just used to show/modify/dump config files
    def configSelectorFinal(opts)
        doUpdate = false
        control = opts[:settings][:control]
        doUpdate = true if control[:updateLookup] == true
        if opts[:settings][:control][:rSettings] != nil then
            # Merge RPC provided settings with ours
            # Drop unwanted stuff first
            # Clean out all regualr control so we cannot hack config through RPC
            rArg = opts[:settings][:control][:rSettings].merge({})
            rSettings = rArg[:settings].merge({})
            opts[:settings][:control] = {}
            opts[:settings][:control][:rSettings] = rArg

            rSettings[:control] = {}
            dbRSettings = rSettings[:db]
            rSettings[:db] = {}
            rSettings[:db][:package_db_tables] = dbRSettings[:package_db_tables] if dbRSettings[:package_db_tables] != nil
            merge_settings(opts[:settings], rSettings)
        end
        settings = WorkEnvs::settings(opts[:settings])

        if doUpdate == true
            WorkEnvs::checkEnvs(true)
            exit
        end

        if settings[:global][:alwaysNo] == true &&  settings[:global][:alwaysYes] == true then
            raise("Cannot use --yes and --no at the same time")
        end
        if control[:show_config] == true then
            puts "Current DB configuration"
            puts settings.to_yaml
            exit 0
        end

        if opts[:envOpts].class == WorkEnvs::EnvOpts  &&
           settings[:global][:default_options].class == WorkEnvs::EnvOpts then
            opts[:envOpts].concat(settings[:global][:default_options])
        end
        if control[:save_config_file] != nil then
            out_file = control[:save_config_file]
            if control[:globalOnly] == true then
                save_global_config(settings)
            else
                save_local_settings(settings, out_file)
            end
            exit 0
        end
    end
    module_function :configSelectorFinal
end
