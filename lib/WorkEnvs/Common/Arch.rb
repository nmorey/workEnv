#!/usr/bin/ruby
module WorkEnvs

    # Returns a hash describing a host setup
    #
    # if machine is passed, it overrides host detection and used machine string instead
    #
    # Return format is
    # - :label: machine string or generated string that can be passed to getArch
    # - :distrib: machine distribution (mingw, centos, debian, fedora, ubuntu, unknown)
    # - :version: Distrib version
    # - :arch: Core architecture (i386, x86_64)
    # - :base: Distribution base (RHEL, debian, WINNT, unknown)
    def getArch(machine = nil, ignore_settings = false)
        arch = {}
        machine = WorkEnvs::settings[:arch][:machine] if machine == nil && ignore_settings == false

       if machine == nil
         uname=`uname -s`.chomp()
         if(uname =~ /^MINGW([0-9]{2})_NT-([0-9]+\.[0-9]+)/) then
           machine="mingw#{$2}-#{$1}"
         else
            machine=`get_machine() {
	ARCH=$(uname -m)
	ARCH_S="32"
	if [ "$ARCH" = "x86_64" ]; then
		ARCH_S="64";
	fi

	if [ -f /etc/fedora-release ]; then
        FC_NUM=$(sed -e 's/^Fedora release \\([0-9]\\+\\) .*$/\\1/' /etc/fedora-release)
		echo "fedora${FC_NUM}-${ARCH_S}";
	elif [ -f /etc/redhat-release ]; then
        if grep -q "Red Hat" /etc/redhat-release ; then
            if grep -q ' 5\\.' /etc/redhat-release ; then
                echo "redhat5-${ARCH_S}";
            elif grep -q ' 6\\.' /etc/redhat-release ; then
                echo "redhat6-${ARCH_S}";
            elif grep -q ' 7\\.' /etc/redhat-release ; then
                echo "redhat7-${ARCH_S}";
            else
                echo "Unsupported centos/RHEL version"
				exit 1
            fi
        elif grep -q "CentOS" /etc/redhat-release ; then
            if grep -q ' 5\\.' /etc/redhat-release ; then
                echo "centos5-${ARCH_S}";
            elif grep -q ' 6\\.' /etc/redhat-release ; then
                echo "centos6-${ARCH_S}";
            elif grep -q ' 7\\.' /etc/redhat-release ; then
                echo "centos7-${ARCH_S}";
            else
                echo "Unsupported centos/RHEL version"
				exit 1
            fi
        else
            echo "Unsupported centos/RHEL version"
			exit 1
        fi
	elif [ -f /etc/lsb-release ]; then
		. /etc/lsb-release
		VER=$(echo ${DISTRIB_RELEASE} | sed -e 's/\\.//g')
		echo "ubuntu${VER}-${ARCH_S}"
	elif [ -f /etc/debian_version ]; then
		VER=$(cat /etc/debian_version | sed -e 's/\\.[0-9]*//g')
		echo "debian${VER}-${ARCH_S}";
	else
        source /etc/os-release
        echo "$ID_LIKE" | grep -q "suse"
        if [ $? -eq 0 ]; then
            echo "suse$(echo ${VERSION_ID} | sed -e 's/\\..*$//')-${ARCH_S}"
        else
        	echo "Unknown"
	        return  1;
        fi
	fi
	return 0;
	}
	get_machine`
                raise("Failed to get Arch (#{$?}): #{machine}") if $? != 0
            machine.chomp!()
         end
        end
        case(machine)
        when /debian([0-9]+)-32/
            arch[:version]=$1
            arch[:label]="debian#{arch[:version]}-32"
            arch[:distrib]="debian"
            arch[:arch]="i386"
            arch[:base]="debian"
        when /debian([0-9]+)-64/
            arch[:version]=$1
            arch[:label]="debian#{arch[:version]}-64"
            arch[:distrib]="debian"
            arch[:arch]="amd64"
            arch[:base]="debian"
        when "ubuntu804-32"
            arch[:label]="debian5-32"
            arch[:distrib]="debian"
            arch[:version]="5"
            arch[:arch]="i386"
            arch[:base]="debian"
        when "ubuntu804-64"
            arch[:label]="debian5-64"
            arch[:distrib]="debian"
            arch[:version]="5"
            arch[:arch]="amd64"
            arch[:base]="debian"
        when "ubuntu1004-32"
            arch[:label]="debian6-32"
            arch[:distrib]="debian"
            arch[:version]="6"
            arch[:arch]="i386"
            arch[:base]="debian"
        when "ubuntu1004-64"
            arch[:label]="debian6-64"
            arch[:distrib]="debian"
            arch[:version]="6"
            arch[:arch]="amd64"
            arch[:base]="debian"
        when /fedora([0-9]+)-32/
            arch[:version]=$1
            arch[:label]="fedora#{arch[:version]}-32"
            arch[:distrib]="fedora"
            arch[:arch]="i386"
            arch[:base]="RHEL"
        when /fedora([0-9]+)-64/
            arch[:version]=$1
            arch[:label]="fedora#{arch[:version]}-64"
            arch[:distrib]="fedora"
            arch[:arch]="x86_64"
            arch[:base]="RHEL"
        when /^centos([0-9]+)-32$/
            arch[:version]=$1
            arch[:label]="centos#{arch[:version]}-32"
            arch[:distrib]="centos"
            arch[:arch]="i386"
            arch[:base]="RHEL"
        when /^centos([0-9]+)-64$/
            arch[:version]=$1
            arch[:label]="centos#{arch[:version]}-64"
            arch[:distrib]="centos"
            arch[:arch]="x86_64"
            arch[:base]="RHEL"
        when /^redhat([0-9]+)-32$/
            arch[:version]=$1
            arch[:label]="redhat#{arch[:version]}-32"
            arch[:distrib]="redhat"
            arch[:arch]="i386"
            arch[:base]="RHEL"
        when /^redhat([0-9]+)-64$/
            arch[:version]=$1
            arch[:label]="redhat#{arch[:version]}-64"
            arch[:distrib]="redhat"
            arch[:arch]="x86_64"
            arch[:base]="RHEL"
        when /^suse([0-9\.]+)-64$/
            arch[:version]=$1
            arch[:label]="suse#{arch[:version]}-64"
            arch[:distrib]="suse"
            arch[:arch]="x86_64"
            arch[:base]="SUSE"
        when /^mingw([0-9]+\.[0-9]+)-32$/
            arch[:label]="mingw#{$1}-32"
            arch[:distrib]="mingw"
            arch[:version]=$1
            arch[:arch]="i386"
            arch[:base]="WINNT"
        when '%'
            arch[:label]="%"
            arch[:distrib]="unknown"
            arch[:version]="unknown"
            arch[:arch]="unknown"
            arch[:base]="unknown"
        else
            arch[:label]="unknown"
            arch[:distrib]="unknown"
            arch[:version]="unknown"
            arch[:arch]="unknown"
            arch[:base]="unknown"
        end
        return arch
    end
    module_function :getArch
end
