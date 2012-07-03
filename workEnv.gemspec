# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'workEnv'

  # Extract version dynamically from git, falling back to 0.1.0 if not in a git repo or no tags exist
  version_str = `git describe --tags 2>/dev/null`.chomp().gsub(/^v/, "").gsub(/-([0-9]+)-g/, '-\1.g')
  s.version     = version_str.empty? ? '0.1.0' : version_str

  # Extract date dynamically from git, falling back to today's date if no commits exist
  date_str = `git show HEAD --format='format:%ci' -s 2>/dev/null | awk '{ print $1}'`.chomp()
  s.date        = date_str.empty? ? Time.now.strftime('%Y-%m-%d') : date_str

  s.summary     = "A CLI tool and framework to create, switch, and manage isolated, modular development environments."
  s.description = "This set of scripts allows to work easily on a single workstation using multiple versions of Work Tools. These scripts will configure your environment for you (PATH, Licenses, etc.), but also allow to fetch and install coherent set of tools."
  s.authors     = ["Nicolas Morey"]
  s.email       = 'nicolas@morey.ovh'
  s.homepage    = 'https://github.com/nmorey/workEnv'
  s.license     = 'GPL-3.0-or-later'
  s.required_ruby_version = '>= 2.7'

  s.files       = [
    "LICENSE",
  ] + Dir['lib/**/*.rb', 'bin/wenv', 'workrc-completion.sh'].keep_if { |file| File.file?(file) }
  s.bindir      = 'bin'
  s.executables = ['wenv']

end
