#
# Cookbook Name:: rabbitmq
# Provider:: user
#
# Copyright 2011-2013, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

use_inline_resources

def user_exists?(name)
  cmd = "rabbitmqctl -q list_users |grep '^#{name}\\s'"
  cmd = Mixlib::ShellOut.new(cmd)
  cmd.environment['HOME'] = ENV.fetch('HOME', '/root')
  cmd.run_command
  Chef::Log.debug "rabbitmq_user_exists?: #{cmd}"
  Chef::Log.debug "rabbitmq_user_exists?: #{cmd.stdout}"
  begin
    cmd.error!
    true
  rescue
    false
  end
end

def user_has_tag?(name, tag) # rubocop:disable all
  cmd = 'rabbitmqctl -q list_users'
  cmd = Mixlib::ShellOut.new(cmd)
  cmd.environment['HOME'] = ENV.fetch('HOME', '/root')
  cmd.run_command
  user_list = cmd.stdout
  tags = user_list.match(/^#{name}\s+\[(.*?)\]/)[1].split
  Chef::Log.debug "rabbitmq_user_has_tag?: #{cmd}"
  Chef::Log.debug "rabbitmq_user_has_tag?: #{cmd.stdout}"
  Chef::Log.debug "rabbitmq_user_has_tag?: #{name} has tags: #{tags}"
  if tag.nil? && tags.empty?
    true
  elsif tags.include?(tag)
    true
  else
    false
  end
rescue RuntimeError
  false
end

# does the user have the rights listed on the vhost?
# empty perm_list means we're checking for any permissions
def user_has_permissions?(name, vhost, perm_list = nil) # rubocop:disable all
  vhost = '/' if vhost.nil? # rubocop:enable all
  cmd = "rabbitmqctl -q list_user_permissions #{name} | grep \"^#{vhost}\\s\""
  cmd = Mixlib::ShellOut.new(cmd)
  cmd.environment['HOME'] = ENV.fetch('HOME', '/root')
  cmd.run_command
  Chef::Log.debug "rabbitmq_user_has_permissions?: #{cmd}"
  Chef::Log.debug "rabbitmq_user_has_permissions?: #{cmd.stdout}"
  Chef::Log.debug "rabbitmq_user_has_permissions?: #{cmd.exitstatus}"
  if perm_list.nil? && cmd.stdout.empty? # looking for empty and found nothing
    Chef::Log.debug 'rabbitmq_user_has_permissions?: no permissions found'
    return false
  end
  if perm_list == cmd.stdout.split.drop(1) # existing match search
    Chef::Log.debug 'rabbitmq_user_has_permissions?: matching permissions already found'
    return true
  end
  Chef::Log.debug 'rabbitmq_user_has_permissions?: permissions found but do not match'
  false
end

action :add do
  Chef::Application.fatal!('rabbitmq_user with action :add requires a non-nil/empty password.') if new_resource.password.nil? || new_resource.password.empty?

  # To escape single quotes in a shell, you have to close the surrounding single quotes, add
  # in an escaped single quote, and then re-open the original single quotes.
  # Since this string is interpolated once by ruby, and then a second time by the shell, we need
  # to escape the escape character ('\') twice.  This is why the following is such a mess
  # of leaning toothpicks:
  new_password = new_resource.password.gsub("'", "'\\\\''")
  cmd = "rabbitmqctl add_user #{new_resource.user} '#{new_password}'"
  execute "rabbitmqctl add_user #{new_resource.user}" do # ~FC009
    sensitive true if Gem::Version.new(Chef::VERSION.to_s) >= Gem::Version.new('11.14.2')
    command cmd
    Chef::Log.info "Adding RabbitMQ user '#{new_resource.user}'."
    not_if { user_exists?(new_resource.user) }
  end
end

action :delete do
  cmd = 'rabbitmqctl delete_user'
  execute "#{cmd} #{new_resource.user}" do
    Chef::Log.debug "rabbitmq_user_delete: #{cmd} #{new_resource.user}"
    Chef::Log.info "Deleting RabbitMQ user '#{new_resource.user}'."
    only_if { user_exists?(new_resource.user) }
  end
end

action :set_permissions do
  Chef::Application.fatal!("rabbitmq_user action :set_permissions fails with non-existant '#{new_resource.user}' user.") unless user_exists?(new_resource.user)

  perm_list = new_resource.permissions.split
  vhosts = new_resource.vhost.is_a?(Array) ? new_resource.vhost : [new_resource.vhost]
  vhosts.each do |vhost|
    next if user_has_permissions?(new_resource.user, vhost, perm_list)
    vhostopt = "-p #{vhost}" unless vhost.nil?
    cmd = "rabbitmqctl set_permissions #{vhostopt} #{new_resource.user} \"#{perm_list.join("\" \"")}\""
    execute cmd do
      Chef::Log.debug "rabbitmq_user_set_permissions: #{cmd}"
      Chef::Log.info "Setting RabbitMQ user permissions for '#{new_resource.user}' on vhost #{vhost}."
    end
  end
end

action :clear_permissions do
  Chef::Application.fatal!("rabbitmq_user action :clear_permissions fails with non-existant '#{new_resource.user}' user.") unless user_exists?(new_resource.user)

  vhosts = new_resource.vhost.is_a?(Array) ? new_resource.vhost : [new_resource.vhost]
  vhosts.each do |vhost|
    next unless user_has_permissions?(new_resource.user, vhost)
    vhostopt = "-p #{vhost}" unless vhost.nil?
    cmd = "rabbitmqctl clear_permissions #{vhostopt} #{new_resource.user}"
    execute cmd do
      Chef::Log.debug "rabbitmq_user_clear_permissions: #{cmd}"
      Chef::Log.info "Clearing RabbitMQ user permissions for '#{new_resource.user}' from vhost #{vhost}."
    end
  end
end

action :set_tags do
  Chef::Application.fatal!("rabbitmq_user action :set_tags fails with non-existant '#{new_resource.user}' user.") unless user_exists?(new_resource.user)

  unless user_has_tag?(new_resource.user, new_resource.tag)
    cmd = "rabbitmqctl set_user_tags #{new_resource.user} #{new_resource.tag}"
    execute cmd do
      Chef::Log.debug "rabbitmq_user_set_tags: #{cmd}"
      Chef::Log.info "Setting RabbitMQ user '#{new_resource.user}' tags '#{new_resource.tag}'"
    end
  end
end

action :clear_tags do
  Chef::Application.fatal!("rabbitmq_user action :clear_tags fails with non-existant '#{new_resource.user}' user.") unless user_exists?(new_resource.user)

  unless user_has_tag?(new_resource.user, '"\[\]"')
    cmd = "rabbitmqctl set_user_tags #{new_resource.user}"
    execute cmd do
      Chef::Log.debug "rabbitmq_user_clear_tags: #{cmd}"
      Chef::Log.info "Clearing RabbitMQ user '#{new_resource.user}' tags."
    end
  end
end

action :change_password do
  if user_exists?(new_resource.user)
    cmd = "rabbitmqctl change_password #{new_resource.user} #{new_resource.password}"
    execute "rabbitmqctl change_password #{new_resource.user}" do # ~FC009
      sensitive true if Gem::Version.new(Chef::VERSION.to_s) >= Gem::Version.new('11.14.2')
      command cmd
      Chef::Log.debug "rabbitmq_user_change_password: #{cmd}"
      Chef::Log.info "Editing RabbitMQ user '#{new_resource.user}'."
    end
  end
end
