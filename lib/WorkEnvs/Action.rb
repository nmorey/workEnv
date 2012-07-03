module WorkEnvs
  class Common < CLIClassTool::Common
  end

  class WorkEnvAction < Common
    ACTION_LIST = [ :check, :clean, :config, :create, :get, :help, :list, :package_lookup, :query, :rename, :rm, :switch, :test, :update ]

    ACTION_HELP = {
      :check          => "Check an environment validity.",
      :clean          => "Clean an environment.",
      :config         => "View and Edit WorkEnvs parameters.",
      :create         => "Create a new environment.",
      :get            => "Get the properties of the current environment.",
      :help           => "Display help or manual pages for WorkEnvs commands.",
      :list           => "List available environments.",
      :package_lookup => "Lookup environments containing a package.",
      :query          => "Query database for packages and versions.",
      :rename         => "Rename an environment.",
      :rm             => "Remove an environment.",
      :switch         => "Switch to a different environment.",
      :test           => "Verify the type and properties of an environment.",
      :update         => "Update an environment with new versions."
    }

    # Set command-line options specifically for each action
    def self.set_opts(action, parser, opts)
      case action
      when :clean
        parser.on("-n", "--name <env_name>", String, "Name of the environment to clean.") {|val| opts[:name] = val}
        WorkEnvs::configSelectorPrepare(opts, parser)

      when :config
        WorkEnvs::configSelectorPrepare(opts, parser)
        parser.separator ""
        parser.separator "Advanced Settings:"
        parser.on("--[no-]confirm-delete", nil, "[Do not] Ask confirmation before removing an environment.") {
            |val| opts[:settings][:global][:confirm_delete] = val}
        parser.on("--[no-]confirm-update", nil, "[Do not] Ask confirmation before retrieving workEnv updates.") {
            |val| opts[:settings][:global][:silent_update] = !val}
        parser.on("--default-option <option-name=value>", String, "Default option. Can be overriden with --options.") {
            |val|
            opts[:settings][:global][:default_options] = WorkEnvs::EnvOpts.new() if opts[:settings][:global][:default_options] == nil
            opts[:settings][:global][:default_options] << val}
        parser.on("--global", nil, "Parse/Save only the global config file.") {
            |val| opts[:settings][:control][:globalOnly] = true}
        parser.on("--show <path/in/tree>", String, "Show a specific settings. Example: db/package_repos.") {
            |val| opts[:show] = val}

      when :create
        opts[:type] = WorkEnvs::WORK_ENV_DEFAULT_TYPE
        parser.on("-n", "--name <env_name>", String, "Name of the environment to create.") {|val| opts[:name] = val}
        parser.on("-t", "--type <envType>", String, "Environment type: Default = #{opts[:type]}.") {|val| opts[:type] = val}
        parser.on("-r", "--release ", nil, "Released versions only.") {|val| opts[:settings][:db][:package_default_table] = "releases"}
        WorkEnvs::configSelectorPrepare(opts, parser)
        parser.separator ""
        WorkEnvs::addEnvToOptParser(parser)

      when :help, :switch
        opts[:ignore_opts] = true
        if action == :switch
          parser.on("-n", "--name <env_name>", String, "Name of the environment to switch to.") {|val| opts[:name] = val}
        end

      when :list
        parser.on("-s", "--short", nil, "Short version.") {|val| opts[:listType] = :short}
        parser.on("-l", "--long", nil, "Long version.") {|val| opts[:listType] = :long}
        parser.on("-n", "--name-only", nil, "Only print env namess.") {|val| opts[:listType] = :name}

      when :package_lookup
        opts[:rec] = false
        opts[:envOpts] = WorkEnvs::EnvOpts.new()
        opts[:checkGitDependencies] = false
        parser.on("-t", "--type <envType>", String, "Environment type: Default = #{opts[:type]}.") {|val| opts[:type] = val}
        parser.on("-p", "--package <package>", String, "Package to lookup.") {|val| opts[:package] = val}
        parser.on("-r", "--regex", String, "Allow extended package name matching.") {|val| opts[:regex] = true}

      when :query
        opts[:type] = WorkEnvs::WORK_ENV_DEFAULT_TYPE
        opts[:envOpts][WorkEnvs::WENV_OPTS_EXTERNAL] = "true"
        opts[:download] = false
        opts[:rQuery] = false
        opts[:raw] = false
        opts[:updateLookup] = false
        opts[:checkGitDependencies] = false
        opts[:no_deps] = false

        parser.on("-t", "--type <envType>", String, "Environment type: Default = #{opts[:type]}.") {|val| opts[:type] = val}
        parser.on("-r", "--release ", nil, "Released versions only.") {|val| opts[:settings][:db][:package_default_table] = "releases"}
        parser.on("-i", "--internal ", nil, "List internal packages.") {|val| opts[:envOpts][WorkEnvs::WENV_OPTS_EXTERNAL] = nil}
        parser.on("-d", "--download [download_dir]", String, "Download the packages.") {|val| opts[:download] = val}
        parser.on("-c", "--createrepo", nil, "Create a repository in the downloaded package repository. Requires --download" ) {|val| opts[:createRepo] = true}
        parser.on("-r", "--raw", nil, "Generate YAML/B64 object to describe all packages" ) {|val| opts[:raw] = true}
        parser.on("--check-git-dependencies", nil, "Check that git dependencies match RPMs" ) {|val| opts[:checkGitDependencies] = true}
        parser.on("--show-environments", nil, "Show the list of environments being pulled") {|val| opts[:showEnvironments] = true }
        parser.on("--no-dependencies", nil, "Only check the selected env type and not its dependencies") {|val| opts[:no_deps] = true }
        parser.on("--list-envs", nil, "List existing environment types.") {|val|
            envHash = WorkEnvs::listEnvTypes()
            puts envHash.map(){|x, y| x.to_s()}.join(' ')
            exit(0)
        }
        WorkEnvs::versionSelectorPrepare(opts, parser)
        WorkEnvs::configSelectorPrepare(opts, parser)
        parser.separator ""
        WorkEnvs::addEnvToOptParser(parser)

      when :rename
        parser.on("-n", "--name <env_name>", String, "Original name of the environment.") {|val| opts[:name] = val}
        parser.on("-N", "--new-name <new_env_name>", String, "New name to give the environment.") {|val| opts[:newname] = val}
        WorkEnvs::configSelectorPrepare(opts, parser)

      when :rm
        parser.on("-n", "--name <env_name>", String, "Name of the environment to remove.") {|val| opts[:name] = val}
        WorkEnvs::configSelectorPrepare(opts, parser)

      when :test
        opts[:rec] = false
        opts[:envOpts] = WorkEnvs::EnvOpts.new()
        opts[:checkGitDependencies] = false
        parser.on("-n", "--name <env_name>", String, "Name of the environment to test.") {|val| opts[:name] = val}
        parser.on("-t", "--type <envType>", String, "Environment type.") {|val| opts[:type] = val}

      when :update
        opts[:checkGitDependencies] = false
        parser.on("-n", "--name <env_name>", String, "Name of the environment to update.") {|val| opts[:name] = val}
        parser.on("-d", "--date <MM/DD/YYYY>", String, "License expiration date.") {|val| opts[:date] = val}
        parser.on("-f", "--force", nil, "Force to update even if env looks up to date.") {|val| opts[:force_update] = true}
        parser.on("--force-if-not-const", nil, "Force to update even if env looks up to date but is not const.") {|val| opts[:force_update_if_not_const] = true}
        parser.on("-D", "--dump-infos <info.txt>", String, "Dump the version of the required packages.") {|val| opts[:dumpInfos] = val}
        parser.on("-o", "--options <option-name=value>", String, "Pass extra options to an environment.") {|val| opts[:envOpts] << val}
        parser.on("-k", "--install-dkms", nil, "Install DKMS packages.") {|val| opts[:installDKMS] = true}
        parser.on("-K", "--keep-packages", nil, "Keep downloaded packages at the top of the env.") {|val| opts[:keepPackages] = true}
        parser.on("--do-not-update", nil, "Skip the actual download/extract/install part.") {|val| opts[:doNotUpdate] = true}
        parser.on("--check-git-dependencies", nil, "Check that git dependencies match RPMs" ) {|val| opts[:checkGitDependencies] = true}
        parser.on("--no-dependencies", nil, "Only check the selected env type and not its dependencies") {|val| opts[:no_deps] = true }

        WorkEnvs::versionSelectorPrepare(opts, parser)
        WorkEnvs::configSelectorPrepare(opts, parser)
        parser.separator ""

        WorkEnvs::listEnvTypes.each(){|name, envClass|
            sub_opts = []

            begin
                sub_opts = WorkEnvs::getOptions(envClass)
            rescue
            end

            next if sub_opts.length == 0
            if envClass == WorkEnvs::BasicEnv then
                parser.separator "Supported options for any environment:"
            else
                parser.separator "Supported options for environment of type '#{WorkEnvs::getEnvType(envClass)}':"
            end
            sub_opts.each(){|str|
                parser.separator str
            }
        }
      end
    end

    # Perform command-line options checks and final configuration
    def self.check_opts(opts)
      case opts[:action]
      when :clean, :create, :query, :rename, :rm, :update
        # These all run the final config selector
        WorkEnvs::configSelectorFinal(opts)
      end

      case opts[:action]
      when :clean, :create, :rename, :rm
        if opts[:name] == nil
          raise WorkEnvs::RunError.new(1, "No name provided")
        end
      end

      case opts[:action]
      when :rename
        if opts[:newname] == nil
          raise WorkEnvs::RunError.new(1, "No new name provided")
        end
      end
    end

    # 1. Action: check
    def check(opts)
      curEnv = WorkEnvs::getCurrentEnv()
      return 1 if curEnv == nil
      curEnv.checkEnv(curEnv.versions)
      return 0
    end

    # 2. Action: clean
    def clean(opts)
      name = WorkEnvs::nameToEnvName(opts[:name])

      if WorkEnvs::getCurrentEnvName() == name
        log(:ERROR, "You are actually using '#{name}'. You cannot clean your current environment")
        return 1
      end
      if WorkEnvs::settings[:global][:confirm_delete] != false
        WorkEnvs::Confirm.new("Are you sure you want to clean '#{opts[:name]}' ?")
        WorkEnvs::Confirm.new("Are you really really really sure you want to clean '#{opts[:name]}' ?")
      end

      env = WorkEnvs::getEnv(name)
      env.cleanup()
      log(:INFO, "Environment '#{opts[:name]}' successfully cleaned")
      return 0
    end

    # 3. Action: config
    def config(opts)
      if opts[:show] != nil then
        path = opts[:show].split("/")
        entry = WorkEnvs::settings()
        while path.length > 0
            d = path.shift
            entry = entry[d.to_sym()]
        end
        begin
            puts entry.join("\n")
        rescue
            puts entry
        end
      end
      return 0
    end

    # 4. Action: create
    def create(opts)
      WorkEnvs::createEnv(opts[:name], opts[:type], nil)
      log(:INFO, "Environment '#{opts[:name]}' successfully created")
      return 0
    end

    # 5. Action: get
    def get(opts)
      curEnv = WorkEnvs::getCurrentEnv()
      return 1 if curEnv == nil

      puts "Current environment stored at: #{WorkEnvs::WORK_ENVS}\n\n"
      puts WorkEnvs::listHeader()
      puts curEnv
      puts "Properties: " + curEnv.properties.to_s
      return 0
    end

    # 6. Action: help
    def help(opts)
      args = opts[:extra_args] || []
      root_dir = File.expand_path('../..', __dir__)
      wenv_man_dir = root_dir + "/man"

      if args.length != 1 then
        if File.exist?(wenv_man_dir + "/man7/wenv.7") then
          system("man " + wenv_man_dir + "/man7/wenv.7") or return 1
          return 0
        else
          return 1
        end
      end

      commands = WorkEnvs.getActionAttr("ACTION_LIST").map { |x| WorkEnvs.actionToString(x) }

      name = args.shift
      if commands.index(name) == nil then
        found = 0
        full_name = ""
        commands.each(){|cmd|
          next if cmd !~ /^#{name}/
          found += 1
          full_name = cmd
        }
        if found != 1 then
          log(:ERROR, "No such action '#{name}'")
          raise WorkEnvs::RunError.new(1, "No such command")
        else
          name = full_name
        end
      end

      if File.exist?(wenv_man_dir + "/man1/wenv-" + name + ".1")
        system("man " + wenv_man_dir + "/man1/wenv-" + name + ".1") or return 1
      else
        system("ruby " + root_dir + "/wenv " + name + " --help") or return 1
      end
      return 0
    end

    # 7. Action: list
    def list(opts)
      envs = WorkEnvs::getEnvs()
      if opts[:listType] != :name then
          puts "Environments stored at:\n"
          WorkEnvs::getDirList().each{|label, dirpath|
              puts " - #{label} => #{dirpath}"
          }
          puts "\n"
      end
      if envs.length == 0 then
          puts "No environments"
      else
          puts WorkEnvs::listHeader() if opts[:listType] != :name
          envs.each(){|env|
              puts env.to_s(opts[:listType])
          }
      end
      return 0
    end

    # 8. Action: package_lookup
    def package_lookup(opts)
      if opts[:package] != nil then
          if opts[:type] != nil then
              packages = WorkEnvs::listAllPackages(WorkEnvs::stringToEnvClass(opts[:type]))
              if packages.index(opts[:package]) != nil then
                  puts "Env '#{opts[:type]}' contains package '#{opts[:package]}'"
                  return 0
              else
                  puts "Env '#{opts[:type]}' does contains package '#{opts[:package]}'"
                  return 1
              end
          else
              types = WorkEnvs::listEnvTypes()
              containsList=[]
              containsHash={}
              types.each() {|label, envClass|
                  packages = WorkEnvs::listAllPackages(envClass)
                  index = nil
                  if (opts[:regex]) then
                      index = packages.index(){|e| e =~ /#{opts[:package]}/}
                      next if index == nil

                      containsHash[packages[index]] = [] if containsHash[packages[index]] == nil
                      containsHash[packages[index]] << label
                  else
                      index = packages.index(opts[:package])
                      containsList << label if index != nil
                  end
              }
              if containsList.length == 0 && containsHash.length == 0 then
                  puts "Package '#{opts[:package]}' does not belong to any environment"
                  return 1
              else
                  if (opts[:regex]) then
                      containsHash.each(){|p, envs|
                          puts "Package '#{p}' matching regexp belongs to environments:"
                          puts " - " + envs.join("\n - ")
                      }
                  else
                      puts "Package '#{opts[:package]}' belongs to environments:"
                      puts containsList.join("\n")
                  end
              end
          end
      else
          packages = WorkEnvs::listAllPackages(WorkEnvs::stringToEnvClass(opts[:type]))
          puts packages.join("\n")
      end
      return 0
    end

    # 9. Action: query
    def query(opts)
      if opts[:settings][:control][:rSettings] != nil then
          rOpts = opts[:settings][:control][:rSettings][:opts]
          opts[:raw] = true
          opts[:infos] = rOpts[:infos]
          opts[:infos_extra] = rOpts[:infos_extra]
          opts[:type] = rOpts[:type]
          opts[:release] = rOpts[:release]
          opts[:envOpts] = rOpts[:envOpts]
          opts[:no_deps] = rOpts[:no_deps]
      end

      env = WorkEnvs::instantiateEnv("QUERY_____", opts[:type], nil, opts[:release])

      WorkEnvs::versionSelectorFinal(opts, env)

      if opts[:infos].empty? then
          if opts[:ignore_empty] == true then
              puts "INFO: No matching packages found"
              return 0
          else
              raise WorkEnvs::RunError.new(1, "Error: No version, sha1, or sub env provided")
          end
      end

      filelist = nil
      temp_list = nil

      if opts[:raw] != false then
          downloader, packages, temp_packages = env.get_dependencies_raw(opts)
          packages.each(){|p| p.path = nil }
          temp_packages.each(){|p| p.path = nil }
          puts WorkEnvs::serialize({:packages => packages, :temp_packages => temp_packages})
          return 0
      end

      if opts[:showEnvironments] == true then
          puts "==========================================================="
          puts "Requested environments"
          puts opts[:infos].to_s
          puts "==========================================================="
      end
      filelist, temp_list = env.get_dependencies(opts)
      filelist.sort!
      temp_list.sort!

      puts "\n\nRequired packages:"
      filelist.each(){|pack|
          puts pack.path
      }
      if opts[:envOpts][WorkEnvs::WENV_OPTS_EXTERNAL] != "true" then
          puts "\n\nExtra packages:"
          temp_list.each(){|pack|
              puts pack.path
          }
      end

      if opts[:download] != false then
          downloader = WorkEnvs::PackageDownloader.new()
          downloader.be_silent = !WorkEnvs::VERBOSE
          lastChoice = false
          opts[:download] = "." if opts[:download] == nil || opts[:download] == ""
          puts "Downloading selected RPMS to #{opts[:download]}"
          if ! File.directory?(opts[:download]) then
              Dir.mkdir(opts[:download])
          end
          curDir = Dir.pwd()
          Dir.chdir(opts[:download])
          list = filelist
          list += temp_list if opts[:envOpts][WorkEnvs::WENV_OPTS_EXTERNAL] != "true"
          tName=runCmd("mktemp", !WorkEnvs::VERBOSE)
          runCmd("rm -f #{tName}", !WorkEnvs::VERBOSE)
          list.each(){|pack|
              fName = File.basename(pack.path)
              if File.exist?(fName) then
                  lastChoice = WorkEnvs::OverWrite.check("File #{fName} already exists. Do you want to overwrite it?:", lastChoice)
                  next if lastChoice == false
                  File.delete(fName)
              end
              downloader.download(pack, tName)
              runCmd("mv -Z #{tName} #{File.basename(pack.path)} || mv #{tName} #{File.basename(pack.path)}", !WorkEnvs::VERBOSE)
          }
          if opts[:createRepo] == true then
              arch = WorkEnvs::PackageDownloader.getArch()
              raise("Target machine is not RHEL based. Cannot create a repo") if arch[:base] != "RHEL"
              puts "Creating repository in #{opts[:download]}"
              runCmd("createrepo #{opts[:download]}", !WorkEnvs::VERBOSE)
          end
      end
      return 0
    end

    # 10. Action: rename
    def rename(opts)
      if !WorkEnvs::isEnv?(opts[:name])
         log(:ERROR, "'#{opts[:name]} is not a valid environment")
         return 1
      end
      if WorkEnvs::getCurrentEnvName() == opts[:name]
          log(:ERROR, "You are actually using '#{opts[:name]}'. You cannot rename your current environment")
          return 1
      end

      env = WorkEnvs::getEnv(opts[:name])
      env.rename(opts[:newname])
      log(:INFO, "Environment '#{opts[:name]}' successfully renamed")
      return 0
    end

    # 11. Action: rm
    def rm(opts)
      if !WorkEnvs::isEnv?(opts[:name])
         log(:ERROR, "'#{opts[:name]}' is not a valid environment")
         return 1
      end
      if WorkEnvs::getCurrentEnvName() == opts[:name]
          log(:ERROR, "You are actually using '#{opts[:name]}'. You cannot delete your current environment")
          return 1
      end
      if WorkEnvs::settings[:global][:confirm_delete] != false
          WorkEnvs::Confirm.new("Are you sure you want to delete '#{opts[:name]}' ?")
          WorkEnvs::Confirm.new("Are you really really really sure you want to delete '#{opts[:name]}' ?")
      end

      WorkEnvs::deleteEnv(opts[:name])
      log(:INFO, "Environment '#{opts[:name]}' successfully deleted")
      return 0
    end

    # 12. Action: switch
    def switch(opts)
      args = opts[:extra_args] || []
      envName = opts[:name]

      if envName.to_s == ""
          if args.length == 0
            raise WorkEnvs::RunError.new(1, "No environment name provided")
          end
          envName = args[0]
          args.shift
      end

      envName = WorkEnvs::nameToEnvName(envName)

      if WorkEnvs::getCurrentEnvName() == envName
          log(:ERROR, "You are already in this environment")
          return 1
      end

      if !WorkEnvs::isSwitchable?(envName)
          log(:ERROR, "Cannot switch to an uninitialized environment")
          return 1
      end
      env = WorkEnvs::getEnv(envName)

      cmd = ""
      if args.length > 0 then
          cmd = "-c " + "'" + 0.upto(args.length - 1).map(){|x| "$#{x}"}.join(" ") + "' '"+
                + args.join("' '") + "'"
      end

      switchEnvFile = env.genPath() +"/" + WorkEnvs::ENV_SWITCH
      env.genSwitchEnvScript()

      exec_cmd = "BASH_ENV=\"#{switchEnvFile}\" bash --rcfile #{switchEnvFile} #{cmd}"
      exec(exec_cmd)
    end

    # 13. Action: test
    def test(opts)
      opts[:name] = WorkEnvs::nameToEnvName(opts[:name])
      env = WorkEnvs::getEnv(opts[:name])

      raise WorkEnvs::EnvNoTypeErrorException if opts[:type].to_s == ""

      envClass = WorkEnvs::stringToEnvClass(opts[:type])
      raise("Environment has type '#{env.type}', expected '#{WorkEnvs::getEnvType(envClass)}'") if ! (envClass === env)

      puts "Environment has type '#{env.type}'"
      return 0
    end

    # 14. Action: update
    def update(opts)
      opts[:name] = WorkEnvs::nameToEnvName(opts[:name])
      env = WorkEnvs::getEnv(opts[:name])

      WorkEnvs::versionSelectorFinal(opts, env)

      opts[:ignore_empty] = true if env.isDev?()

      if opts[:infos].empty? then
          if opts[:ignore_empty] == true then
              puts "INFO: No matching packages found"
              return 0 if !env.isDev?()
          else
              raise WorkEnvs::RunError.new(1, "Error: No version, sha1, or sub env provided")
          end
      end

      ret = env.update(opts)

      if ret == true
          puts "Environment '#{opts[:name]}' successfully updated"
      else
          puts "Environment '#{opts[:name]}' looks already up-to-date. Use --force to force an env update."
      end

      if opts[:dumpInfos] != nil then
          f = File.open(opts[:dumpInfos], "w+")
          f.puts opts[:infos]
          f.close()
          dir = File.dirname(opts[:dumpInfos])

          puts "==========================================================="
          puts "Extras dependencies provided but not checkout :"
          puts opts[:infos_extra].to_s
          puts "==========================================================="
          opts[:infos_extra].concat(opts[:infos])

          if WorkEnvs::VERBOSE then
              puts "==========================================================="
              puts "Complete dependencies: Checkouted + extra:"
              puts opts[:infos_extra].to_s
              puts "==========================================================="
          end

          opts[:infos_extra].each(){|name, value|
              tClass = WorkEnvs::symbolToClass(name)
              revFile = WorkEnvs::getRevFile(tClass)
              next if revFile.to_s == ""
              revFile.gsub!(/_revision$/, '_version.txt')
              f = File.open(dir + '/' + revFile, "w+")
              f.puts value[:version]
              f.close
          }
      end
      return 0
    end
  end
end
