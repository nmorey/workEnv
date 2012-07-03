# -*- coding: utf-8 -*-
require 'yaml'
require 'pathname'
require 'thread'
require 'base64'
# User overridable defines


module WorkEnvs
    # User login
    USERNAME=`whoami`.chomp()

    # Defautl directory to put envs to
    WORK_ENVS=(ENV["WORK_ENVS"] != nil && ENV["WORK_ENVS"] != "") ?
                    ENV["WORK_ENVS"] : "/work1/#{USERNAME}/work-envs"

    # Name of environment config file (YAML serialized) within the environment directory
    ENV_CONF=".env_config"

    # Name of the script to switch into an end
    ENV_SWITCH=".switch_env"

    # Default expiration date for licenses
    DEFAULT_EXPIRATION_DATE="12/31/2025"

    # Version of the #Core and #WorkEnv object used for migration
    WORK_ENV_VERSION = 10

    # Core Env class
    # This is not actually an env but all the methods Env needs to inherit through the WorkEnv class
    # that provide global services accross the env graph
    class Core
        #
        # WEIRD Methods. Object methods used to provide easy access to class methods all the way down
        #

        # Calls getVersion for all the nodes in the env graph
        #
        # Returns a hash containing each env version
        def getVersion(canFail = false)
            versions = {}
            path = self.genPath()
            WorkEnvs::familyTreeApply(self) {|x|
                envType = WorkEnvs::getEnvType(x)
                begin
                    if !@deps_infos.exists?(envType) then
                        next
                    end
                    versions.merge!(x.getVersion(path, canFail)){|key, v1, v2|
                        raise("Incoherency for version of #{key}. Have both #{v1} and #{v2}")
                    }
                rescue => e
                    versions[envType] = :unitialized
                    raise e if @setup_options[WENV_OPTS_PARTIAL] != "true"
                end
            }
            return versions
        end

        # Calls checkEnv for all the nodes in the env graph that are installed.
        #
        # The goal is to make sure the checkouted files use the expected version
        #
        # Returns if environment valid (if dev or Partial, always valid).
        # Raises an exception if it is not
        def checkEnv(versions = nil)
            #Disable for the moment as this never reported any issues
            return true

            # return if isDev?()
            # path = self.genPath()
            # WorkEnvs::familyTreeApply(self) {|x|
            #     next if versions[WorkEnvs::getEnvType(x)] == nil
            #     begin
            #         x.checkEnv(self, path,versions)
            #     rescue => e
            #         raise e if @setup_options[WENV_OPTS_PARTIAL] != "true"
            #     end
            # }
        end


        #Check that all packages in the DB with this SHA1 are known by workEnvs
        def checkPackages(downloader, revision, objClass)
            allPackages = WorkEnvs::listAllPackagesWithSiblings(objClass)
            availPackages = downloader.queryMatchingSHA1(revision)
            unknownPackages = availPackages - allPackages
            if unknownPackages.length != 0 then
                STDERR.puts "ERROR: #{objClass} -> Found packages registered with SHA1 #{revision} in the DB but not in WorkEnvs."+
                    " Try to update WorkEnvs by running:\n#{WORK_ENV_SCRIPTS_DIR}/wenv --update\n"+
                    "If the problem subsists, someone added a new package in the DB but did not register it in the WorkEnvs\n"+
                    "Find him and slap him repeatedly with a trout until he fixes it....\n"+
                    "Unknown packages are:"
                unknownPackages.each(){|p|
                    package = downloader.queryPackage(p, revision, true)
                    STDERR.puts"\t#{p} => #{package.pack}"
                }
                exit(1) if ENV["WENV_IGNORE_ERRORS"] == nil
            end
        end

        # Analyze the packages from a sub env and look for dependy to other sub envs
        #
        # - classDeps is a list of the sub env class depency description
        # - familyTree is a list of all sub env class that are parents to self
        # - packages is a list of all the available packages provided by this sub env class
        #   for this version
        # - info is the Depencies object used during dependcy computation
        #
        # Used only by genPath
        #
        # Throws EmptyQueryException if a dependency to a parent sub class could not be fulfilled
        #  or mismatch and existing one.
        def lookupDependencies(downloader, classDeps, familyTree, packages, infos)
            packages.each(){|pack|
                # Match all packages against regexps
                dependencies = nil
                classDeps.each(){|regexp, deps|
                    if pack.to_s =~ regexp then
                        #Generate dependencies
                        dependencies = downloader.listDependencies(pack) if dependencies == nil
                        deps.each(){|depTypes, depList|
                            depTypes = [ depTypes ] if ! depTypes.kind_of? Array
                            depClasses = depTypes.map(){|depType| WorkEnvs::symbolToClass(depType)}
                            # There may only be one element not as an array so self wrap it
                            if(depList.kind_of? String) then
                                depList = [ depList ]
                            end
                            depList.each(){|dep_name|
                                dep_ver = downloader.extractDependency(dependencies, dep_name)
                                next if dep_ver == nil
                                success = false
                                depClasses.each(){|depClass|
                                    if familyTree.index(depClass) == nil then
                                        STDERR.puts "DEV WARNING: Found requested dependency from #{pack} to"+
                                                    " #{dep_name} (#{depClass}) (#{dep_ver}) " +
                                                    "but environment #{depClass} is not a valid ancestor"
                                    end
                                    begin
                                        infos.push_version(depClass, dep_ver)
                                        success = true
                                    rescue EmptyQueryException
                                    end
                                }
                                if success == false then
                                    STDERR.puts "WARNING: Package #{pack} has dependencies to any of those "+
                                                "env (#{depClasses}), but no matching packages were found"
                                end
                            }
                        }
                    end
                }
            }
        end
        private :lookupDependencies

        # Generate a list of all the packages (including temporary) that should
        # be downloaded and extracted in the env.
        #
        # This looks at the dependencies both in the options (--sha1, --version, --rev-files, etc)
        # and the dependencies from the packages while adding them to the list.
        #
        # It will iterate on all the env dependency tree (except if opts[:no_deps] is true)
        # to generate a complete list.
        #
        # It returns two arrays:
        # - an array of Package object containg all the permanent packages
        # - an array of temporary Package object that might be needed furing the post_setup phase
        def genPackages(downloader, opts)
            packages = []
            temp_packages = []
            infos = opts[:infos]

            settings = WorkEnvs::settings()

            #In case of RPC chaining, check the previous one to make sure we won't loop
            prev_rpc_host=""
            begin
                prev_rpc_host = opts[:settings][:control][:rSettings][:settings][:db][:rpc_host]
            rescue => e
                # Ignore errors
            end
            # Try to do it remotely but do not recurse infinitely
            if settings[:db][:rpc_host] != nil && prev_rpc_host != settings[:db][:rpc_host] then
                msgs = nil
                host = settings[:db][:rpc_host]
                begin
                    rOpts={}
                    rOpts[:settings] = WorkEnvs::settings()
                    rOpts[:opts] = opts

                    # Force type when used with wenv update
                    # Wenv query has already set this but it's
                    # the same value as @type
                    rOpts[:opts][:type] = @type
                    objs, msgs = WorkEnvs::remoteRun(host, "query",
                                                       ' -R "' + WorkEnvs::serialize(rOpts) + '"')
                    hash = objs[0]
                    packages = hash[:packages]
                    temp_packages = hash[:temp_packages]
                    puts "INFO: Computed dependencies remotely on #{host}"
                    puts msgs
                    return packages, temp_packages
                rescue => e
                    #Fail, fall back to original mode
                    puts "INFO: Fail to resolve depencies remotely. Running locally (#{e.to_s})"
                end
            end

            familyTree = WorkEnvs::familyTreeList(self)

            packageRef={}

            WorkEnvs::familyTreeApply(self, false){|x|
                envType = WorkEnvs::getEnvType(x)
                packName = WorkEnvs::getMainPackage(x)

                # We hit rock bottom or empty env
                next if packName == ""

                # If we allow partial env and have no deps on this package, just skip it
                next if infos.partialEnv == true && !infos.exists?(envType)
                # Find the revision from the dep
                if infos.exists?(envType) then
                    revision = infos.get_sha1(envType)
                    if revision !~ /^[a-f0-9]{40}$/ then
                        raise("Invalid #{WorkEnvs::getMainPackage(x)} version '#{infos.get(envType)}'")
                    end
                else
                    if opts[:shutUp] != true && !x.isDev?() && opts[:no_deps] != true then
                        puts "WARNING: Found no dependency to #{envType.to_s}. Skipping..."
                    end
                    next
                end

                classPackages = WorkEnvs::getPackages(x)
                classDeps = WorkEnvs::getDependencies(x)
                classDeps = {} if opts[:no_deps] == true

                # First let us check that we know of every package registered with this SHA1 in the db
                # This is just for sanity
                checkPackages(downloader, revision, x)

                WorkEnvs::dputs("Looking at #{envType} packages:")
                isExternal = (opts[:envOpts] != nil && opts[:envOpts][WENV_OPTS_EXTERNAL].to_s == "true") ? true : false
                # Get required external (and internal if enabled) list of packages
                required = classPackages[:external][:required] + (isExternal ? [] : classPackages[:internal][:required])
                # Get extra external (and internal if enabled) list of packages
                # Extra means it's OK if not available
                extras = classPackages[:external][:extras] + (isExternal ? [] : classPackages[:internal][:extras])

                # Generate the list of truly available package and their full package name
                # for both required and extras, and both permanent and temporary
                local_packages = downloader.getPackagesName(required, extras, revision)
                local_temp_packages = downloader.getPackagesName(classPackages[:temporary][:required],
                                                                 classPackages[:temporary][:extras], revision)

                all_packages = local_packages + local_temp_packages
                if isExternal
                    # Still check the internal packages for dependencies
                    all_packages += downloader.getPackagesName(classPackages[:internal][:required],
                                                               classPackages[:internal][:extras], revision)
                end

                if opts[:skipDeps] != true then
                    # Check in the package list we generated if there are RPM/Deb
                    # dependencies that matches env Class description.
                    # This is how dependencies are propagated when working only with package
                    # and without any rev_file/sub-sha1 options
                    lookupDependencies(downloader, classDeps, familyTree, all_packages, infos)
                end


                # Sanity checks to make sure there are never two sub envs that pull the same package
                # in two different version
                #
                # packageRef basically store the full name of the packahe
                # If another envs pull sthe exact same one it's OK
                # If it pull the same packahe name but with a different full name (ie different version or
                # due to a weird rebuild after tag changes), let it know and crash
                (local_packages + local_temp_packages).each(){|pack|
                    if packageRef[pack.name] == nil then
                        packageRef[pack.name] = { :pack => pack.pack, :env => x }
                        next
                    end
                    extname = File.extname(pack.pack)
                    next if extname != ".deb" && extname != ".rpm"
                    if packageRef[pack.name][:pack] != pack.pack then
                        raise("Env pulls both #{packageRef[pack.name][:pack]} (#{packageRef[pack.name][:env]}) and "+
                              "#{pack.pack} (#{x}) which are not compatible")
                    end
                }
                packages += local_packages
                temp_packages += local_temp_packages

            }
            packages.uniq!
            temp_packages.uniq!

            checkGitDeps(downloader, infos) if opts[:checkGitDependencies]

            return packages, temp_packages
        end

        # Checks that dependencies extracted from the packages math the Git dependencies.
        def checkGitDeps(downloader, infos)
            git_repo = WorkEnvs::settings[:db][:git_repo]
            WorkEnvs::familyTreeApply(self){|x|
                envClass = x
                envType = WorkEnvs::getEnvType(x)
                version = infos.get_version(envType)
                next if version == nil

                gitRepo = WorkEnvs::getGitRepo(x).to_s()
                next if gitRepo == ""

                parentList = WorkEnvs::familyTreeListClass(x)

                dInfos = downloader.queryDepInfosFromVersion(x, version, true)
                sha1 = dInfos[:sha1]

                remoteRepo = gitRepo.gsub(/^.*:/, '')
                revFiles = runCmd("ssh #{git_repo} ls-tree #{remoteRepo} #{sha1} -- valid/hudson/rev_files/", !VERBOSE)
                revFiles.split("\n").each(){|revFileLine|
                    cols = revFileLine.split(" ")
                    revFile = File.basename(cols[3])
                    revClasses = WorkEnvs::revFileToClasses(revFile)
                    next if revClasses == nil

                    revClasses.each(){|revClass|
                        revType = WorkEnvs::getEnvType(revClass)
                        # Continue if this is not a parent env...
                        next if parentList.index(revClass) == nil

                        puts "Checking #{envType} => #{revType}"
                        objSha1 = cols[2]
                        revSha1 = runCmd("ssh #{git_repo} cat-file #{remoteRepo} -p #{objSha1}", !VERBOSE)

                        revPack = downloader.queryPackageVersion(WorkEnvs::getMainPackage(revClass), revSha1, false)
                        expected = infos.get_version(revType)

                        #Skip if everything is OK
                        next if expected == revPack && expected.to_s != ""

                        expected = "<N/A>" if expected.to_s == ""
                        revPack = "<???>" if revPack.to_s == ""
                        puts "WARNING: On #{envType} => #{revType}\n" +
                             "\tRPM requires: #{expected} / Rev files requires: #{revPack} (SHA1 = #{revSha1})"
                    }
                }
            }
       end

        # Generate the env specific part of the switch env script
        #
        # Iterates on all the env dependency tree and call the switchEnv method of each class.
        #
        # Note that switchEnv is not called for classes that have not been updated
        # (no dependency to them even if in the dependency tree)
        #
        # Returns an array of commands to be written in the switchEnv script
        def genSwitchEnv()
            path = self.genPath()
            commands=[]
            WorkEnvs::familyTreeApply(self) {|x|
                next if (@deps_infos == nil ||
                         !@deps_infos.exists?(WorkEnvs::getEnvType(x))) && !x.isDev?() && !self.isDev?()
                begin
                    ret = x.switchEnv(self, "${WORK_ENV_PATH}")
                    commands = [ "##{x.to_s}" ] + ret + [ "" ] + commands
                rescue => e
                    raise e if @setup_options[WENV_OPTS_PARTIAL] != "true"
                end
            }
            return commands
        end

        # Default footer commands to output in the switch env script.
        #
        # - Autoload workEnv bash completion
        # - Load global workEnv bashrc if it exists
        # - Load env specific bashrc if it exists
        # - Check Env coherency
        def genEnvFooter()
            array = []
            array << "#Env Footer"
            array << "[ -f ${WORK_ENV_SCRIPTS_DIR}/workrc-completion.sh ] && source ${WORK_ENV_SCRIPTS_DIR}/workrc-completion.sh"
            array << "[ -f #{WORK_ENV_GLOBAL_DIR}/bashrcs/.bashrc ] && source #{WORK_ENV_GLOBAL_DIR}/bashrcs/.bashrc"
            array << "[ -f #{WORK_ENV_GLOBAL_DIR}/bashrcs/${WORK_ENV_CURRENT} ] && source #{WORK_ENV_GLOBAL_DIR}/bashrcs/${WORK_ENV_CURRENT}"
            array << "if [ -f $WORK_ENV_SCRIPTS_DIR/checkEnv ]; then ruby $WORK_ENV_SCRIPTS_DIR/checkEnv || exit 1; fi"
            return array
        end

        # Top level function to generate a switchEnv script.
        #
        # Call #genSwitchEnv and #genEnvFooter then dumps the strings to the appropriate file
        def genSwitchEnvScript()
            cmds = genSwitchEnv() +
                   genEnvFooter()
            output = File.open(self.genPath() + "/" + ENV_SWITCH, "w")
            cmds.each(){|x|
                output.puts x
            }
            output.close()
        end

        # Call the pre_setup method for each envClass
        #
        # Iterates on all the env dependency tree and calls the pre_setup method.
        # Method is not called for dev env classes nor for uninitialized env classes
        def pre_setup(opts, packages, temp_packages)
            #Pre-setup in reverse order so we start from the trunk and install inherited env first
            WorkEnvs::familyTreeApply(self, true){|x|
                next if !@deps_infos.exists?(WorkEnvs::getEnvType(x)) && !x.isDev?()
                next if x.singleton_methods().index(:pre_setup) == nil
                x.pre_setup(opts, packages, temp_packages)
            }
        end

        # Call the post_setup method for each envClass
        #
        # Iterates on all the env dependency tree and calls the post_setup method.
        # Method is not called for dev env classes nor for uninitialized env classes
        def post_setup(opts = {})
            #Post setup in reverse order so we start from the trunk and install inherited env first
            WorkEnvs::familyTreeApply(self, true){|x|
                next if !@deps_infos.exists?(WorkEnvs::getEnvType(x)) && !x.isDev?()
                next if x.singleton_methods().index(:post_setup) == nil
                x.post_setup(opts)
            }
            genSwitchEnvScript()
        end

        # Call the pre_install method for each envClass
        #
        # Iterates on all the env dependency tree and calls the pre_install method.
        # Method is not called for dev env classes nor for uninitialized env classes
        def pre_install(opts, packages, temp_packages)
            #Pre Install in reverse order so we start from the trunk and install inherited env first
            WorkEnvs::familyTreeApply(self, true){|x|
                next if !@deps_infos.exists?(WorkEnvs::getEnvType(x)) && !x.isDev?()
                next if x.singleton_methods().index(:pre_install) == nil
                x.pre_install(opts, packages, temp_packages)
            }
        end

        # Call the post_install method for each envClass
        #
        # Iterates on all the env dependency tree and calls the post_install method.
        # Method is not called for dev env classes nor for uninitialized env classes
        def post_install(opts, packages, temp_packages)
            #Post Install in reverse order so we start from the trunk and install inherited env first
            WorkEnvs::familyTreeApply(self, true){|x|
                next if !@deps_infos.exists?(WorkEnvs::getEnvType(x)) && !x.isDev?()
                next if x.singleton_methods().index(:post_install) == nil
                x.post_install(opts, packages, temp_packages)
            }
        end

        #
        # COMMON Methods. Same for all types of env.
        #

        # Return a if env has a dev type
        #
        # Dev env do not neet to be initialized to be switched to
        def isDev?()
            return self.class.isDev?()
        end

        # Rename an env
        #
        # Move the env directory and update the object name proprery
        def rename(name)
            raise("Cannot rename an environment with the same name...") if name == WorkEnvs::labelNameToStr(@label, @name)
            raise("An environment named '#{name}' already exists") if WorkEnvs::existsEnv?(name)
            label, name = WorkEnvs::strToLabelName(name)
            runCmd("mv #{genPath()} "+
                   "   #{WorkEnvs::getDirPathFromLabel(label)}/#{name}")
            @name = name
            @label = label
            self.dump()
        end

        # Returns if the env can be switched to (env is initialized)
        def isSwitchable?()
            return true if @deps_infos != nil && @deps_infos.partialEnv == true

            @versions.each() {|name, version|
                if version == :uninitialized then
                    return false
                end
            }
            return true
        end

        # Check that at least one version/SHA1 was required in the options
        def check_version(opts = {})
            downloader = get_downloader()
            project = WorkEnvs::getMainPackage(self)
            if opts[:version] != nil || opts[:sha1] != nil then
                return downloader, opts[:infos].get_sha1(name)
            elsif opts[:infos] != nil && !opts[:infos].empty?
                return downloader, nil
            else
                raise("Neither version or SHA1 provided")
            end
        end

        # Return a string with the patch to the environment directory
        def genPath()
            path = WorkEnvs::getDirPathFromLabel(@label) + "/" + @name
        end

        # Backup the environment config in its workspace
        #
        # This serializes the env as a YAML object into the environment directory
        def dump()

            raise("No path for environment") if @name.to_s() == ""


            desc = File.open(genPath() + "/" + ENV_CONF, "w+")

            label = @label
            @label = nil
            desc.puts self.to_yaml()
            desc.close()
            @label = label
        end

        # Returns a string that describe the env
        #
        # - lType == :name
        #   - name
        # - lType == :short
        #   - name
        #   - type
        #   - machine
        #   - expiration
        # - lType == :long
        #   - name
        #   - type
        #   - machine
        #   - expiration
        #   - versions info
        #   - setup options
        def to_s(lType = :long)
            lType = :long if lType == nil
            case lType
            when :short, :long
                # Convert an environment to string so they can be printed
                maxLen = WorkEnvs::getEnvNames().inject(0){|x, y| x > y.length ? x : y.length}
                _versions = @versions
                prefix=""
                type = @type.to_s
                name = WorkEnvs::labelNameToStr(@label, @name)
                str = "* " +name.ljust(maxLen) + type.center(20) +  @machine.to_s.center(15) + @expiration.to_s.center(15)

                sub_shift = "".ljust(maxLen+20+15+15+5)

                if lType == :long then
                    str+= "\t{"
                    _versions.each(){|key, val|
                        str += prefix +" :" + key.to_s + " => " + val.to_s + ""
                        prefix = "\n" + sub_shift + "\t "
                    }
                    str += " }"
                    if @setup_options != nil && @setup_options.empty? == false then
                        str+= "\n" + sub_shift + "\t{ "
                        comma = ""
                        @setup_options.each(){|name, val|
                            str += comma + name + "=" + val
                            comma = ", "
                        }
                        str += " }"
                    end
                end
                return str
            when :name
                str =  WorkEnvs::labelNameToStr(@label, @name)
                return str
            else
                raise("Unknown listing type #{lType}")
            end
        end

        # List the latest top packages from the env type
        #
        # Query the latest limit packages defining this env (from the branch branch if non nil)
        #
        # Returns an array of EnvPackage
        def getPackages(downloader, branch=nil, limit=100000)
            branch='%' if branch.nil? || branch.length == 0

            limit = 100000 if limit == 0
            packages = downloader.queryPackages(WorkEnvs::getMainPackage(self), branch,
                                                limit, WorkEnvs::getBlackList(self))
            return packages
        end

        # Call getPackages and display the results on STDOUT
        def listPackages(downloader, quantity, branch=nil)
            puts "Getting package list..."
            packages = getPackages(downloader, branch, quantity)
            (packages.length - 1).downto(0){|x|
                elnt = packages[x]
                puts elnt
            }
        end

        # Create a PackageDownloader with settings matching this env
        def get_downloader(opts={})
            machine = @machine
            tables = @db_tables
            begin
                if opts[:settings][:arch][:machine] != nil then
                    arch = WorkEnvs::getArch(opts[:settings][:arch][:machine])

                    puts "INFO: Overriding environment arch with '#{arch[:label]}'" if machine != arch[:label]
                    machine =  arch[:label]
                end
            rescue
                   # Probably no settings available
            end
            begin
                if opts[:settings][:db][:package_default_table] != nil then
                    new_table =  DBInterface::toTable(opts[:settings][:db][:package_default_table])

                    puts "INFO: Overriding environment table with '#{new_table}'" if tables != new_table
                    tables =  new_table
                end
            rescue
                   # Probably no settings available
            end
            return WorkEnvs::PackageDownloader.new(machine, tables, !VERBOSE)
        end

        # Wrapper around genPackages
        #
        # Basically calls genPackages with a few extra checks.
        #
        # This is mostly use for get_dependencies or by queryEnv to generate raw object
        # when using the RPC mode to solve dependencies
        #
        # Returns:
        # - PackageDownloaded used to call genPackages
        # - an array of permanent Package
        # - an array of temporary Package
        def get_dependencies_raw(opts={})
            downloader, package_sha1 = check_version(opts)

            # Check package server is up
            downloader.checkRepo()

            packages = []
            temp_packages = []
            packages, temp_packages = genPackages(downloader, opts)

            packages.uniq!
            temp_packages.uniq!
            return downloader, packages, temp_packages
        end

        # Wrapper around get_dependencies_raw
        #
        # Calls get_dependencies_raw but convert the Package list to path to the packages
        #
        # Used by queryEnv to generate a list of URL to the package to download
        # Returns:
        # - PackageDownloaded used to call genPackages
        # - an array of permanent package paths (String)
        # - an array of temporary package paths (String)
        def get_dependencies(opts = {})
            downloader, packages, temp_packages = get_dependencies_raw(opts)
            packages.each(){|p| downloader.getPackagePath(p)}
            temp_packages.each(){|p| downloader.getPackagePath(p)}
            return packages, temp_packages
        end

        # Download and extract the packages listed in packages AND temp_packages.
        #
        # temp_packages are extracted in a temporary dir.
        # The dirpath will be stored in opts[:tempDir]
        #
        # The function returns an array of all the downloaded/extracted package that need to
        #   be install on the system. This is done by checking install package
        #   flags and DKMS options
        def download_extract(downloader, opts, packages, temp_packages)
           puts "Downloading and installing packages:"

            # Check package server is up
            downloader.checkRepo()

            package_to_be_installed=[]

            if WorkEnvs::settings[:db][:unthreaded] == false
                semaphore = Mutex.new
                threads = []
                begin
                    processorCount = `cat /proc/cpuinfo  2> /dev/null  | grep processor | wc -l`.chomp().to_i() / 2
                    processorCount = 1 if processorCount < 1
                rescue
                    processorCount = 4
                end
                1.upto(processorCount) {
                    threads << Thread.new {
                        while true do
                            pack = nil
                            semaphore.synchronize {
                                pack = packages.pop()
                            }
                            break if pack == nil
                            downloader.downloadAndExtract(pack, true, !pack.shouldKeep(opts))
                            if pack.shouldInstall(opts) then
                                semaphore.synchronize {
                                    package_to_be_installed << pack
                                }
                            end

                        end
                    }
                }
                threads.each(){|thr| thr.join}
            else
                packages.each() {|pack|
                    downloader.downloadAndExtract(pack, true, !pack.shouldKeep(opts))
                    if pack.shouldInstall(opts) then
                        package_to_be_installed << pack
                    end
                }
            end

            opts[:tempDir] = create_tmp_dir()
            puts "Downloading and installing temporary packages (To be removed post-install):"
            Dir.chdir(opts[:tempDir])
            temp_packages.each() {|pack|
                downloader.downloadAndExtract(pack, true, true)
            }
            Dir.chdir(opts[:dir])

            return package_to_be_installed
        end

        # Cleanup and env
        #
        # Remove all files from the env and mark it as uninitialized.
        # This also calls the cleanup method from the env Class tree.
        def cleanup(opts)
            path=genPath()
            #Cleanup in  order

            WorkEnvs::familyTreeApply(self){|x|
                next if x.singleton_methods().index(:cleanup) == nil
                x.cleanup(opts)
            }

          #Deconfigure previous package to be sure
            @versions.each(){|name, val|
                @versions[name] = :uninitialized
            }
            @deps_infos = nil
            @properties = {}
            self.dump()

            runCmd("chmod -R +w #{path}", !VERBOSE)
            # Remove previous checkout
            runCmd("rm -f #{path}/*.rpm #{path}/*.deb", !VERBOSE)
            runCmd("rm -Rf #{path}/usr", !VERBOSE)
            runCmd("rm -Rf #{path}/lib", !VERBOSE)
            runCmd("rm -Rf #{path}/etc", !VERBOSE)
            runCmd("rm -Rf #{path}/mppa", !VERBOSE)
            runCmd("rm -Rf #{path}/*", !VERBOSE)
        end

        #
        # Update configure and install a new envs
        #
        # Update phases are:
        #  - Generate package list
        #  - CLEANUP:
        #    - Cleanup per Env
        #    - Cleanup env globally (reset class and remove all files)
        #
        #  - PRE_SETUP: Call pre_setup per Env
        #  - SETUP: Download and extract all packages
        #  - PRE_INSTALL: Call pre_install per Env
        #  - INSTALL: (yum install) all packages required (DKMS, etc.)
        #  - POST_SETUP:
        #    - Call post_setup per Env
        #    - Generate switch env script
        #  - Update the class and save to disk
        def update(opts = {})
            opts[:endDate] = DEFAULT_EXPIRATION_DATE if opts[:endDate] == nil
            opts[:release] = @db_tables.join(":")


            opts[:srcDir] = Dir.pwd()
            opts[:self] = self

            # Checkout a new set of packages in the environment workspace
            path=genPath()
            opts[:dir] = path

            raise("Nothing to update") if (opts[:infos] == nil || opts[:infos].empty?) && !isDev?()
            infos = opts[:infos]

            if isDev?() then
                puts "INFO: Updating a development environment"
            end

            downloader = get_downloader(opts)

            puts "==========================================================="
            puts "Update requested with these environments:"
            puts infos.to_s
            puts "==========================================================="
            puts "Looking for their dependencies....."

            prevOptions = @setup_options

            @setup_options = opts[:envOpts]
            #If we had hudson specs and no version for our current env, allow partial stuff
            if infos.partialEnv != false && !infos.exists?(WorkEnvs::getEnvType(self))
                @setup_options[WENV_OPTS_PARTIAL] = "true"
            end
            infos.partialEnv = true if @setup_options[WENV_OPTS_PARTIAL] == "true"

            packages, temp_packages = genPackages(downloader, opts)

            puts "==========================================================="
            puts "Installing these requested environments (pulled by dependency):"
            puts "Dependencies:\n"
            puts infos.to_s
            puts "==========================================================="

            do_cleanup = true
            do_setup = true
            do_install = true


            if !isDev?() && infos == @deps_infos && prevOptions == opts[:envOpts] &&
                    !(opts[:force_update] == true ||
                      (opts[:force_update_if_not_const] == true && opts[:envOpts][WENV_OPTS_CONST].to_s != "true"))
                # Be lazy and check if we really need to update
                # When true, this means that all the proper packages are already extracted. We just
                # need to force the reinstallation of installPackages
                do_cleanup = false
                do_setup = false
            end
            if opts[:doNotUpdate] == true then
                do_cleanup = false
                do_setup = false
            end

            if do_cleanup then
                # CLEANUP
                cleanup(opts)
            end

            Dir.chdir(opts[:dir])
            install_deps = nil
            @deps_infos = YAMLLoad(infos.to_yaml())
            @deps_infos.downloader = nil

            # PRE SETUP
            pre_setup(opts, packages, temp_packages)

            # Save package list in opts.
            opts[:packages] = []
            (packages | temp_packages).each do |package|
              opts[:packages].push package
            end

            # If we only want install packages, filter out all the unneeded ones
            if !do_setup then
                alt_pack = []

                packages.each() {|pack|
                    alt_pack << pack if pack.shouldInstall(opts)
                }
                packages = alt_pack
                temp_packages = []
            end

            # SETUP
            install_deps, packages_to_install =
                          download_extract(downloader, opts, packages, temp_packages)


            # INSTALL
            if do_install && !packages_to_install.empty? then
                pre_install(opts, packages, temp_packages)
                downloader.installPackages(packages_to_install)
                post_install(opts, packages, temp_packages)
           end

            # POST SETUP
            if do_setup then
                post_setup(opts)
            end

            Dir.chdir(opts[:srcDir])
            runCmd("rm -Rf #{opts[:tempDir]}", true)

            @expiration = opts[:endDate]

            if do_setup then
                @versions = getVersion()
            end
            @setup_options = opts[:envOpts]
            @machine = downloader.arch[:label]
            @table = downloader.table
            # Dump the updated env at we're good to go
            self.dump()

            if @setup_options[WENV_OPTS_CONST].to_s() == "true"
                Dir.chdir(opts[:dir])
                runCmd("chmod -Rf -w #{path}/*; true", !VERBOSE)
            end

            return true
        end

        # Self migration method to update default values
        def migrate()
            case @version
            when nil
                # Very old pre rename Env have their own migrate function

                #Compat to migrate old envs
                if @machine == nil then
                    arch = WorkEnvs::getArch()
                    @machine = arch[:label]
                end
                if @release == nil
                    @release = false
                end
                if @setup_options == nil
                    @setup_options = WorkEnvs::EnvOpts.new()
                end
                @version = 1
            when 1
                @properties = {}
                @version = 2
            when 2
                if @machine == nil then
                    arch = WorkEnvs::getArch()
                    @machine = arch[:label]
                end
                @version = 3
            when 3
                # New inheritance scheme. We cannot change our hierarchy but it should keep working anyway
                @version = 4
            when 4
                # New switch env script
                genSwitchEnvScript() if isSwitchable?() == true
                @version = 5
            when 5
                case @release
                when nil, false, "false"
                    @release = "package"
                when true, "true"
                    @release = "releases"
                end
                @version = 6
            when 6
                @release = [ @release ]
                @version = 7
            when 7
                @db_tables = @release
                @version = 8
            when 8
                @ignore_conflicts = false
                @version = 9
            when 9
                if @deps_infos then
                    infos = Dependencies.new

                    downloader = WorkEnvs::PackageDownloader.new(@machine, @db_tables, !VERBOSE)
                    infos.downloader = downloader

                    @deps_infos.each(){|s, v|
                        envClass = WorkEnvs::symbolToClass(s)
                        infos.push_version(envClass, v, false)
                    }
                    infos.downloader = nil
                    @deps_infos = infos
                end
                @version = 10
            when WORK_ENV_VERSION
                # End of recursion, we're up to date
                return self
            else
                raise("Unknown version for env #{@name}")
            end
            # Save edit to the environment due to migration
            self.dump()

            # Keep migrating until we reach the right version
            return self.migrate()
        end
    end
end
