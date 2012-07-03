#!/usr/bin/ruby

require 'uri'
require 'tempfile'
require 'rbconfig'
require 'thread'

# Creates unique temporary directory in /tmp
def create_tmp_dir(tmp_dir_prefix=nil,tmp_root_dir=nil)
    tmp_dir = nil

    if(Dir.respond_to?('mktmpdir')) then
        tmp_dir = Dir.mktmpdir(tmp_dir_prefix,tmp_root_dir)
    else
        tmp_root_dir = (tmp_root_dir.nil? ? Dir.tmpdir : tmp_root_dir)
        tmp_dir_prefix = (tmp_dir_prefix.nil? ? "" : tmp_dir_prefix)
        tmp_dir_name = File.join(tmp_root_dir,tmp_dir_prefix)
        tmp_dir = `mktemp -d #{tmp_dir_name}XXXXXX`.chomp()
    end
    return tmp_dir
end

# Run a shell command and return its stdout
#
# Print command if verbose = false
#
# Returns the cimmand return status
def runCmd(cmd, silent = false, nRetry = 1)
    ret = 0
    1.upto(nRetry){|i|
        retrying = (i == 1 ? "" : "Retrying: ")
        puts retrying + cmd if silent == false
        if(RbConfig::CONFIG['host_os']  =~ /mingw/) then
            script   = Tempfile.new("script")
            script.puts "set -x"
            script.puts "set -e"
            script.puts cmd
            script.flush()
            system("cat #{script.path}")
            ret = `bash #{script.path}`.chomp()
            script.close()
        else
            ret = `#{cmd}`.chomp()
        end
        return ret if $? == 0
    }
    raise("Command failed:\npwd=#{Dir.pwd()}\nCommand=#{cmd}\nReturn=#{ret}") if $? != 0
end

# Execute cmd and returns true in case of success, false otherwise
def runTest(cmd, silent = false, nRetry = 1)
    ret = 1
    1.upto(nRetry){|i|
        retrying = (i == 1 ? "" : "Retrying: ")
        puts retrying + cmd if silent == false
        if(RbConfig::CONFIG['host_os']  =~ /mingw/) then
            script   = Tempfile.new("script")
            script.puts "set -x"
            script.puts "set -e"
            script.puts cmd
            script.flush()
            system("cat #{script.path}")
            ret = `bash #{script.path}`.chomp()
            script.close()
        else
            ret = `#{cmd}`.chomp()
        end
        return true if $? == 0
    }
    return false
end

