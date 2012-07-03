module WorkEnvs
    # Take an env object or an envClass as an input and return the env Class
    def envToClass(env)
        return env if env.kind_of? Class
        return env.class
    end
    module_function :envToClass

    # Get the MAIN_PACKAGE from an env or an envClass
    #
    # Return an array of package Strings
    #
    # Throws an exception is MAIN_PACKAGE is not set
    def getMainPackage(env, version=0)
        envClass = WorkEnvs::envToClass(env)
        begin
            mainPack = envClass.const_get(:MAIN_PACKAGE)
            return mainPack if mainPack.kind_of?(Array)
            return [ mainPack ]
        rescue
            raise("Environment class #{envClass} has no 'MAIN_PACKAGE'")
        end
    end
    module_function :getMainPackage

    # Get the ENV_TYPE from an env or an envClass
    #
    # Return a label or nil if ENV_TYPE is not set
    def getEnvType(env)
        envClass = WorkEnvs::envToClass(env)
        begin
            return envClass.const_get(:ENV_TYPE)
        rescue
            return nil
        end
    end
    module_function :getEnvType


    # Get the PACKAGES hash from an env or an envClass
    #
    # Return a hash of hash of packages
    #
    # Throws an exception is PACKAGES is not set
    def getPackages(env, version=0)
        envClass = WorkEnvs::envToClass(env)
        begin
            return envClass.const_get(:PACKAGES)
        rescue
            raise("Environment class #{envClass} has no 'PACKAGES'")
        end
    end
    module_function :getPackages

    # Get the DEPENDENCIES from an env or an envClass
    #
    # Return a hash of dependencies or {} if DEPENDENCIES is not set
    def getDependencies(env, version=0)
        envClass = WorkEnvs::envToClass(env)
        begin
            return envClass.const_get(:DEPENDENCIES)
        rescue
            return {}
        end
    end
    module_function :getDependencies

    # Get the GIT_REPO from an env or an envClass
    #
    # Return a String "" if GIT_REPO is not set
    def getGitRepo(env, version=0)
        envClass = WorkEnvs::envToClass(env)
        begin
            return envClass.const_get(:GIT_REPO)
        rescue
            return ""
        end
    end
    module_function :getGitRepo

    # Get the REV_FILE from an env or an envClass
    #
    # Return a String or "n/a" if REV_FILE is not set
    def getRevFile(env, version=0)
        envClass = WorkEnvs::envToClass(env)
        begin
            return envClass.const_get(:REV_FILE)
        rescue
            return "n/a"
        end
    end
    module_function :getRevFile


    # Get the ENV_DESCRIPTION from an env or an envClass
    #
    # Return a String with the env description
    def getEnvDescription(env, version=0)
        envClass = WorkEnvs::envToClass(env)
        begin
            return envClass.const_get(:ENV_DESCRIPTION)
        rescue
            return "<No description provided>"
        end
    end
    module_function :getEnvDescription

    # Get the PARENTS from an env or an envClass
    #
    # Return an of parent env Classes or [] if PARENTS is not set
    def getParents(env, version=0)
        envClass = WorkEnvs::envToClass(env)
        begin
            return envClass.const_get(:PARENTS)
        rescue
            return []
        end
    end
    module_function :getParents

    # Get the OPTIONS from an env or an envClass
    #
    # Return an array of options help strings or [] if OPTIONS is not set
    def getOptions(env, version=0)
        envClass = WorkEnvs::envToClass(env)
        begin
            return envClass.const_get(:OPTIONS)
        rescue
            return []
        end
    end
    module_function :getOptions


    # Get the BLACKLIST from an env or an envClass
    #
    # Return an array of blacklisted packages or [] if BLACKLIST is not set
    def getBlackList(env, version=0)
        envClass = WorkEnvs::envToClass(env)
        begin
            return envClass.const_get(:BLACKLIST)
        rescue
            return []
        end
    end
    module_function :getBlackList
end
