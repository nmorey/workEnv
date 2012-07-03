# -*- coding: utf-8 -*-

require 'cli_class_tool'

WORK_ENV_LIB_DIR = __FILE__.chomp(File.extname(__FILE__))

require_relative 'WorkEnvs/Common'
require_relative 'WorkEnvs/Core'
require_relative 'WorkEnvs/accessors'

ENV_LIST=Dir.entries(WORK_ENV_LIB_DIR + "/Envs/").sort().map(){|entry|
    next if (!File.file?(WORK_ENV_LIB_DIR + "/Envs/" + entry) || entry !~ /\.rb$/ );
    entry.sub(/.rb$/, "")
}.compact()

# Load base WorkEnv first
require_relative "WorkEnvs/Envs/Basic"

# Add forward declaration for all classes
ENV_LIST.each(){|e|
    next if e == "Basic"
    c = Class.new(WorkEnvs::BasicEnv)
    WorkEnvs.const_set(e + "Env", c)
}

# Now truly load them
ENV_LIST.each(){|e|
    next if e == "Basic"

    require_relative "WorkEnvs/Envs/#{e}"
    # Make sure the class in the rb file has the proper name
    #
    # To handle parents we were force to generate pre declaration of classes based on the file names
    # So now we want to make sure each file declares the class linked to his name
    expectedEnvClass = WorkEnvs.const_get(e + "Env")
    envType = WorkEnvs::getEnvType(expectedEnvClass)
    if envType  == :dev || envType == nil then
        raise("File #{e} did not set an ENV_TYPE for class #{e}Env.\n"+
              "Make sure the class insided has the name #{e}Env or rename the file appropriately.")
    end
}

if File.exist?(WorkEnvs::WORK_ENV_GLOBAL_DIR + "/extras/CustomEnvs.rb") then
    $LOAD_PATH.push(WorkEnvs::WORK_ENV_GLOBAL_DIR + "/extras")
    require 'CustomEnvs'
    $LOAD_PATH.pop()
end

module WorkEnvs
    WORK_ENV_DEFAULT_TYPE = "dev"
end

#Now all non objet functions
require_relative 'WorkEnvs/global'

module WorkEnvs
  class WorkEnvsError < StandardError; end
end

require_relative 'WorkEnvs/Action'

module WorkEnvs
  ACTION_CLASS = [ WorkEnvAction ]
  extend CLIClassTool::Utils

  def self.actionToString(sym)
    return sym.to_s().gsub('_', '-')
  end

  def self.stringToAction(str)
    action = str.gsub('-', '_').to_sym()
    raise("Invalid action '#{str}'") if self.getActionAttr("ACTION_LIST").index(action) == nil
    return action
  end
end
