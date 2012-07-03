module WorkEnvs

    # Class used by WorkEnv commands to add option to select an env (or sub env versions)
    #
    # It provides all the standard way (sha1, version, rev files, etc), to select which
    # version of each envClass needs to be selected
    #
    # It also provides the --list option to list available envs
    class VersionSelector

        # Default number of environment versions in a list
        WORK_ENV_DEF_LIST_SIZE = 20

        # Constructor
        #
        # - opts: Program option struct to add the defaults values
        # - optsParser: Program option parser to add the options
        #
        # This is called by WorkEnvs::versionSelectorPrepare
        def initialize(opts, optsParser)
            @options={
                :infos => WorkEnvs::Dependencies.new(),
                :infos_extra => WorkEnvs::Dependencies.new(),
                :envOpts => WorkEnvs::EnvOpts.new(),
                :list => false,
                :branch => nil,
                :hudson => [],
                :sub_sha1 => [],
                :flags => {
                    :ignore_empty => false,
                }
            }
            @rev_files=[]

            optsParser.separator "\nVersion Selection:"
            optsParser.on("-v", "--version <package name>", String,
                          "Name of the package to install.") {|val| @options[:version] = val}
            optsParser.on("-c", "--copy-env <.env_config>", String,
                          "Checkout the versions specified in this environment.") {|val| @options[:copyEnv] = val}
            optsParser.on("-s", "--sha1 <SHA1>", String, "Full or short SHA1 of the package to install.") {|val| @options[:sha1] = val}
            optsParser.on("-l", "--list [#result|all]", String,
                          "List possible packages."+
                          " Shows the last #{WORK_ENV_DEF_LIST_SIZE} by default") {|val| @options[:list] = val}
            optsParser.on("-L", "--latest", nil, "Get the latest possible version.") {|val| @options[:latest] = true}
            optsParser.on("-H", "--hudson <rev_file>", String, "Hudson mode.") {|val| @options[:hudson] << val}
            optsParser.on("-A", "--hudson-auto", nil, "Hudson Auto mode.") {|val| @options[:hudsonAuto] = true}
            optsParser.on("--sub-sha1 <(project|+rev_file name)>:<full sha1>", String,
                          "SHA1 for dependency.") {|val| @options[:sub_sha1] << val}
            optsParser.on("-B", "--branch <branch_name>", String, "Filter list or latest by branch name.") {|val|
                @options[:branch] = val}
            optsParser.on("--ignore-empty", nil, "Exit without error if no packages are found.") {|val|
                @options[:flags][:ignore_empty] = val}

        end

        # Finalize option parsing
        #
        # It validates all the option passed and fills a Dependencies object
        # or simply list the latest packages
        #
        # It fills the Depencencies with:
        # - Existing Dependencies from opts[ :infos ]
        # - version from the latest package if --latest is used
        # - version specified using --version
        # - SHA1 specified using --sha1
        # - Dependencies from another env if --copy-env is used
        # - Rev files provided by the --hudson option
        # - Rev files found using the --hudson-auto option
        # - SHA1 from sub envs if --sub-sha1 is used
        #
        # Note that at this point, dependencies are NOT extracted from the packages.
        # This is done much later by WorkEnvs::Core itself when generating package lists
        #
        # Note that an additional Dependencies is created (infos_extras).
        # It contains dependencies extracted from the rev_file and sub-sha1 to envClass that
        # are not parent of this env
        #
        # Throws an exception if there are dependencies incompatibilites
        #
        # Returns:
        # - A flag hash (:ignore_empty)
        # - a Depencencies for the env
        # - a Depencencies object for dependencies not part of this env (infos_extras)
        # - an EnvOpts object fetched by --copy-env
        #
        # This is called by WorkEnvs::versionSelectorFinal
        def finalize(opts, env)
            #Handle hudson file selection
            @options[:infos].concat(opts[:infos]) if opts[:infos] != nil && !opts[:infos].empty?
            @options[:infos_extra].concat(opts[:infos]) if opts[:infos_extra] != nil && !opts[:infos_extra].empty?

            @options[:infos].ignore_conflicts = true if env != nil && env.ignore_conflicts == true

            downloader = nil
            if env != nil then
                downloader = env.get_downloader(opts)
            else
                downloader = WorkEnvs::PackageDownloader.new()
                downloader.be_silent = !VERBOSE
            end
            @options[:infos].downloader = downloader
            @options[:infos_extra].downloader = downloader

            # Handle version listing
            list_versions(env, downloader) if @options[:list] != false

            # Find all _revision files
            if @options[:hudsonAuto] != nil then
                dirs = runCmd('find . -name "*_revision" -type f | while read dir; do '+
                              'dirname "$dir"; done | sort -u', true).split("\n")
                @options[:hudson] = @options[:hudson].concat(dirs)
            end

            # File to only store the valid rev files
            @options[:revFileList] = []

            @options[:hudson].each(){|revfile|
                if File.exist?(revfile) && File.directory?(revfile) then
                    puts "INFO: Looking at directory '#{revfile}' for dependencies..."
                    @options[:revFileList] +=
                        Dir.entries(revfile).map() { |file|
                        if !File.file?(revfile + "/" + file) || file !~ /.*_revision$/ then
                            nil
                        else
                            revfile + "/" + file
                        end
                    } .compact()
                elsif File.exist?(revfile) == false then
                    puts "INFO: Revision file #{revfile} does not exist. Skipping...."
                else
                    @options[:revFileList].push(revfile)
                end
            }

            #Select the right --latest
            if @options[:latest] == true then
                begin
                    packages = env.getPackages(downloader ,@options[:branch], 1)
                    latest = packages[0]
                    puts "Latest version is:\n\t" + latest.to_s
                    WorkEnvs::Confirm.new("Do you want to update with this version?")
                    @options[:sha1] = latest.sha1
                rescue WorkEnvs::EmptyQueryException => e
                    raise e if @options[:flags][:ignore_empty] != true
                end
            end

            # Convert package name to actual version
            if @options[:version] != nil
                @options[:infos].push_name(env, @options[:version])
            end
            #Convert SHA1 to actual version
            if @options[:sha1] != nil
                @options[:infos].push_sha1(env, @options[:sha1])
            end

            # Fetch copy env dependencies
            if @options[:copyEnv] != nil then
                copy_env = WorkEnvs::loadEnvPath(@options[:copyEnv])
                if copy_env.deps_infos == nil || copy_env.deps_infos.empty? == true then
                    puts "WARNING: env_config provided contains no environment description (Either too old or env is empty..)"
                else
                    @options[:infos].concat(copy_env.deps_infos)

                    if copy_env.setup_options != nil then
                        @options[:envOpts].concat(copy_env.setup_options)
                    end
                end
            end

            viableClassList = WorkEnvs::familyTreeList(env) if env != nil

            # Add deps provided by hudson options
            @options[:revFileList].each(){|revfile|
                @options[:infos].partialEnv = true

                optsKey = :infos

                fileName = File.basename(revfile)
                envClasses = WorkEnvs::revFileToClasses(fileName)
                if envClasses == nil
                    STDERR.puts("WARNING: Unknown rev file type '#{fileName}'. Ignoring...")
                    next
                end
                revision = runCmd("cat #{revfile}", true).split("\n")[0]
                raise("Invalid revision '#{revision}' in #{revfile}") if revision !~ /^[a-f0-9]{40}$/

                WorkEnvs::dputs("Looking at rev file: '#{revfile}")
                process_classes(env, envClasses, revision, viableClassList)
                @rev_files << { :file => revfile, :revision => revision, :envClasses => envClasses }
            }
            @options[:sub_sha1].each(){|str|
                @options[:infos].partialEnv = true

                type, revision = str.split(':')

                envClasses = nil
                if type[0] == "+"
                    fileName = type[1..-1]
                    envClasses = WorkEnvs::revFileToClasses(fileName)
                else
                    envClasses = [ WorkEnvs::stringToEnvClass(type) ]
                end

                if envClasses == nil  || envClasses[0] == nil then
                    STDERR.puts "WARNING: Unknown env type '#{type}'. Skipping..."
                    next
                end
                process_classes(env, envClasses, revision, viableClassList)
            }

            # Flush data to global options
            return @options[:flags], @options[:infos], @options[:infos_extra], @options[:envOpts]
        end

        # Returns an array of hash containing
        # * :file => name of the rev file
        # * :revision => SHA1 in the rev file
        # * :envClasses => List of Classes using this rev file
        def getRevFiles()
            return @rev_files
        end

        # Add dependencies to a revision on a list of env Classes
        #
        # - env is the top env we are looking at
        # - envClasses is an array of env Classes that share the same revision
        # - revision is the SHA1 to use for the dependency
        # - viableClassList is a list of all env Class that are parents to env
        #
        # For each class in envClasses, the dependency is pushed in the Dependencies
        # object @options[ :infos] or @options [ :infos_extra ] depending on
        # the class being a viable class or not
        def process_classes(env, envClasses, revision, viableClassList)
            envClasses.each(){|envClass|
                optsKey = :infos
                envType = WorkEnvs::getEnvType(envClass)

                if env != nil && viableClassList.index(envClass) == nil then
                    STDERR.puts("WARNING: Cannot checkout a #{envType} in "+
                                "a #{env.type} environment. Ignoring...")
                    optsKey = :infos_extra
                end

                added = @options[optsKey].push_sha1(envClass, revision, false)
                if added
                    puts "Add dependency '#{@options[optsKey].get_version(envType)}' for envType #{envType}" if VERBOSE == true
                elsif optsKey != :infos_extra
                    puts "WARNING: Could not find version associated to SHA1 #{revision}"
                end
            }
        end
        private :process_classes

        # Display a list of possible top packages to use with --sha1 or --version
        # and exit
        #
        # Throws EmptyQueryException if no package was found
        def list_versions(env, downloader)
            qty = WORK_ENV_DEF_LIST_SIZE.to_i
            case @options[:list]
            when nil
                qty = WORK_ENV_DEF_LIST_SIZE.to_i
            when "all"
                qty = 0
            else
                qty = @options[:list].to_i
            end
            begin
                env.listPackages(downloader, qty, @options[:branch])
            rescue WorkEnvs::EmptyQueryException => e
                raise e if @options[:flags][:ignore_empty] != true
            end
            exit 0
        end
        private :list_versions
    end
end
