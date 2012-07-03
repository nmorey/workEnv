module WorkEnvs
    class AnyEnv < BasicEnv
        MAIN_PACKAGE = "Any"
        ENV_TYPE = :any
        ENV_DESCRIPTION = "Any Combination of environments"
        PARENTS = ENV_LIST.map(){|x|
            if x == "Any" || x == "Work" then
                nil
            else
                WorkEnvs.const_get(x + "Env")
            end
        }.compact()
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
        DEPENDENCIES = {},
        OPTIONS = []
        REV_FILE = 'any_revision'
        GIT_REPO = 'git:software/foo/bar'

        def initialize(name, machine, release)
            super(name, machine, release)
            @versions[ENV_TYPE] = :uninitialized
            @type = ENV_TYPE
        end

        def self.getVersion(path, canFail = false)
            versions[:any] = "any"
            return versions
        end

        def self.post_setup(opts = {})
        end
        def self.switchEnv(env, path)
            return []
        end
    end
end