module WorkEnvs
    # Command to download a remote file through HTTP or HTTPS
    WORK_WGET_CMD="wget -q --no-check-certificate"
    # Command to check if a remote file exists (HTTP or HTTPS)
    WORK_WGET_SPIDER_CMD="wget #{WorkEnvs::VERBOSE == true ? "" : "-q"} --no-check-certificate --spider"
    # Command to copy a file
    WORK_CP_CMD="cp"

    # Exception thrown when a file was not found
    class NoSuchFileException < StandardError
        # Constructor
        #
        # - path = package path
        # - server = locations searched
        def initialize(path, server="")
            super("\nERROR: File #{path} could not be found #{server}\n")
        end
    end

    # Class used to manipulate packages
    #
    # This allows to query the DB for packages, query for dependencies (DB or files),
    # download, extract packages and much more
    class PackageDownloader
        # Selected architectrue.
        #
        # This is a hash returned by WorkEnvs::getArch()
        attr_reader :arch

        # Table to use for DB queries (default = nil)
        #
        # Passed to the DBInterface #db_interface
        attr_reader :table

        # Global settings
        attr_reader :settings

        # DBInterface used for DB queries
        attr_reader :db_interface

        # Constructor
        #
        # - machine: label of the machine to run on. (default = nil)
        #   This is passed to WorkEnvs::getArch to fill the #arch attribute
        # - table: Table to use for queries (default = nil)
        #   This is usually not set because the --table option modifies the settings
        #   and end up to be the default
        # - silent: If false, activate verbosity (default = true)
        def initialize(machine = nil, table=nil, silent = true)
            @settings = WorkEnvs::settings[:db]
            @arch = WorkEnvs::getArch(machine)
            @table = table

            @db_interface = DBInterface.new(machine, table, silent)
            @be_silent = silent
            @semaphore = Mutex.new
        end

        # Change the silent attribute for the PackageDownloader and its DBInterface
        def be_silent=(val)
            @be_silent = val
            @db_interface.be_silent = val
        end

        # Modify a DBQuery to ignore specific version
        #
        # The goal of this is to handle package that moved from one project to
        # another. This make sure we ignore the packages whose sha1
        # matches SHA1 of the blacklisted project
        def addBlacklist(db_query, blacklist)
            if blacklist.length > 0 then
                db_query.cond <<
                { :field => "sha1", :not => true,
                  :sub_query => DBQuery.new({
                                                :qtype => [ "sha1" ],
                                                :cond  => [ {:field => "arch",:value =>@arch[:label]},
                                                            {:field => "project",:value => blacklist},
                                                          ],
                                                :limit => false,
                                                :order => false
                                            }).to_sql(@db_interface.table, true)[0]}
            end
        end

        # Find the full package name of a package from its SHA1 and the #arch
        #
        # Returns a Package with its pack field filled or nil
        #
        # Throws EmptyQueryException if the package was not found and required = true
        def queryPackage(package, sha1, required = false)
            query = DBQuery.new({
                :qtype => [ "name" ],
                :cond  => [ {:field => "sha1",:value =>sha1},
                            {:field => "arch",:value =>@arch[:label]},
                            {:field => "project",:value =>package.to_s}
                          ]
            })

            packageName = @db_interface.doQuery(query, required)
            return nil if packageName == WORK_EMPTY_QUERY

            if package.instance_of?(WorkEnvs::Package) then
                package.pack = packageName[0][0]
            else
                package = Package.new(package, {}, packageName[0][0])
            end
            return package
        end

        # Find the version of a package from its SHA1 and the #arch
        #
        # Returns the version String or nil
        #
        # Throws EmptyQueryException if the package was not found and required = true
        def queryPackageVersion(project, sha1, required = false)
            query = DBQuery.new({
                :qtype => [ "version" ],
                :cond  => [ {:field => "sha1",:value =>sha1},
                            {:field => "arch",:value =>@arch[:label]},
                            {:field => "project",:value =>project}
                          ]
            })

            packageVersion = @db_interface.doQuery(query, required)
            if packageVersion then
                return packageVersion[0][0]
            else
                return nil
            end
        end

        # Find the version of a package and its SHA1 from a package
        # full name and the #arch
        #
        # Returns dep_info (See #Dependencies) or nil
        #
        # Throws EmptyQueryException if the package was not found and required = true
        def queryDepInfosFromName(env, name, required)
            project = WorkEnvs::getMainPackage(env)
            query = DBQuery.new({
                :qtype => [ "version", "sha1" ],
                :cond  => [ {:field => "name",:value =>name},
                            {:field => "arch",:value =>@arch[:label]},
                            {:field => "project",:value =>project}
                          ]
            })
            addBlacklist(query, WorkEnvs::getBlackList(env))

            packageVersion = @db_interface.doQuery(query, required)
            return nil if packageVersion == WORK_EMPTY_QUERY
            return {
                :version => packageVersion[0][0],
                :sha1 => packageVersion[0][1]
            }
        end

        # Find the version of a package from its SHA1 and the #arch
        #
        # Returns dep_info (See #Dependencies) or nil
        #
        # Throws EmptyQueryException if the package was not found and required = true
        def queryDepInfosFromSHA1(env, sha1, required)
            project = WorkEnvs::getMainPackage(env)

            short_sha1 = nil
            if sha1 !~ /[0-9a-f]{40}/ then
                short_sha1 = sha1
                sha1 += "%"
            end
            query = DBQuery.new({
                :qtype => [ "version", "sha1" ],
                :cond  => [ {:field => "sha1",:value =>sha1},
                            {:field => "arch",:value =>@arch[:label]},
                            {:field => "project",:value =>project}
                          ],
                :limit => 1000
            })
            addBlacklist(query, WorkEnvs::getBlackList(env))

            packageVersion = @db_interface.doQuery(query, required)
            return nil if packageVersion == WORK_EMPTY_QUERY
            if short_sha1 != nil then
                if packageVersion.length > 1 then
                    raise("Multiple SHA1 matching the given prefix:\n" +
                          packageVersion.map(){|m| "\t#{m[1]}\t#{m[0]}\n"}.join(""))
                else
                    puts "INFO: short sha1 #{short_sha1} expanded to (#{packageVersion[0][1]}, #{packageVersion[0][0]})"
                end
            end
            return {
                :version => packageVersion[0][0],
                :sha1 => packageVersion[0][1]
            }
        end

        # Find the SHA1  package from its version string and the #arch
        #
        # Returns dep_info (See #Dependencies) or nil
        #
        # Throws EmptyQueryException if the package was not found and required = true
        def queryDepInfosFromVersion(env, version, required)
            project = WorkEnvs::getMainPackage(env)
            query = DBQuery.new({
                :qtype => [ "sha1" ],
                :cond  => [ {:field => "version",:value =>version},
                            {:field => "arch",:value =>@arch[:label]},
                            {:field => "project",:value =>project}
                          ]
            })
            addBlacklist(query, WorkEnvs::getBlackList(env))

            packageVersion = @db_interface.doQuery(query, required)
            return nil if packageVersion == WORK_EMPTY_QUERY
            return {
                :version => version,
                :sha1 => packageVersion[0][0]
            }
        end

        # Return an array all package names using this SHA1 and this #arch
        #
        # Throws EmptyQueryException if no packages were not found and required = true
        def queryMatchingSHA1(sha1, required = false)
            query = DBQuery.new({
                :qtype => [ "project" ],
                :cond  => [ {:field => "sha1",:value =>sha1},
                            {:field => "arch",:value =>@arch[:label]},
                          ],
                :limit => 10000
            })

            packageList = @db_interface.doQuery(query, required)
            return packageList.map(){|col| col[0]}
        end

        # Return an array all the branches that have packages for env
        #
        # Throws EmptyQueryException if no branches were not found
        def queryBranches(env)
            project = WorkEnvs::getMainPackage(env)
            query = DBQuery.new({
                :qtype => [ "branch" ],
                :cond  => [ {:field => "arch",:value =>@arch[:label]},
                            {:field => "project",:value =>project}
                          ],
                :group_by => "branch",
                :limit => 1000000
            })
            addBlacklist(query, WorkEnvs::getBlackList(env))
            branches = @db_interface.doQuery(query, true, false)
            return branches
        end

        # Query the limit last packages named name on teh select branch
        #
        # if branch = nil, all branches are looked at
        #
        # Returns an array of EnvPackage
        def queryPackages(project, branch=nil, limit=100000, blacklist=[])
            query = DBQuery.new({
                :qtype => [ "name", "sha1", "branch", "info" ],
                :cond  => [ {:field => "arch",:value =>@arch[:label]},
                            {:field => "project",:value => project},
                            {:field => "branch",:value => branch}
                          ],
                :limit => limit,
                :order => "id",
                :orderType => "desc"
            })
            addBlacklist(query, blacklist)

            result = @db_interface.doQuery(query, true, false)
            packages=[]
            idx = 0
            result.each() {|cols|
                next if cols[1] == nil || cols[0] == nil
                packages[idx] = EnvPackage.new(cols[0], cols[1], cols[2], cols[3])
                idx += 1
            }
            return packages
        end

        # Get a package full path
        #
        # Looks at all the possible package repositories to find a package
        # that matches package full name and arch
        #
        # Call by getPackagePath when path is not yet resolved
        #
        # Returns the package path
        #
        # Throws NoSuchFileException if the package could not be found and ignore_err = false
        def resolvePackagePath(package, ignore_err = false)
            packageName = package.pack.gsub(/^ */, "")
            @settings[:package_repos].each(){|url|
                type = url.split("://")[0]
                case(type)
                when "http", "https"
                    tables = @db_interface.table + @settings[:package_db_tables]
                    tables.uniq!
                    tables.each(){
                        |table|
                        path = "#{url}/#{table}/#{@arch[:distrib]}/#{@arch[:version]}/#{@arch[:arch]}/#{packageName}"
                        begin
                            runCmd("#{WORK_WGET_SPIDER_CMD} #{path}", @be_silent)
                            return path
                        rescue
                            return path if ignore_err == true
                        end
                    }
                when "file"
                    base = url.split("://")[1]
                    path = "#{type}://#{base}/#{packageName}"
                    puts "Checking file: #{path}" if !@be_silent
                    if File.exist?("#{base}/#{packageName}")
                        return path
                    end
                    path2 = "#{type}://#{base}/#{@arch[:distrib]}/#{@arch[:version]}/#{@arch[:arch]}/#{packageName}"
                    puts "Checking file: #{path2}" if !@be_silent
                    if File.exist?("#{base}/#{@arch[:distrib]}/#{@arch[:version]}/#{@arch[:arch]}/#{packageName}")
                        return path2
                    end
                    return path if ignore_err == true
                else
                    raise("Unsupported WORK_PACKAGE_REPO_PROTO: #{type}")
                end
            }
            raise NoSuchFileException.new(package, "in any repositories") if ignore_err != true
        end
        private :resolvePackagePath

        # Returns a Package path
        #
        # If the path is not set, call #resolvePackagePath to fill it
        #
        # Throws NoSuchFileException if the package could not be found and ignore_err = false
        def getPackagePath(package, ignore_err = false)
            return package.path if package.path != nil

            package.path = resolvePackagePath(package, ignore_err)
            return package.path
        end

        # Make sure that at least one package repository is accesible
        #
        # Throws an exception on failure
        def checkRepo()
            errors=[]
            raise("No package source provided") if @settings[:package_repos] == nil || @settings[:package_repos].length == 0
            @settings[:package_repos].each(){|url|
                urlType = url.split('://')[0]
                case(urlType)
                when "http", "https"
                    path = "#{url}/#{@db_interface.table[0]}/"+
                           "#{@arch[:distrib]}/#{@arch[:version]}/#{@arch[:arch]}/"
                    begin
                        runCmd("#{WORK_WGET_SPIDER_CMD} #{path}", @be_silent)
                        return
                    rescue
                        errors << "Could not connect to server #{url}"
                    end
                when "file"
                      base = url.split("://")[1]
                      if !File.exist?(base) then
                          errors << "Local package repository '#{base}' does not exists"
                      else
                          return
                      end
                else
                    errors << "Unsupported WORK_PACKAGE_REPO_PROTO: #{url}"
                end
            }
            raise("Could not find any accessible package repositories\n" + errors.join("\n"))
        end

        # Returns true if Packahe is a gzip package
        def isGzipPackage?(package)
            return runTest("file #{package} | grep \"gzip\" >/dev/null  2>&1 ", @be_silent)
        end
        private :isGzipPackage?

        # Extracts all the dependencies from a RPM file and store them in deps
        #
        # Format
        # dep[ depName ] :
        # - [ :operator ] :  <, <=, =, >= or >
        # - [ :version ] : Version required
        # - { :provided ] : true if it is provided for
        #
        # This is used to extract all dependencies (not internal to envs)
        def getLocalPackageDependencies(packageName, deps = {})
            raise("Feature only supported on RHEL/Centos/Fedora packages") if @arch[:base] != "RHEL"

            return if(isGzipPackage?(packageName))

            runCmd("rpm -qp --requires #{packageName}",
                   @be_silent).chomp().split("\n").each(){|line|

                next if line !~ /([^ ]+)( +([<>=]+) +(.*))?$/

                if deps[$1] != nil and $2 != nil then
                    package=$1
                    operator = $3
                    version = $4
                    if (deps[package][:version] !~ /#{version}(.el5)?/ &&
                        version !~ /#{deps[package][:version]}(.el5)?/) && deps[package][:version] == '=' &&
                            operator == '='
                        raise("Incompatible dependencies: Package '#{package}' is required in "+
                              "version #{deps[package][:version]} and #{version}")
                    end
                elsif deps[$1] == nil
                    deps[$1] = {}
                    deps[$1][:operator] = $3
                    deps[$1][:version] = $4
                end
            }
            runCmd("rpm -qp --provides #{packageName}",
                   @be_silent).chomp().split("\n").each(){|line|

                next if line !~ /([^ ]+)( +([<>=]+) +(.*))?$/

                if deps[$1] != nil and $2 != nil then
                    package=$1
                    version = $4
                    if (deps[package][:version] !~ /#{version}(.el5)?/ &&
                        version !~ /#{deps[package][:version]}(.el5)?/) && deps[package][:version] == '=' then
                        raise("Incompatible dependencies: Package '#{package}' is required in "+
                              "version #{deps[package][:version]} and #{version}")
                    end
                    deps[package][:provided] = true
                elsif deps[$1] != nil
                    deps[$1][:provided] = true
                else
                    deps[$1] = {}
                    deps[$1][:provided] = true
                    deps[$1][:operator] = $3
                    deps[$1][:version] = $4
                end
            }

            return deps
        end
        private :getLocalPackageDependencies

        # Download a Package
        #
        # Rename if to output if set
        #
        # The package is downloaded in the current directory
        def download(package, output = nil)
            path = getPackagePath(package)
            output = File.basename(path) if output == nil
            type = path.split("://")[0]
            case type
            when "http", "https"
                runCmd("#{WORK_WGET_CMD} -O #{output} #{path}", @be_silent)
            when "file"
                base = path.split("://")[1]
                runCmd("#{WORK_CP_CMD} #{base} #{output}", @be_silent)
            else
                raise("Unsupported protocol #{type}")
            end
        end

        # Download a Package to the current directory
        #
        # Extract if if extract is true
        #
        # Erase afterwars if erase is set
        #
        def downloadAndExtract(package, extract, erase)
            packageName = package.pack.gsub(/^ */, "")
            runCmd("rm -f #{packageName}", @be_silent)

            if @be_silent
                puts "\t#{packageName}\n"
            end
            download(package)

            return if(extract != true)


            if(isGzipPackage?(packageName)) then
                runCmd("tar --atime-preserve=system -zxf #{packageName} 2>&1 || "+
                       "tar -zxf #{packageName} 2>&1", @be_silent)
            else
                case(@arch[:base])
                when "debian"
                    runCmd("dpkg --extract #{packageName} . 2>&1", @be_silent)
                when "RHEL"
                    runCmd("rpm2cpio #{packageName} | cpio -id 2>&1", @be_silent, 5)
                else
                    raise("Invalid package type")
                end
            end
            if deps != nil
                getLocalPackageDependencies(packageName, deps)
            end
            runCmd("rm -f #{packageName}", @be_silent) if erase == true
        end

        # Remove a the installed versions of Packages from the system (RPM/RHEL only)
        #
        # Throws an exception in uninstall failed
        #
        # Called by installPackages to remvoe former packages prior to enw install
        def removePackage(package)
            package = package.pack.gsub(/^ */, "")
            raise ("Package '#{package}' is missing") if !File.exist?(package)

            driver=runCmd("rpm -qp --qf='%{NAME}' #{package}", @be_silent)
            installed = system("rpm -q #{driver}")
            if(installed) then
                begin
                    @semaphore.synchronize {
                        runCmd("sudo yum -y -q remove #{driver} || sudo yum -y -q remove #{driver}", @be_silent)
                    }
                rescue => e
                    # Because we do it in //, we may have a race condition to uninstall this one
                    # So if it failed, just check if it's still there. If not, don't bother
                    installed = system("rpm -q #{driver}")
                    raise e if installed
                end
            end
        end
        private :removePackage

        # Install packages on the system (yum, dpkg)
        #
        # Remove them prior to install using #removePackage
        #
        # Throws exception on unsupported arch, uninstall or install failure
        def installPackages(packages)
            pack_list=[]
            packages.each(){|pack|

                removePackage(pack)
                package = pack.pack.gsub(/^ */, "")
                raise ("Package '#{package}' is missing") if !File.exist?(package)

                pack_list << package
            }
            case(@arch[:base])
            when "debian"
                raise("Do not know how to install DEB packages automatically")
            when "RHEL"
                puts "Installing"
                runCmd("sudo rpm -i #{pack_list.join(" ")}", @be_silent)
            else
                raise("Invalid package type")
            end
        end

        # Fetch the full names of two lists of Package matching sha1 and #arch
        #
        # This is used to generate a list of Package needed when updating an env
        #
        # Throws EmptyQueryException if a package in required could not be found
        #
        # Returns an array of Packages
        def getPackagesName(required, extras, sha1)
            packages = []
            required.each() {|p|
                package = queryPackage(p, sha1, true)

                next if package == nil

                list = package.pack.split("\n")
                if list.length > 1 then
                    STDERR.puts "###################################################"
                    STDERR.puts "# ERROR: Query returned more than one package     #"
                    STDERR.puts "# in a single DB entry.....                       #"
                    list.each(){|pack|
                        STDERR.puts "# => #{pack}".ljust(50) + "#"
                    }
                    STDERR.puts "###################################################"
                    raise()
                end
                packages << package
            }
            extras.each() {|p|
                package = queryPackage(p, sha1, false)
                next if package == nil

                list = package.pack.split("\n")
                if list.length > 1 then
                    STDERR.puts "###################################################"
                    STDERR.puts "# ERROR: Query returned more than one package     #"
                    STDERR.puts "# in a single DB entry.....                       #"
                    list.each(){|pack|
                        STDERR.puts "# => #{pack}".ljust(50) + "#"
                    }
                    STDERR.puts "###################################################"
                    raise()
                end
                packages << package
            }
            return packages
        end

        # Extract dependencies (RPM, Deb)  from a Package
        #
        # - Try to fetch the dependencies from the DB
        # - On failure
        #   - Get the dependencies from the package
        #   - Publish them to the dependencies DB
        #
        # Returns a list of dependencies string
        def listDependencies(pack)
            remotePack = getPackagePath(pack)
            extname = File.extname(remotePack)
            return [] if(extname != ".deb" and extname != ".rpm")
            res = nil

            file = runCmd("mktemp", true)

            tables = @db_interface.table + @settings[:package_db_tables]
            tables.uniq!

            # Try to do it on the SQL server first
            query = DBDepsQuery.new({
                :qtype => [ "dependencies" ],
                :cond  => [ {:field => "name",:value => pack.pack },
                            {:field => "arch",:value =>@arch[:label] }
                          ],
                :limit => 1,
            })
            begin
                res = @db_interface.doDepQuery(query)[0][0].to_s.split("\n")
                return res
            rescue => e
            end

            runCmd("rm -f #{file}", true)
            case(@arch[:base])
            when "RHEL"
                res = runCmd("rpm -qp --requires #{remotePack} 2>/dev/null ", @be_silent).split("\n")
            when "debian"
                file = runCmd("mktemp", true)
                download(pack, file)
                res = runCmd("dpkg --info #{file}  | /bin/grep -E '^ Depends:'",
                             @be_silent).gsub(/^ Depends: /, '').split(", ")
                runCmd("rm -f #{file}", @be_silent)
            else
                raise("Invalid package type")
            end

            begin
                query = DBDepsQuery.new({
                    :cond  => [ {:field => "name",:value => pack.pack },
                                {:field => "arch",:value => @arch[:label] },
                                { :field => "dependencies", :value => res.join("\n") },
                              ],
                    :insert => true
                                        })
                @db_interface.doInsertDep(query)
            rescue
            end
           return res
        end

        # Look for depenency to the package name in a list generated by #listDependencies
        #
        # Return the version of name required
        def extractDependency(dependencies, name)
            res = nil
            case(@arch[:base])
            when "RHEL"
                dependencies.each(){|line|
                    next if line !~ /#{name}[[:space:]]*=/
                    res = line.gsub(/\.(fc|el)[0-9]*$/, '').gsub(/.*=[[:space:]]*(.*)$/, '\1')
                    puts "Dependency to: #{name} = #{res} " if @be_silent == false
                    return res
                }
            when "debian"
                dependencies.each(){|line|
                    next if line !~ /^#{name}[[:space:]]*\(/
                    res = line.gsub(/.*=[[:space:]]*/, '').gsub(/\)/, '')
                    puts "Dependency to: #{name} = #{res} " if @be_silent == false
                    return res
                }
            else
                raise("Invalid package type")
            end
            return res
        end
    end
end
