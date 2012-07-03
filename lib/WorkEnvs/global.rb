# -*- coding: utf-8 -*-
require 'pathname'


module WorkEnvs

    # DEBUG mode.
    #
    # Enabled by ENV["DEBUG"] is set
    DEBUG = ((ENV["DEBUG"] != nil) ? true: false)

    # Array of all supported Environment classes
    ENV_TYPES = WorkEnvs.constants.delete_if {|c|
        theObject = WorkEnvs.const_get(c)
        !(Class === theObject) ||
            getEnvType(theObject) == nil
    }.map(){|x| WorkEnvs.const_get(x)}

    @@checkedUpdates = false
    @@checkedEnvs = false

    # Debug print macro.
    # * Only prints if DEBUG=1
    # * Print backtrace if bt == true
    def dputs(str, bt = false)
        return if DEBUG != true

        puts "DEBUG: " + str
        if bt == true then
            puts caller
        end
    end
    module_function :dputs

    # More complete check of the WorkEnvs
    # Mostly checks for coherency error within the ruby scripts themselves.
    #
    # This is not called automatically, unless DEBUG is set
    def selfCheckFull()
        return if !DEBUG
        #Check that the envClass really redefined itself
        global = {
            :types => {},
            :main  => {}
        }

        ENV_LIST.each(){|e|
            envClass = WorkEnvs.const_get(e + "Env")
            type = getEnvType(envClass)
            raise("Both #{global[:types][type]} and #{envClass} use environment type '#{type}'") if global[:types][type] != nil && type != :dev
            global[:types][type] = envClass

            mains = getMainPackage(envClass)
            mains.each(){|main|
                if global[:main][main] != nil then
                    STDERR.puts "WARNING: Both  #{global[:main][main]} and #{envClass} use the same main package '#{main}'"
                end
                global[:main][main] = envClass
            }
        }

    end
    module_function :selfCheckFull

    # WorkEnvs global safety checks
    # and eventual self update
    def checkEnvs(force_update = false)
        return if @@checkedEnvs == true
        # Check required thing that would break everything
        # Autocalled on requiring this file so no worries
        selfCheckFull() if DEBUG == true

        if !File.directory?(WORK_ENVS) then
            STDERR.puts "#{WORK_ENVS} needs to be created to use Work Environments"
            STDERR.puts "Please run: mkdir -p #{WORK_ENVS}"
            raise("Missing #{WORK_ENVS}")
        end
        if !File.directory?(WORK_ENV_CACHE_DIR) then
            runCmd("mkdir -p #{WORK_ENV_CACHE_DIR}", !VERBOSE)
        end
        @@checkedEnvs = true
    end
    module_function :checkEnvs

    # Get the name of the current environment
    def getCurrentEnvName()
        return  ENV["WORK_ENV_CURRENT"]
    end
    module_function :getCurrentEnvName

    # Get path to the current environment
    def getCurrentEnvPath()
        return  ENV["WORK_ENV_PATH"]
    end
    module_function :getCurrentEnvPath

    # Get the list of all dirs to store envs
    #
    # Return a hash (label | :default) => dirpath
    def getDirList()
        settings = settings()
        dirs = { :default => WORK_ENVS }

        settings[:global][:custom_env_dirs].each{|name, dirpath|
            next if !File.exist?(dirpath)
            dirs[name] = dirpath
        }
        return dirs
    end
    module_function :getDirList

    # Get the top dir of an env from its label
    def getDirPathFromLabel(label)
        return WORK_ENVS if label.to_s() == "" || label == :default

        settings[:global][:custom_env_dirs].each{|d_label, dirpath|
            return dirpath if d_label == label
        }
        raise("Invalid wenv directory label '#{label}'")
    end
    module_function :getDirPathFromLabel

    # Get the label top dir from its path
    def getDirLabelFromPath(path)
        settings[:global][:custom_env_dirs].each{|label, dirpath|
            return label if dirpath == path
        }
        return nil
    end
    module_function :getDirLabelFromPath

    # Extract label and name from an env name string
    #
    # Format is label::name
    #
    # Returns label,name
    #
    # If the env is in the default dir, label=nil
    def strToLabelName(str)
        a = str.split("::")
        env_name = str
        label = nil
        if a.length > 1 then
            env_name = a[1]
            label = a[0]
        end
        return label,env_name
    end
    module_function :strToLabelName

    # Generate an env name string from a label and the env name
    #
    # Returns a string with the full name
    def labelNameToStr(label, name)
        if label.to_s() == "" || label == :default
            return name
        else
            return label.to_s() + "::" + name.to_s()
        end
    end
    module_function :labelNameToStr

    # Check if the name match a valid environment
    #
    # This returns true wheteher the environment is switchable or not
    def isEnv?(name)
        checkEnvs()
       # Does this name matches a valid environment
        label, name = strToLabelName(name)

        confFile = getDirPathFromLabel(label) + "/" + name + "/" + ENV_CONF
        # Skip unconfigured envs
        return false if !File.exist?(confFile)
        return true
    end
    module_function :isEnv?

    # Load environment from its name using loadEnv
    #
    # name MUST be a valid environment
    def getEnv(name)
        checkEnvs()
        label, name = strToLabelName(name)

        # Create an workEnv object (from it's file) using its name (must be valid)
        path = getDirPathFromLabel(label) + "/" + name + "/" + ENV_CONF
        env = loadEnvPath(path)
        env.label = label if env != nil
        return env
    end
    module_function :getEnv

    def YAMLLoad(data)

        begin
            return YAML::load(data)
        rescue Psych::DisallowedClass
            # If data is a file, don't forget to rewind back to its beginning
            data.rewind() if data.is_a?(File)
            y = YAML::load(data,
                              permitted_classes:
                                  ENV_LIST.map(){|x| WorkEnvs.const_get(x+ "Env") } +
                              [ WorkEnvs::EnvOpts, Symbol ])
        end
    end
    module_function :YAMLLoad

    # Load environment from a YAML file
    # * Path points to a YAML description file
    # * Environment are self migrated on load
    def loadEnvPath(path)
        migrate = false
        desc = File.open(path, "r")
        begin
            env = YAMLLoad(desc)
        rescue => e
            raise("Failed to load environment description for environment '#{path}': #{e}")
        end
        desc.close()

        #Check for broken Envs
        expectedName = File.basename(File.dirname(path))
        if env.name != expectedName then
            STDERR.puts "ERROR: Environment internal name does not match directory name..."
            STDERR.puts "ERROR: Directory name is '#{expectedName}'. Internal name is '#{env.name}'"
            rep = 't'
            while rep != "y" && rep != "n" && rep != '' do
                puts "Do you wish to update this environment internal name to '#{expectedName} ? (y/N): "
                rep = STDIN.gets.chomp()
            end
            if rep == "y" then
                env.name = expectedName
                env.dump()
            else
                raise("Cannot continue until this environment name is fixed or #{File.dirname(path)} is moved outside #{WORK_ENVS}.")
            end
        end

        #Update the env if necessary
        env = env.migrate()

        return env
    end
    module_function :loadEnvPath

    # Return the current environment object
    def getCurrentEnv()
       # Return the current environment in we are in one

        envName = getCurrentEnvName()
        if envName == nil || envName == "" then
            STDERR.puts "No current environment"
            return nil
        end
        dirpath = File.dirname(getCurrentEnvPath())
        label = getDirLabelFromPath(dirpath)
        name_str = labelNameToStr(label, envName)
        if !isEnv?(name_str)
            STDERR.puts "'#{curEnv} is not a valid environment"
            return nil
        end
        # Load environment
        return getEnv(name_str)
    end
    module_function :getCurrentEnv

    # Return an array of all existing environments object
    def getEnvs()
        checkEnvs()
        settings = settings()

        envs=[]
        dirs = getDirList()
        dirs.each(){|label, dirpath|
            Dir.foreach(dirpath).sort().each() {|dirname|
                # Skip hidden directories
                next if dirname[0] == "."

                # Skip bad environment
                next if !isEnv?(labelNameToStr(label, dirname))

                # Load environment
                begin
                    envs << getEnv(labelNameToStr(label, dirname))
                rescue => e
                    # Environment might be broken. Skip
                    puts e.to_s
                    next
                end
            }
        }
        return envs
    end
    module_function :getEnvs

    # Return an array of all existing environments names
    def getEnvNames()
        settings = settings()
        envs = []
        dirs = getDirList()
        dirs.each(){|label, dirpath|
            Dir.foreach(dirpath).sort().each() {|dirname|
                # Skip hidden directories
                next if dirname[0] == "."

                # Skip bad environment
                next if !isEnv?(labelNameToStr(label, dirname))
                envs << dirname
            }
        }
        return envs
    end
    module_function :getEnvNames

    # Check if 'type' is a valid environment type
    #
    # type can either be String or Symbol
    def isValidType?(type)
        envTypes = listEnvTypes()
        return false if envTypes[type.to_sym()] == nil
        return true
    end
    module_function :isValidType?

    # Check if 'name' is a valid environment name
    def isValidName?(name)
        # Can the name be used for an environment
        return false if name !~ /^[a-zA-Z0-9][a-zA-Z0-9_.:-]*$/
        return true
    end
    module_function :isValidName?

    # Check if we can safely switch to an environment from its name
    #
    # This checks that the environment has contents (unless it's a dev environment),
    # and that the versions of the files within the environment are the
    # versions expected
    #
    # 'name' must be a valid name.
    def isSwitchable?(name)

        # Load the environment object
        env = getEnv(name)

        # Check that all required packages are initialized
        return env.isSwitchable?()
    end
    module_function :isSwitchable?

    # Convert en environment type (Symbol or String) to the
    # associated environment Class
    #
    # Returns nil if none or multiple environment match
    def symbolToClass(name)
        envClass = listEnvs().select {|c|
            getEnvType(c) == name.to_sym()
        }
        return nil if envClass == nil || envClass.length != 1
        return envClass[0]
    end
    module_function :symbolToClass

    # Returns an array of environment class that use
    # 'file' as theuir REV_FILE
    #
    # Returns nil if no environment matches
    def revFileToClasses(file)
        name = File.basename(file)
        envClasses = listEnvs().select {|c|
            getRevFile(c) == name
        }

        return nil if envClasses == nil || envClasses.length == 0
        return envClasses
    end
    module_function :revFileToClasses

    # Add all env specific options to the opt Parser
    # so it shows up in the usage
    def addEnvToOptParser(optsParser)
        envHash = listEnvTypes()
        optsParser.separator "Environment Types:"
        envHash.each(){|sym, tClass|
            legend = getEnvDescription(tClass)
            char='-'
            char='*' if sym.to_s == WORK_ENV_DEFAULT_TYPE
            optsParser.separator("    #{char} " + sym.to_s.ljust(59) + legend)
        }
    end
    module_function :addEnvToOptParser

    # Return an array of all environment classes
    def listEnvs()
        return ENV_TYPES
    end
    module_function :listEnvs

    # Return a hash containing environment type => environment class
    def listEnvTypes()
        envClass = listEnvs()
        envHash = {}
        envClass.each(){|theClass|
            envHash[getEnvType(theClass)] = theClass
        }
        return envHash
    end
    module_function :listEnvTypes

    # Create a memory instance of an environment
    #
    # * name: instance name
    # * type: environment type
    # * machine: hash returned by getArch() to configure the environment
    #            host/arch
    # * release: Name of the default table in the DB to search for versions
    #
    # All environment are checked for validity
    # Return a pointer to a BasicEnv object on success
    def instantiateEnv(name, type, machine, release)
        label, name = strToLabelName(name)
        envClass = stringToEnvClass(type)
        env = envClass.new(name, machine, release)
        env.label = label
        return env
    end
    module_function :instantiateEnv

    # Return if an environment with this name exists
    def existsEnv?(name)
        checkEnvs()
        label, name = strToLabelName(name)
        dirpath = getDirPathFromLabel(label)
        return File.exist?(dirpath + "/" + name) && File.exist?(dirpath + "/" + name + "/" + ENV_CONF)
    end
    module_function :existsEnv?

    # Create an environment.
    #
    # * Instantiate a environment using instantiatEnv
    # * Saves it on disk
    def createEnv(name, type, release)
        checkEnvs()
        raise("Environment already exists") if existsEnv?(name) == true
        env = instantiateEnv(name, type, nil, release)
        dirpath = getDirPathFromLabel(env.label)

        Dir.mkdir(dirpath + "/" + env.name)
        env.dump()
        return env
    end
    module_function :createEnv

    # Generic code to support version selection in the opt parser
    #
    # * --sha1/--version
    # * --hudson/--hudson-auto
    # * --sub-sha1
    # * --list/--latest
    # * etc...
    #
    # Instantiate a #VersionSelector
    def versionSelectorPrepare(opts, optsParser)
        opts[:version_selector] = VersionSelector.new(opts, optsParser)
    end
    module_function :versionSelectorPrepare

    # Post-Process #VersionSelector options by calling finalize()
    def versionSelectorFinal(opts, env)
        raise("Internal error") if opts[:version_selector] == nil
        flags, opts[:infos], opts[:infos_extra], envOpts = opts[:version_selector].finalize(opts, env)
        opts[:envOpts] = opts[:envOpts].concat(envOpts)
        opts.merge!(flags)
    end
    module_function :versionSelectorFinal

    # Remove an env from its full name (label and name)
    #
    # BEWARE: No confirmation !
    def deleteEnv(name)
        # Delete an existing environment completely !!!
        label, name = strToLabelName(name)
        dirpath = getDirPathFromLabel(label)
        runCmd("chmod -R +w #{dirpath + "/" + name}", !VERBOSE)
        runCmd("rm -Rf #{dirpath + "/" + name}", !VERBOSE)
    end
    module_function :deleteEnv

    # Return a header to display environment lists
    def listHeader()
        maxLen = getEnvNames().inject(0){|x, y| x > y.length ? x : y.length}
        return "Name".ljust(maxLen + 2) + "Type".center(20) + "Machine".center(15) +
            "Expiration".center(15)
    end
    module_function :listHeader

    # Return an array of all the parent env Classes of an envClass (including itself)
    #
    # if no_recurse is set, only return the envClass provided
    def familyTreeListClass(objClass, no_recurse = false)
        if no_recurse == true
            return [ objClass ]
        end

        classList=[ ]
        tmpList=[ objClass ]
        hasBaseClass = false

        while tmpList.length != 0
            obj = tmpList.shift()


            # Delete object first so that if it exits, we will retain the version
            # that is the highest in the dep tree so all the analysis dependency
            # should be done in the right order
            classList.delete(obj)

            classList.push(obj)
            hasBaseClass = true if obj == BasicEnv

            getParents(obj).each(){|parent|
                tmpList.push(parent)
            }
        end

        classList.push(BasicEnv) if hasBaseClass == false
        return classList
    end
    module_function :familyTreeListClass

    # Return an array of all the parent env Classes of an env (including the env class itself)
    #
    # Calls #familyTreeListClass
    def familyTreeList(obj, no_recurse = false)
        return familyTreeListClass(obj.class, no_recurse)
    end
    module_function :familyTreeList

    # Calls a code block on each parent env Class of an env Class (including itself)
    #
    # If reverse is true, call from ancestors to children
    def familyTreeApplyClass(objClass, reverse = false, no_recurse = false, &f)
        classList = familyTreeListClass(objClass, no_recurse)

        if reverse == false then
            classList.each(){|objClass|
                yield objClass
            }
        else
            while ! classList.empty? do
                objClass = classList.pop()
                yield objClass
            end
        end

    end
    module_function :familyTreeApplyClass


    # Calls a code block on each parent env Class of an env (including the env class itself)
    #
    # If reverse is true, call from ancestors to children
    #
    # Calls #familyTreeApplyClass
   def familyTreeApply(obj, reverse = false, no_recurse=false, &f)
        familyTreeApplyClass(obj.class, reverse, no_recurse){|_class| yield _class }
    end
    module_function :familyTreeApply

    # Returns an array of all the env Classes that share the same repository as objClass
    def exploreSiblings(objClass)
        envClass = envToClass(objClass)
        repo = getGitRepo(objClass)
        return [ envClass ] if repo == ""

        begin
            return listEnvs().map{|e| getGitRepo(e) == repo ? e : nil}.compact()
        rescue
            return [ envClass ]
        end
    end
    module_function :exploreSiblings

    # Look in entries for string that starts with str
    #
    # Returns:
    # - the first match
    # - a list of all matches
    def matchPrefix(entries, str)
        full_name = []
        entries.each(){|ent|
            next if ent !~ /^#{str}/
            full_name << ent
        }
        return full_name[0], full_name
    end
    module_function :matchPrefix

    # Look in entries for string that contains with str
    #
    # Returns:
    # - the first match
    # - a list of all matches
    def matchExp(entries, str)
        full_name = []
        entries.each(){|ent|
            next if ent !~ /#{str}/
            full_name << ent
        }
        return full_name[0], full_name
    end
    module_function :matchExp

    # Exception when the provided name matches more than one environment
    class EnvNameErrorException < StandardError
        # Constructor
        #
        # - str: string provided on the command line
        # - matches: array of environment names that matches
        def initialize(str, matches)
            if matches.length == 0 then
                super("'#{str}' match no environment")
            else
                super("'#{str}' match multiple environments: #{matches.join(", ")}")
            end
        end
    end

    # Exception when no environment name has been provided
    class EnvNoNameErrorException < StandardError
        # Default constructor
        def initialize()
            super("No environment name provided")
        end
    end

    # Exception when no environment name has been provided
    class EnvNoTypeErrorException < StandardError
        # Default constructor
        def initialize()
            super("No environment type provided")
        end
    end

    # Exception when no environment name has been provided
    class EnvTypeErrorException < StandardError
        # Constructor
        #
        # - str: string provided on the command line
        def initialize(str)
            super("Environment type '#{str}' is invalid")
        end
    end

    # Environment name expansion
    #
    # Return the name of an existing environment if 'str' matches at most 1
    # existing environment
    def nameToEnvName(str)
        raise EnvNoNameErrorException if str.to_s == ""

        return str if isEnv?(str)

        envs =  getEnvs().map(){|x| x.name}
        completeName, matches = matchPrefix(envs, str)
        if matches.length == 0 then
            completeName, matches = matchExp(envs, str)
        end

        if matches.length != 1 then
            exp = EnvNameErrorException.new(str, matches)
            raise exp
        end
        puts "INFO: Env name '#{str}' matches environment '#{completeName}'"
        return completeName
    end
    module_function :nameToEnvName

    # Serialize an object to be returns to a calling RPC process through logs
    #
    # Returns a string of the serialized object
    def serialize(str)
        return ":B64_OBJ:" + Base64.encode64(str.to_yaml()).gsub("\n", '') + ":/B64_OBJ:"
    end
    module_function :serialize

    #Regexp to extract B64 Objects encoded in RPC result
    B64_OBJ_REGXP = /:B64_OBJ:([A-Za-z0-9+\/=]*):\/B64_OBJ:/

    # Returns an array with all the objects encoded in Base64 within the provided string
    def deserialize(str)
        return str.scan(B64_OBJ_REGXP).map(){|x|
            YAMLLoad(Base64.decode64(x[0].gsub(B64_OBJ_REGXP, '\1')))
        }
    end
    module_function :deserialize

    # Run a remote Wenv action 'action' with option_str as options.
    #
    # host_str format is [user@]host[:/path/to/wenv]
    #
    # Returns an (array of returned RPC objects, logs without RPC)
    def remoteRun(host_str, action, option_str)
        args=host_str.split(":")
        host=args[0]
        path=""
        path=args[1] + "/" if args.length == 2
        ret = runCmd("ssh -t -t -o  StrictHostKeyChecking=no "+
                     "#{host} #{path}wenv #{action} #{option_str}", !VERBOSE)
        return deserialize(ret), ret.gsub(B64_OBJ_REGXP, "")
    end
    module_function :remoteRun

    # Convert a string from CLI to an env Class
    #
    # String is normalement (lower first char) and converted to a label then matched against
    # ENV_TYPE of each env class
    def stringToEnvClass(type)
        normalized_typename = type.to_s.slice(0,1).downcase + type.to_s.slice(1..-1)
        raise EnvTypeErrorException.new(type) if ! isValidType?(type)

        # Create a new environment or raise an exception if parameters are invalid
        env = nil
        envClass = symbolToClass(normalized_typename)
        raise("Ooops. Failed to generate envClass. Contact support !") if envClass == nil
        return envClass
    end
    module_function :stringToEnvClass

    # Return a list of all the packages (including internal, temporary, extras)
    # listed in an env Class
    def listAllPackages(objClass)
        getPackages(objClass).values.inject([]){|p, x|
            p + x.values.inject([]){|q, c|
                q+c.map(){|d| d.to_s}
            }
        }
    end
    module_function :listAllPackages

    # Return a list of all the packages (including internal, temporary, extras)
    # listed in an env Class and its siblings
    def listAllPackagesWithSiblings(objClass)
        return exploreSiblings(objClass).inject([]) { |r, sibling |
            r + listAllPackages(sibling)
        }.uniq
    end
    module_function :listAllPackagesWithSiblings
end

