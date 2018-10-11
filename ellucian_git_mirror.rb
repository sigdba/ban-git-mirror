#!/usr/bin/ruby
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/LineLength

require 'git'
require 'net/ssh'
require 'pp'
require 'yaml'
require 'gitlab'

raise 'usage: ellucian_git_mirror.rb <conf_yml>' unless ARGV.length == 1

# To avoid a group search for each repository, the groups are cached. This cache
# is flushed at the start of cycle of mirroring.
$group_cache = {}

def log
  Logger.new(STDOUT)
end

# Base configuration object - This object represents the settings provided in
# the configuration file.
class Conf
  def initialize(path)
    log.info "Loading configuration: #{path}"
    @conf = YAML.load_file(path)
    @conf['mirror']['ssh_key'] || raise("key not found in #{path}: mirror/ssh_key")
    @conf['mirror']['root'] || raise("key not found in #{path}: mirror/root")
  end

  def origin_host
    @conf['mirror']['git_host'] || 'banner-src.ellucian.com'
  end

  def origin_user
    @conf['mirror']['ssh_user'] || 'git'
  end

  def origin_url_base
    @conf['mirror']['git_url'] || "ssh://#{origin_user}@#{origin_host}"
  end

  def skip_paths
    @conf['mirror']['skip'] || []
  end

  def refresh_delay_secs
    @conf['mirror']['refresh_delay_secs'] || 3600
  end

  def interval_secs
    @conf['mirror']['interval'] || 21_600
  end

  def project_visibility
    @conf['gitlab']['project_visibility'] || 10
  end

  def ssh_key
    @conf['mirror']['ssh_key']
  end

  def mirror_root
    @conf['mirror']['root']
  end

  def gitlab?
    @conf.include? 'gitlab'
  end

  def gitlab_url
    @conf['gitlab']['url']
  end

  def gitlab_token
    @conf['gitlab']['token']
  end

  def gitlab
    Gitlab.client(endpoint: gitlab_url, private_token: gitlab_token)
  end
end

# Repository configuration object - This class provides the settings for a
# repository and is derived from the repository list provided by Ellucian
# combined with the settings from configuration file.
#
# This class does not inherit from the Conf class, but it does use it's
# method_missing() method to defer to the Conf class. You can therefore use
# this class to access both global and repository-specific settings.
class RepoConf
  def initialize(conf, path)
    @conf = conf
    @path = path
  end

  # Delegate to @conf for methods not handled by RepoConf
  def method_missing(method, *args)
    @conf.send(method, *args)
  end

  def repo_name
    File.basename(@path)
  end

  def base_path
    @path
  end

  def group_path
    File.dirname(base_path)
  end

  def parent_path
    "#{@conf.mirror_root}/#{File.dirname(@path)}"
  end

  def bare_name
    "#{repo_name}.git"
  end

  def bare_path
    "#{parent_path}/#{bare_name}"
  end

  def touch_file
    "#{bare_path}/mirror_last_fetched"
  end

  def origin_url
    "#{origin_url_base}/#{@path}"
  end
end

def mirror(conf)
  return Git.bare(conf.bare_path, log: log) if mirror_skip?(conf)

  ret = if File.directory?(conf.bare_path)
          mirror_fetch(conf)
        else
          mirror_clone(conf)
        end
  FileUtils.touch(conf.touch_file)
  ret
end

def mirror_skip?(conf)
  # Don't skip if the directory doesn't exist
  return false unless File.directory?(conf.bare_path)

  # If the directory exists, but touch_file doesn't delete it.
  unless File.exist?(conf.touch_file)
    log.info "#{conf.bare_path} exists but is not complete. Deleting for re-clone."
    FileUtils.rm_r(conf.bare_path)
    return false
  end

  # Skip if the touch file is recent enough
  Time.now - File.mtime(conf.touch_file) < conf.refresh_delay_secs
end

def mirror_fetch(conf)
  log.info "Fetching #{conf.bare_path}"
  ret = Git.bare(conf.bare_path, log: log)
  ret.fetch(conf.origin_url, tags: true, prune: true)
  ret
end

def mirror_clone(conf)
  log.info "Cloning #{conf.origin_url} into #{conf.parent_path}/#{conf.bare_name}"
  Git.clone(conf.origin_url, conf.bare_name, log: log, bare: true, path: conf.parent_path)
end

def gitlab_update(conf, repo)
  log.info "Updating GitLab project: #{conf.repo_name}"
  project = gitlab_project(conf)
  url = project.ssh_url_to_repo
  # url = "git@192.168.33.12:xe/#{conf.bare_name}"
  log.info "Pushing to: #{url}"
  repo.push(url, '--all', tags: true)
end

def gitlab_project(conf)
  group_id = gitlab_group(conf).id

  p = conf.gitlab.project_search(conf.repo_name).select { |q| q.name == conf.repo_name && q.namespace.id == group_id }.first

  if p
    if p.visibility_level != conf.project_visibility
      log.info "Changing visibility of #{p.name} from #{p.visibility_level} to #{conf.project_visibility}"
      conf.gitlab.edit_project(p.id, visibility_level: conf.project_visibility)
    end
    return p
  end

  log.info "Creating new GitLab project: #{conf.repo_name}"
  conf.gitlab.create_project(conf.repo_name,
                             group_id: group_id,
                             namespace_id: group_id,
                             visibility_level: conf.project_visibility)
end

# Returns information about the group of the repository specified in conf. It
# wraps the real method to provide simple caching.
def gitlab_group(conf)
  path = conf.group_path
  return $group_cache[path] if $group_cache.key?(path)

  ret = _gitlab_group(path, conf)
  $group_cache[path] = ret
  ret
end

# Return information about the group of the group on path.
# NB: This method only uses conf to get a handle on the GitLab client. It makes
# no reference to any repository-specifc details in conf.
def _gitlab_group(path, conf)
  if path.include?('/')
    parts = path.reverse.split('/', 2).map(&:reverse)
    parent_id = _gitlab_group(parts[1], conf).id
    group_name = parts.first
  else
    parent_id = nil
    group_name = path
  end

  log.debug "Looking for GitLab group '#{group_name}' with parent_id=#{parent_id}"
  g = conf.gitlab.group_search(group_name).select { |q| q.name == group_name && q.parent_id == parent_id }.first
  return g if g

  log.info "Creating new GitLab group: #{path} (Parent ID: #{parent_id})"
  conf.gitlab.create_group(group_name, group_name, description: "Ellucian Mirror: #{path}",
                                                   parent_id: parent_id)
end

log.info 'Starting Ellucian XE mirror process'
conf = Conf.new(ARGV[0])

loop do
  log.info 'Fetching repository list from Ellucian'
  $group_cache.clear
  repo_list = Net::SSH.start(conf.origin_host,
                             conf.origin_user,
                             keys: [conf.ssh_key],
                             keys_only: true) do |ssh|
    ssh.exec!('info').lines
  end

  repo_list.map(&:split)
           .select { |a| a[0] == 'R' }
           .map(&:last)
           .select { |l| l.start_with?('banner/') }
           .select { |l| !conf.skip_paths.include?(l) }
           .map { |path| RepoConf.new(conf, path) }
           .each do |c|
    begin
      repo = mirror(c)
      gitlab_update(c, repo) if conf.gitlab?
    rescue => e
      log.warn "Error while mirroring #{c.bare_name}:\n#{e.message}\n#{e.backtrace.inspect}\nCarrying On."
    end
  end
  log.info "All done. Sleeping #{conf.interval_secs} seconds..."

  sleep conf.interval_secs
end
