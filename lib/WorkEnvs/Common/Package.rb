# -*- coding: utf-8 -*-

module WorkEnvs
    # Class to briefly describe a MAIN_PACKAGE of an envClass
    #
    # This is only used to get a list of possible MAIN_PACKAGE version
    # of a given class to provide a human readable list of accessible package
    class EnvPackage
        # Full name of the package
        attr_reader :name
        # SHA1 that generated the package
        attr_reader :sha1
        # Package the branch was generated on
        attr_reader :branch
        # Additional info (timestamp usually) on the package
        attr_reader :info

        # Default Constructor
        def initialize(name, sha1, branch, info)
            @name = name
            @sha1 = sha1
            @branch = branch
            @info = info
        end

        # Returns a human readable string of the package data
        def to_s()
            return "\t" + @name.to_s.ljust(65) + "\t" +
                @sha1.to_s + "\t" +
                @branch.to_s.ljust(40) +
                @info.to_s
        end
    end

    # Class to describe a package
    class Package

        # Package name (without version/release/etc)
        #
        # Also known as "project" in de DB
        attr_accessor :name
        # Package attributes (default = {}
        #
        # Currently supported attributes:
        # - :install
        #   - :dkms : Packet is installed during an env update when --install-dkms is set
        #   - :install: Packet is always installed during an env update. SHOULD NOT BE SET
        # - :keep : Package is kept after download/extraction event if keep-packages is not set
        attr_accessor :attributes
        # Full package name (ie name-version-release.rpm)
        attr_accessor :pack
        # Full path to the package
        attr_accessor :path

        # Default constructor
        def initialize(name, attributes = {}, pack=nil)
            @name = name
            @attributes = attributes
            @pack = pack
            @path = nil
        end

        # Returns the package name
        def to_s()
            return @name
        end

        # Compare two Package objects themselves (not the content)
        #
        # Used for sorting
        def eql?(other)
            return self == other
        end

        # Compare two Package objects values
        def ==(other)
            return false if other == nil
            return self.hash() == other.hash()
        end

        # Spaceship operation
        #
        # Calls <=> on full package names
        #
        # Used for sorting
        def <=>(other)
            return @pack <=> other.pack()
        end

        # Returns a Package hash
        #
        # Used for sorting
        def hash()
            return { :name => @name, :attributes => @attributes, :pack => @pack, :path => @path }.hash()
        end

        # Returns true if the package should be installed
        #
        # A package should be installed if:
        # - it has the attribute :install == true
        # - it has the attribute :install == :dkms and :installDKMS options is set
        def shouldInstall(opts)
            return @attributes[:install] == true ||
                ( @attributes[:install] == :dkms && opts[:installDKMS] == true)
        end

        # Returns true if the package should be kept after download/extraction
        #
        # A package should be kept if:
        # - it has the attribute :keep == true
        # - it the :keepPackages options is set
        def shouldKeep(opts)
            return @attributes[:keep] == true || opts[:keepPackages] == true
        end
    end
end
