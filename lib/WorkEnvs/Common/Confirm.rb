# -*- coding: utf-8 -*-

module WorkEnvs
    # Exception thrown by Confirm when confirm dialog is aborted
    class ConfirmAbortedException < StandardError
        # Default constructor
        def initialize()
            super("Aborted...")
        end
    end

    # Create a confirmation" dialog"
    #
    # Asks user to reply yes/no if neither --yes or --no is set
    #
    # Return true for yes, false for no
    class Confirm
        # Default constructor
        #
        # str is the string to prompt the user ebfore asking yes/no
        def initialize(str)
            while true do
                printf str + " (y(es)/N(o)): "
                if WorkEnvs::settings()[:global][:alwaysYes] == true
                    puts "(--yes option enabled)"
                    return
                end
                if WorkEnvs::settings()[:global][:alwaysNo] == true
                    puts "(--no option enabled)"
                    raise ConfirmAbortedException
                end
                rep = STDIN.gets.to_s().chomp().downcase()
                case rep
                when "y","yes"
                    return
                when "n","no"
                    raise ConfirmAbortedException
                else
                    puts "Are you sure you can read ? That question was not that hard..."
               end
            end
       end
    end

    # Variation of the Confirm class that support --always
    #
    # Return true, (yes), false (no) or :always (always)
    class OverWrite
        # Prompt the user the str string and ask for an answer (yes, no, always)
        #
        # lastValue should be nil for the first call
        # if lastValue == :always, returns ::always
        def self.check(str, lastVal)
            return :always if lastVal == :always
            while true do
                printf str + " (y(es)/N(o)/a(lways)): "
                if WorkEnvs::settings()[:global][:alwaysYes] == true
                    puts "(--yes option enabled)"
                    return :always
                end
                if WorkEnvs::settings()[:global][:alwaysNo] == true
                    puts "(--no option enabled)"
                    return false
                end
                rep = STDIN.gets.chomp().downcase()
                case rep
                when 'y', 'yes'
                    return  true
                when 'n', 'no'
                    return false
                when 'a', 'always'
                    return :always
                else
                    puts "Please remove your mitten before typing anymore wrong answers..."
                end
            end
       end
    end

end
