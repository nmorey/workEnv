module WorkEnvs
    # Default Env class
    # All environment should inherit from this.
    #
    #
    # They must provide these constants:
    # * MAIN_PACKAGE
    # * ENV_TYPE
    # * ENV_DESCRIPTION
    # * PARENTS
    # * PACKAGES
    # * DEPENDENCIES
    # * OPTIONS
    # * REV_FILE
    # * GIT_REPO
    class BasicEnv < Core
        # Name of the package used to lookup the environment in the DB
        MAIN_PACKAGE = ""

        # Unique label to describe the env Class
        ENV_TYPE = :dev

        # String to describethe env in man pages/help
        ENV_DESCRIPTION = "Empty environment"

        # Array of parent Classes
        #
        # Parent classes (also called sub classed) are env Classes that are used by this Env
        #
        # When updating an env they should usually be downloaded and extracted to.
        # Their dependency come either from:
        # - Integration stuff (rev_files, manual --sub-sha1 opts)
        # - More genrally through packages (RPM/Deb) dependencies as described in #DEPENDENCIES
        PARENTS = []

        # List of all the packages provided by this envClass
        #
        # Three top levels to the hash:
        # - :external: Package that should end up in the release packages
        # - :internal: Internal build packages. Do not deliver
        # - :temporary: Package needed during the setup pahe but to be removed afterward
        #   Specially used for keygens
        # Two bottom levels:
        # - :required: package MUST be available or there is an issue
        # - :extras: package are retreive if available
        #   This used for package that are added as time passes but are not available
        #   for all versions
        PACKAGES = {
            :external => {
                :required => [],
                :extras => [],
            },
            :internal => {
                :required => [],
                :extras => [],
            },
            :temporary => {
                :required => [],
                :extras => [],
            }
        }

        # Dependency descriptor used to extract dependencies to parent envClass from packages
        #
        # Format of the hash is
        #   regexp => { [ env types ] => [ package name to match ]
        #
        # - The regexp is matched on the packages listed by this env class
        # - The env types allows to point to a specific env if a package name
        #   belong to multiple env Class
        # - Package name that may or may not be the MAIN_PACKAGE of parent Classes
        DEPENDENCIES = {
        }

        # Array of env specific options help string
        OPTIONS = [
                   WENV_OPTS_EXTERNAL_STRING, WENV_OPTS_PARTIAL_STRING, WENV_OPTS_CONST_STRING
                  ]
        # Revision file name. Should end with __revision
        REV_FILE = 'n/a'

        # Repository path
        # This is used to find "siblings" env classes (meaning different packages but same SHA1)
        GIT_REPO = ''

        # Name of the environment
        attr_accessor :name
        # ENV_TYPE of the appropriate env Class
        attr_accessor :type
        # Version stored during update by getVersion functions
        attr_accessor :versions
        # Dependencies Object generated during update
        attr_accessor :deps_infos
        # Optional expiration date for licenses
        attr_accessor :expiration
        # EnvOpts Object geenrated during update
        attr_accessor :setup_options
        # Target architecture String
        attr_accessor :machine
        # DB Tables used
        attr_accessor :db_tables
        # Internal Core versio number for migration
        attr_accessor :version
        # Hash to store custom properties
        attr_accessor :properties
        # Magic flag to ignore conflict during update (stored for --copy-env)
        attr_accessor :ignore_conflicts
        # Label describing which dir the env is stored to
        # Cleared on dump to avoid messing with other setups
        attr_accessor :label

        # Subclass should implement this, start by calling super, fix their type and initialize theuir version to
        # :unitialized
        def initialize(name, machine, release)
            if ! WorkEnvs::isValidName?(name)
                raise("Invalid name '#{name}' for an environment. Syntax is [a-zA-Z0-9][a-zA-Z0-9_.-]*")
            end

            arch = WorkEnvs::getArch(machine)
            @name = name
            @type = ENV_TYPE
            @machine = arch[:label]
            @versions={}
            @deps_infos = nil
            @expiration = "   N/A   "
            @db_tables = DBInterface::toTable(release)
            @setup_options = EnvOpts.new();
            @version = WORK_ENV_VERSION
            @properties = {}
            @parents = []
            @ignore_conflicts = false
        end

        # This returns a map that contains the environment version and all the
        # version of the inherited environments as versions[:'type'] = 'version id'
        def self.getVersion(path, canFail = false)
            versions = {}
            return versions
        end

        # Function called by update during env cleanup
        def self.cleanup(opts)
        end

        # Function called during pre-setup, before download
        #
        # These functions are allowed to modify the package lists
        def self.pre_setup(opts, packages, temp_packages)
        end

        # Post install script. This is called after all definitive and temporary packages are downloaded
        # It is called from the temporary package directory
        # opts define :tempDir with the current directory and :dir for the install directory
        # This must call super before or after its own role to make sure inherited environments are initialized
        def self.post_setup(opts = {})
            return if self != WorkEnvs::BasicEnv
            path = opts[:dir]
            runCmd("mkdir -p #{path}/kEnv-config", !VERBOSE)

        end

        # Function called after download and extract but before installation of system packages
        def self.pre_install(opts, packages, temp_packages)
        end

        # Function called after installation of system packages
        def self.post_install(opts, packages, temp_packages)
        end

        # Function to generate commands into the switch env script for this env class
        #
        # Returns an array of string
        def self.switchEnv(env, path)
            return [] if self != WorkEnvs::BasicEnv

            array=[]
            array << "#!/bin/bash"
            array << ""
            array << "unset BASH_ENV"
            array << "export WORK_ENV_SCRIPTS_DIR=\"#{WORK_ENV_SCRIPTS_DIR}\""
            array << "export WORK_ENVS=\"$(dirname $(dirname $( readlink -f $BASH_SOURCE)))\""
            array << "export WORK_ENV_CURRENT=\"$(basename $(dirname $( readlink -f $BASH_SOURCE)))\""
            array << "export WORK_ENV_PATH=\"${WORK_ENVS:-/work1/$(whoami)/work-envs}/${WORK_ENV_CURRENT}\""
            array << "export WORK_ENV_CURRENT_TYPE=#{env.type.to_s}"
            array << "export WORK_ENV_LOADING_BASHRC='y'"
            array << "[ -z $WORK_ENV_NOBASHRC ] && [ -f ~/.bashrc ] && . ~/.bashrc"
            array << "unset WORK_ENV_LOADING_BASHRC"
            array << ""
            array << "export PATH=\"${WORK_ENV_SCRIPTS_DIR}${PATH:+:$PATH}\""
            array << "export MANPATH=\"${WORK_ENV_SCRIPTS_DIR}/man:${MANPATH}\""
            array << "export WORK_ENV_PS1=\"${WORK_ENV_CUSTOM_COLOR_START}${WORK_ENV_CURRENT:+($WORK_ENV_CURRENT) }"+
                "${WORK_ENV_CUSTOM_COLOR_STOP}\""
            array << "export PS1=\"${WORK_ENV_PS1}${PS1}\""
            return array
        end

        # Returns if an environment is of dev type
        def self.isDev?()
            type_str = WorkEnvs::getEnvType(self).to_s
            return true if type_str =~ /^dev/
            return false
        end
   end
end
