# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'open3'

class TestWorkEnv < Minitest::Test
  def setup
    # Preserve original environment variables
    @orig_work_envs = ENV['WORK_ENVS']
    @orig_xdg_config = ENV['XDG_CONFIG_HOME']

    # Create temporary directories for sandboxing
    @test_dir = Dir.mktmpdir('wenv_test_')
    @work_envs_dir = File.join(@test_dir, 'work_envs')
    @xdg_config_dir = File.join(@test_dir, 'xdg_config')
    FileUtils.mkdir_p(@work_envs_dir)
    FileUtils.mkdir_p(@xdg_config_dir)

    # Set sandboxed environment variables
    ENV['WORK_ENVS'] = @work_envs_dir
    ENV['XDG_CONFIG_HOME'] = @xdg_config_dir

    # Path to wenv executable
    @wenv_bin = File.expand_path('../bin/wenv', __dir__)
  end

  def teardown
    # Restore original environment variables
    ENV['WORK_ENVS'] = @orig_work_envs
    ENV['XDG_CONFIG_HOME'] = @orig_xdg_config

    # Clean up temporary directories
    FileUtils.remove_entry(@test_dir) if File.exist?(@test_dir)
  end

  # Helper to execute wenv in our sandboxed environment
  def run_wenv(*args)
    cmd = ['bundle', 'exec', @wenv_bin] + args
    stdout, stderr, status = Open3.capture3(*cmd)
    { stdout: stdout, stderr: stderr, status: status }
  end

  def test_list_empty_environments
    res = run_wenv('list')
    assert_equal 0, res[:status].exitstatus, "Expected success: #{res[:stderr]}"
    assert_match(/No environments/, res[:stdout])
  end

  def test_create_and_list_environment
    res = run_wenv('create', '-n', 'test_dev_env', '-t', 'dev')
    assert_equal 0, res[:status].exitstatus, "Expected success: #{res[:stderr]}"
    assert_match(/Environment 'test_dev_env' successfully created/, res[:stderr].to_s + res[:stdout].to_s)

    # List environments to ensure it shows up
    res_list = run_wenv('list')
    assert_equal 0, res_list[:status].exitstatus
    assert_match(/test_dev_env/, res_list[:stdout])
    assert_match(/dev/, res_list[:stdout])
  end

  def test_create_invalid_name_fails
    res = run_wenv('create', '-n', 'invalid/name', '-t', 'dev')
    refute_equal 0, res[:status].exitstatus
    assert_match(/Invalid name/, res[:stderr].to_s + res[:stdout].to_s)
  end

  def test_switch_and_run_command
    # Create the environment
    create_res = run_wenv('create', '-n', 'test_dev_env', '-t', 'dev')
    assert_equal 0, create_res[:status].exitstatus

    # Switch and run simple command
    switch_res = run_wenv('switch', '-n', 'test_dev_env', 'echo', 'hello', 'world')
    assert_equal 0, switch_res[:status].exitstatus, "Switch failed: #{switch_res[:stderr]}"
    assert_match(/hello world/, switch_res[:stdout])
  end

  def test_switch_uninitialized_fails
    # Create environment of type any (which is uninitialized by default)
    create_res = run_wenv('create', '-n', 'test_any_env', '-t', 'any')
    assert_equal 0, create_res[:status].exitstatus

    # Switch should fail since it's uninitialized
    switch_res = run_wenv('switch', '-n', 'test_any_env', 'echo', 'hello')
    refute_equal 0, switch_res[:status].exitstatus
    assert_match(/Cannot switch to an uninitialized environment/, switch_res[:stderr])
  end

  def test_custom_bashrc_per_env
    # Create the environment
    create_res = run_wenv('create', '-n', 'my_custom_env', '-t', 'dev')
    assert_equal 0, create_res[:status].exitstatus

    # Create the custom bashrc file for this environment
    bashrc_dir = File.join(@xdg_config_dir, 'workEnv', 'bashrcs')
    FileUtils.mkdir_p(bashrc_dir)
    env_bashrc = File.join(bashrc_dir, 'my_custom_env')
    File.write(env_bashrc, "export MY_CUSTOM_VAR='env_specific_value'\n")

    # Switch and print variable to verify it is sourced
    switch_res = run_wenv('switch', '-n', 'my_custom_env', 'printenv', 'MY_CUSTOM_VAR')
    assert_equal 0, switch_res[:status].exitstatus, "Switch failed: #{switch_res[:stderr]}"
    assert_match(/env_specific_value/, switch_res[:stdout])
  end

  def test_global_bashrc
    # Create the environment
    create_res = run_wenv('create', '-n', 'another_env', '-t', 'dev')
    assert_equal 0, create_res[:status].exitstatus

    # Create global bashrc
    bashrc_dir = File.join(@xdg_config_dir, 'workEnv', 'bashrcs')
    FileUtils.mkdir_p(bashrc_dir)
    global_bashrc = File.join(bashrc_dir, '.bashrc')
    File.write(global_bashrc, "export MY_GLOBAL_VAR='global_value'\n")

    # Switch and print variable to verify it is sourced
    switch_res = run_wenv('switch', '-n', 'another_env', 'printenv', 'MY_GLOBAL_VAR')
    assert_equal 0, switch_res[:status].exitstatus, "Switch failed: #{switch_res[:stderr]}"
    assert_match(/global_value/, switch_res[:stdout])
  end

  def test_rename_environment
    # Create the environment
    create_res = run_wenv('create', '-n', 'old_name', '-t', 'dev')
    assert_equal 0, create_res[:status].exitstatus

    # Rename
    rename_res = run_wenv('rename', '-n', 'old_name', '-N', 'new_name')
    assert_equal 0, rename_res[:status].exitstatus, "Rename failed: #{rename_res[:stderr]}"

    # Verify old name is gone and new name is present
    list_res = run_wenv('list')
    refute_match(/old_name/, list_res[:stdout])
    assert_match(/new_name/, list_res[:stdout])
  end

  def test_remove_environment
    # Create the environment
    create_res = run_wenv('create', '-n', 'to_delete', '-t', 'dev')
    assert_equal 0, create_res[:status].exitstatus

    # Delete with --yes option to bypass confirmation
    rm_res = run_wenv('rm', '-n', 'to_delete', '--yes')
    assert_equal 0, rm_res[:status].exitstatus, "Remove failed: #{rm_res[:stderr]}"

    # Verify to_delete is gone
    list_res = run_wenv('list')
    refute_match(/to_delete/, list_res[:stdout])
  end
end
