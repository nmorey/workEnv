# -*- coding: utf-8 -*-

module WorkEnvs

    # Name of the no dkms options
    WENV_OPTS_NODKMS = "nodkms"
    # Help string for the no dkms options
    WENV_OPTS_NODKMS_STRING =
        "\t#{WENV_OPTS_NODKMS}=false                                             Build DKMS modules"

    # Name of the no eclipse options
    WENV_OPTS_NOECLIPSE = "noeclipse"
    # Help string for the no eclipse options
    WENV_OPTS_NOECLIPSE_STRING =
        "\t#{WENV_OPTS_NOECLIPSE}=true                                           Do not install eclipse plugins"

    # Name of the external options
    WENV_OPTS_EXTERNAL = "external"
    # Help string for the external options
    WENV_OPTS_EXTERNAL_STRING =
        "\t#{WENV_OPTS_EXTERNAL}=true                                            Do not install internal packages "

    # Name of the partial options
    WENV_OPTS_PARTIAL = "partial"
    # Help string for the partial options
    WENV_OPTS_PARTIAL_STRING =
        "\t#{WENV_OPTS_PARTIAL}=true                                             Support partially checked out environment "

    # Name of the remote install options
    WENV_OPTS_REMOTE_INSTALL = "remote-install"
    # Help string for the remote install options
    WENV_OPTS_REMOTE_INSTALL_STRING =
        "\t#{WENV_OPTS_REMOTE_INSTALL}=false                                     Disable install of packages on remote "

    # Name of the remote host options
    WENV_OPTS_REMOTE_HOST_INSTALL = "remote-host"
    # Help string for the remote host options
    WENV_OPTS_REMOTE_HOST_INSTALL_STRING =
        "\t#{WENV_OPTS_REMOTE_HOST_INSTALL}=<host>                                       Install of packages on the specified remote host "

    # Name of the const options
    WENV_OPTS_CONST = "const"
    # Help string for the const options
    WENV_OPTS_CONST_STRING =
        "\t#{WENV_OPTS_CONST}=true                                               Remove all write rights to environment so it cannot be modified"

    # Name of the sparse options
    WENV_OPTS_SPARSE = "sparse"
    # Help string for the sparse options
    WENV_OPTS_SPARSE_STRING =
        "\t#{WENV_OPTS_SPARSE}=true                                              Sparse update of the env (skip some unneeded packages"

    # Class to store envClass options
    class EnvOpts
        # Default constructor
        def initialize
            @opts = {}
        end

        # Iterates on all options set
        #
        # Block args are (option name, option val)
        def each()
            @opts.each(){|name, val|
                yield name, val
            }
        end

        # Returns true if there are no options set
        def empty?
            return @opts.empty?
        end

        # Returns the value of the option "name"
        #
        # Returns "" if the option was not set
        def [](name)
            return "" if @opts[name] == nil
            return @opts[name]
        end


        # Set the value of the option "name"
        #
        # Returns its value
        def []=(name, val)
            @opts[name] = val
            return val
        end

        # Parse an option string and add it to self
        #
        # String format is name=val
        #
        # val cannot contain an "=" symbol
        def <<(string)
            args = string.split("=")
            raise("Unsupported option #{string}") if args.length != 2
            @opts[args[0]] = args[1];
        end

        # Compare two EnvOpts
        def ==(another)
            begin
                @opts.each(){|name, val|
                    return false if another[name] != val
                }
                another.each(){|name, val|
                    return false if @opts[name] != val
                }
                return true
            rescue
                return false
            end
        end

        # Concat another EnvOpts into this one
        #
        # Value set in this one are NOT overwritten by the other one
        def concat(another)
            if another != nil then
                another.each(){|name, val|
                    @opts[name] =  val if @opts[name] == nil || @opts[name] == ""
                }
            end
            return self
        end
	end
end
