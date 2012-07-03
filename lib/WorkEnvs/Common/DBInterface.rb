#!/usr/bin/ruby
if !ENV["WENV_WITHSQL"].nil? then
    begin
        # Load MySQL2 module
        require 'mysql2'
        #Ugly hack not to laod MySQL2 if we really want to test MySQL1
        raise LoadError if !ENV["WENV_FORCE_SQL1"].nil?
        raise ("Version 0.4.1 of Mysql2 is broken. Please use another version") if Mysql2::VERSION == "0.4.1"
    rescue LoadError
        begin
            require 'mysql'
        rescue LoadError
            raise("Neither ruby-mysql nor ruby-mysql2 are available on this system")
        end
    end
    begin
        require 'sqlite3'
    rescue LoadError
    end
end
require 'uri'
require_relative 'PackageDownloader'

module WorkEnvs
    # Empty 2D array to to return when select provided no results
    WORK_EMPTY_QUERY = [[nil]]

    # Max number of retrying a query. Used to handle bad connections
    MAX_ERROR_RETRY = 3

    # Maximum duration of a SQL query before trigging a warning when #DEBUG_QUERIES is true
    WENV_SLOW_QUERY_THRESHOLD = 1e-0

    # Flag to enable tracking of slow queries
    DEBUG_QUERIES = ((ENV["DEBUG_QUERIES"] != nil) ? true: false)

    # Exception thrown when executing a query on a DB object failed
    class QueryErrorException < StandardError
        # Constructor
        #
        # - query is the query string that caused the failure
        # - table is the table on which the query was executed
        # - msg is an additional error message to print (default = nil)
        def initialize(query, table, msg=nil)
            super("\nERROR: Error while executing query:\n" + query.to_s(table) + "\n" + msg.to_s)
        end
    end

    # Exception thrown when executing a select query did not returned any results
    class EmptyQueryException < StandardError
        # Constructor
        #
        # - query is the query string that caused the failure
        # - table is the table on which the query was executed
        def initialize(query, table)
            super("\nERROR: Found no match in the database for query:\n" + query.to_s(table))
        end
    end

    # Interface to execute DBQuery on a SQL database
    class DBInterface
        # Array of table names to search into (default extracted from settings)
        attr_reader :table
        # Object to connect to database. Abstract ruby-mysql, ruby-mysql2 or sqlite3
        attr_reader :db
        # When false, enable verbose mode (default = true)
        attr_accessor :be_silent

        # Convert a table string issue from the command line to an array of table
        #
        # - If nil or false, get the default table string from settings
        # - If true, only use the "releases" table (legacy from --release option)
        # - If a string, convert to an array containing the string
        def self.toTable(table)
            case table
            when nil, false
                return WorkEnvs.settings[:db][:package_default_table].split(":").
                    inject([]){|glob, t| glob + DBInterface::toTable(t)}
            when true
                return [ "releases" ]
            else
                return [ table ]
            end
        end

        # Connect to a MySQL database
        #
        # Tries to connect with ruby-mysql2 (unless WENV_FORCE_SQL1)
        # fallback to ruby-mysql
        #
        # Returns:
        # - a DB connection object (nil on error)
        # - a label with the db type (:mysql, :mysql2, :http on error)
        def _connectMySQL(db_server, db_user, db_passwd, db_name)
            begin
                raise("Skip") if !ENV["WENV_FORCE_SQL1"].nil?
                return Mysql2::Client.new(:host => db_server,
                                          :username => db_user,
                                          :password => db_passwd,
                                          :database => db_name), :mysql2
            rescue => e
            end
            begin
                return Mysql.new(db_server, db_user, db_passwd, db_name), :mysql
            rescue => e
            end
            return nil, :http
        end
        private :_connectMySQL


        # Connect to a MySQL database
        #
        # Extract the proper settings from the settings args and call _connectMySQL
        #
        # Returns:
        # - a DB connection object (nil on error)
        # - a label with the db type (:mysql, :mysql2, :http on error)
        def connectMySQL(settings)
            return _connectMySQL(settings[:package_db], settings[:package_db_user], settings[:package_db_passwd],
                                 settings[:package_db_db])
        end
        private :connectMySQL

        # Default constructor
        def initialize(machine = nil, table=nil, silent=true)
            @settings = WorkEnvs::settings[:db]

            @table = []
            if table.instance_of?(Array) then
                @table = table
            elsif table.to_s == "" then
                @table = self.class::toTable(nil)
            else
                @table = table.to_s.split(":").inject([]){|glob, t| glob + DBInterface::toTable(t)}
            end
            @be_silent = silent
            @admin = false
            @dbType = @settings[:package_db_proto]

            case @settings[:package_db_proto]
            when :mysql
                @db,@dbType = connectMySQL(@settings)
                raise("Unable to connect to MySQL Database #{@settings[:package_db]}") if @db == nil
            when :http,:https
                @db,@dbType = connectMySQL(@settings)
                if @dbType == :http
                    STDERR.puts "HTTP Query are not supported any more"
                    STDERR.puts "Please make sure you have ruby mysql or mysql2 installed"
                    raise("Protocol Fix")
                end
            when :sqlite
                raise("SQLite DB '#{@settings[:package_db]}' not found." +
                      " Use --package-db option") if !File.exist?(@settings[:package_db])
                begin
                    @db = SQLite3::Database.open(@settings[:package_db])
                    @admin = true
                rescue => e
                    raise("Unable to connect to SQLite Database #{@settings[:package_db]}: #{e.to_s}")
                end
            else
                raise("Unsupported DB protocol #{@settings[:package_db_proto].to_s}")
            end
            puts "Connected to DB '#{@settings[:package_db]}' using #{@dbType.to_s}" if @be_silent != true
        end

        # Switch the DB connection to an "admin" mode where insert are possible
        #
        # Note does not work with SQLite DB
        def doAdminConnect(db_user = @settings[:package_db_user],
                           db_passwd = @settings[:package_db_passwd],
                           db_server = @settings[:package_db],
                           db_name = @settings[:package_db_db])
            @db, @dbType = _connectMySQL(db_server, db_user, db_passwd, db_name)
            raise("Failed to connect as Admin to the database") if @db == nil
            @admin = true
        end

        # Execute a DBQuery insert query
        #
        # Throw EmptyQueryException on error
        # Returns an error string if DBInterface is not in admin mode
        def doInsert(query)
            return "Admin mode must be enable before inserting..." if @admin != true
            hasInfo = false
            query.cond.each(){|el| hasInfo == true if el[:field] == "info" && el[:value].to_s != "" }
            query.cond << { :field => "info", :value => `date`.chomp()} if hasInfo == false
            begin
                doQueryInternal(query, @table)
            rescue EmptyQueryException
            end
        end

        # Execute a DBDepsQuery insert query
        #
        # Admin mode is not required
        #
        # Returns an error string if DBInterface is not in admin mode
        def doInsertDep(query)
            begin
                doQueryInternal(query, [ "dependencies" ])
            rescue EmptyQueryException
            end
        end

        # Convert results generated by the @db object while executing a query into
        # an 2 dimensional array [result_id][field]
        #
        # Throws EmptyQueryException if there are no results
        # Throws QueryErrorException on internal error
        def extractResults(query, table, result, dbType)
            case dbType
            when :mysql
                raise EmptyQueryException.new(query, table) if result.nil? or result.num_rows < 1
                fieldPos={}; idx = 0
                result.result_metadata.fetch_fields.each() { |field|
                    fieldPos[field.name] = idx
                    idx +=1
                }
                resultTable = []
                result.each(){|line|
                    resultEntry = []
                    query.qtype.map{ |x|
                        resultEntry << "#{line[fieldPos[x]]}"
                    }
                    resultTable << resultEntry
                }
                return resultTable
            when :sqlite
                raise EmptyQueryException.new(query, table) if result.nil?

                hasResult = false

                fieldPos={}; idx = 0
                resultTable = []
                result.each(){|line|
                    hasResult = true
                    resultTable << line
                }
                raise EmptyQueryException.new(query, table) if !hasResult
                return resultTable
            when :mysql2
                if result.nil? or result.count < 1
                    raise EmptyQueryException.new(query, table)
                else
                    resultTable=[]
                    result.each(){|row|
                        resultEntry=[]
                        query.qtype.each(){|field|
                            resultEntry << row[field]
                        }
                        resultTable << resultEntry
                    }
                    return resultTable
                end
            when :http
                file = result
                breakExpr = "-e 's/<[bB][rR][[:space:]]*\\/>/\\n/g'"
                result = runCmd("sed -e 's/.*<BODY>//' -e 's/<\\/BODY>.*//' #{breakExpr} #{file}", @be_silent)
                runCmd("rm -f #{file}", @be_silent)
                if result == "Error querying DB"
                    raise QueryErrorException.new(query, table)
                elsif result == "Error not found"
                    raise EmptyQueryException.new(query, table)
                end
                resultTable = []
                result.split(/[\n,]/).each(){|line|
                    resultEntry = line.split("&nbsp;")
                    resultTable << resultEntry
                }
                return resultTable
            else
                raise("Internal error")
            end
        end
        private :extractResults

        # Internal function to execute a DBQuery (or any class inherting it)
        #
        # Convert the DBQuery into string (+ arg) and run the query.
        #
        # Returns result process by extractResults (two dimensional array)
        # Throw QueryErrorException @db failed to execute the query
        #
        # Note: by setting the env variable DEBUG_QUERIES, it will print a message
        # if queries are slower than WENV_SLOW_QUERY_THRESHOLD
        def doQueryInternal(query, tables)
            result=nil
            startTime=Time.now()
            case @dbType
            when :mysql
                queryStr, args = query.to_sql(tables)
                begin
                    db_query = @db.prepare(queryStr)
                    puts query.to_s(tables) if @be_silent != true
                    result = db_query.execute(*args)
                rescue => e
                    raise QueryErrorException.new(query, tables, e.to_s)
                end
            when :sqlite
                queryStr, args = query.to_sql(tables)
                begin
                    db_query = @db.prepare(queryStr)
                    puts query.to_s(tables) if @be_silent != true
                    result = db_query.execute(*args)
                rescue => e
                    raise QueryErrorException.new(query, tables, e.to_s)
                end
            when :mysql2
                queryStr = query.to_sql2(tables)
                begin
                    puts query.to_s(tables) if @be_silent != true
                    result = @db.query(queryStr)
                rescue => e
                    p e
                    raise QueryErrorException.new(query, tables, e.to_s)
                end
            else
                raise("Internal error")
            end
            endTime = Time.now()
            if DEBUG_QUERIES and (endTime - startTime) > WENV_SLOW_QUERY_THRESHOLD then
                STDERR.puts "# Warning slow query (#{endTime - startTime})"
                puts "#\t" + query.to_s(tables)
          end
            return extractResults(query, tables, result, @dbType)
        end
        private :doQueryInternal

        # Execute a DBQuery select query
        #
        # Calls doQueryInternal
        #
        # - If all_tables is true, query is ran on the provided tables and
        #   all the table referenced as valid in the settings
        # - If all_tables is false the query is only ran on the provided tables
        #
        # Throws EmptyQueryException if required = true and no results were returned
        # Throws QueryErrorException if the query failed
        #
        # Returns a two dimensionnal array containing the results
        def doQuery(query, required = true, all_tables = true, tables = @table)
            raise("Invalid query object") if query.class != DBQuery && query.class != DBDepsQuery
            e = nil
            result = nil

            if all_tables == true then
                tables += @settings[:package_db_tables]
                tables.uniq!
            end

            count = 0
            begin
                begin
                    count  = count + 1
                    result = doQueryInternal(query, tables)
                    puts "Result: #{result.join("\n")}" if @be_silent != true

                rescue EmptyQueryException => e
                    puts "Result: <none>" if @be_silent != true
                rescue QueryErrorException => e
                    puts "Query Error" if @be_silent != true
                end
            end while e.class == QueryErrorException  && count < MAX_ERROR_RETRY
            raise e if e.class == QueryErrorException

            return result if result != nil

            if required != false
                raise EmptyQueryException.new(query, table)
            else
                return WORK_EMPTY_QUERY
            end
        end

        # Wrapper around doQuery to query DBDepsQuery
        #
        # Calls doQuery with the appropriate settings
        def doDepQuery(query)
            return doQuery(query, true, false, [ "dependencies" ])
        end
    end

    # Database query
    class DBQuery
        # Array of DB fields allowed in conditions
        Fields = ["sha1", "project", "name", "version", "branch", "arch"]

        # Array of fields (String) to be queryed (default Fields)
        attr_reader :qtype
        # Hash describing matching conditions (default {})
        # - :field => field to match in the condition
        # - :not => IF true, checks field value is NOT value (default false)
        # - :value => value to check against
        # - :sub_query => DBQuery to run and check field against its results
        #
        # :sub_query and :value cannot be specified at the same time
        attr_reader :cond
        # Group result by this field (default nil)
        attr_reader :group_by
        # - :limit => Max number of results (default 1)
        attr_reader :limit
        # - :order => Field to use for sorting (default "id")
        attr_reader :order
        # - :orderType => Sorting order (default "ASC")
        attr_reader :orderType
        # - :insert => query is an insert, not a select (default false)
        attr_reader :insert

        # Constructor
        #
        # queryHash describe the request content
        #
        # Mapping is bascially @<field> = queryHash [ :<field> ]. See attributes for more infos.
        #
        # The constructor convert the input value into SQL compliant ones
        def initialize(queryHash = {})
            @qtype = Fields
            @qtype = queryHash[:qtype] if queryHash[:qtype] != nil
            @cond = {}
            @cond = queryHash[:cond] if queryHash[:cond] != nil
            @group_by = ""
            @group_by = queryHash[:group_by] if queryHash[:group_by] != nil
            @limit = "LIMIT 1"
            if queryHash[:limit] == false then
                @limit = ""
            elsif queryHash[:limit] != nil then
                @limit = "LIMIT " + queryHash[:limit].to_s()
            end
            @order = "ORDER BY id"
            @orderType = "ASC"
            @orderType = queryHash[:orderType] if queryHash[:orderType] != nil

            if queryHash[:order] == false
                @order = ""
                @orderType = ""
            elsif queryHash[:order] != nil
                @order = "ORDER BY " + queryHash[:order].to_s()
            end
            @insert = false
            @insert = queryHash[:insert] if queryHash[:insert] != nil
        end

        # Internal method to convert a select DBQuery to a SQL String usable with ruby-mysql or sqlite
        #
        # Used by to_sql
        #
        # Returns:
        # - a query String
        # - an array of arguments to be inserted in the string when executing the query
        def to_sql_select(tables, inplace)
            condition = ''
            args=[]
            if @cond != nil && @cond.length != 0 then
                condition = 'WHERE ' + @cond.map(){|x|
                    vals = x[:value]

                    if vals != nil then
                        vals = [ vals ] if !vals.kind_of?(Array)
                        args += vals

                        (x[:not] == true ? "NOT" : "") +
                            " (" + vals.map(){|v|
                            x[:field] + "  LIKE " + (inplace ? "'#{v}'" : "?")
                        }.join(" OR ") + ")"
                    else
                        "#{x[:not] == true ? "NOT" : ""} (" +
                            x[:field] + "  IN #{x[:sub_query]})"
                    end
                }.join(" AND ")

            end

            groupBy = ''
            groupBy = "GROUP BY #{@group_by}" if @group_by.to_s != ""


            queryStr=  tables.map(){|table|
                "( select #{@qtype.join(',')} from #{table} "+
                "#{condition} #{groupBy} #{@order} #{@orderType} " + @limit + " )"
            }.join(" UNION ") +
                       (tables.length > 1 && @limit.to_s != "" ? " #{@limit}" : "")
            queryArgs = tables.inject([]){|x, y| x + args }
            return queryStr, queryArgs
        end
        private :to_sql_select

        # Internal method to convert an insert DBQuery to a SQL String usable with ruby-mysql or sqlite
        #
        # Used by to_sql
        #
        # Returns:
        # - a query String
        # - an array of arguments to be inserted in the string when executing the query
        def to_sql_insert(tables, inplace)
            raise("No content to insert") if @cond.empty?

            queryArgs=[]

            queryStr = "INSERT INTO #{tables[0]} (" +
                       @cond.map(){|el| queryArgs << el[:value]; el[:field].to_s}.join(",") + ") VALUES (" +
                       @cond.map(){|el| inplace == true ? el[:value].to_s : "?"}.join(",") + ")"
            return queryStr, queryArgs
        end
        private :to_sql_insert

        # Convert any DBQuery to a SQL String usable with ruby-mysql or sqlite
        #
        # Uses to_sql_insert or to_sql_select depending on the #insert attribute
        #
        # Returns:
        # - a query String
        # - an array of arguments to be inserted in the string when executing the query
        def to_sql(tables, inplace=false)
            if @insert == true then
                to_sql_insert(tables, inplace)
            else
                to_sql_select(tables, inplace)
            end
        end

        # Internal method to convert a select DBQuery to a SQL String usable with ruby-mysql2
        #
        # Used by to_sql2
        #
        # Returns a query String with arguments inlines
        def to_sql2_select(tables)
            condition = ''
            if @cond != nil && @cond.length != 0 then
                condition = 'WHERE ' + @cond.map(){|x|

                    vals = x[:value]
                    if vals != nil then
                        vals = [ vals ] if !vals.kind_of?(Array)

                        (x[:not] == true ? "NOT" : "") +
                            " (" + vals.map(){|v|
                            x[:field] +" LIKE '#{Mysql2::Client.escape(v.to_s)}'"
                        }.join(" OR ") + ")"
                    else
                        "#{x[:not] == true ? "NOT" : ""} (" +
                            x[:field] + "  IN #{x[:sub_query]})"
                    end
                }.join(" AND ")
            end

            groupBy = ''
            groupBy = "GROUP BY #{@group_by}" if @group_by.to_s != ""

            return tables.map(){|table|
                queryStr= "select #{@qtype.join(',')} from #{table} "+
                          "#{condition} #{groupBy} #{@order} #{@orderType} " + @limit
                "( " + queryStr + " )"
            }.join(" UNION ") +
                           (tables.length > 1 && @limit.to_s != "" ? " #{@limit}" : "")
        end
        private :to_sql2_select

        # Internal method to convert an insert DBQuery to a SQL String usable with ruby-mysql2
        #
        # Used by to_sql2
        #
        # Returns a query String with arguments inlines
        def to_sql2_insert(tables)
            raise("No content to insert") if @cond.empty?


            queryStr = "INSERT INTO #{tables[0]}(" +
                       @cond.map(){|el| el[:field].to_s}.join(",") + ") VALUES (" +
                       @cond.map(){|el| "'" + Mysql2::Client.escape(el[:value].to_s) + "'"}.join(",") + ")"
            return queryStr
        end
        private :to_sql2_insert

        # Convert any DBQuery to a SQL String usable with ruby-mysql2
        #
        # Uses to_sql2_insert or to_sql2_select depending on the #insert attribute
        #
        # Returns a query String with arguments inlines
        def to_sql2(tables)
            if @insert == true then
                to_sql2_insert(tables)
            else
                to_sql2_select(tables)
            end
        end

        # Convert a query to a string for logging and exceptions
        def to_s(tables=["??"])
            return "Query: " + self.to_sql(tables, true)[0]
        end
    end

    # Variation of DBQuery
    #
    # Override the Fields attribute to fir the dependency DB
    class DBDepsQuery < DBQuery
        # Array of Dependency DB fields allowed in conditions
       Fields = ["name", "arch", "dependencies"]
        # Default constructor
        def initialize(queryHash = {})
            super(queryHash)
            @qtype = Fields
            @qtype = queryHash[:qtype] if queryHash[:qtype] != nil
        end

    end
end
