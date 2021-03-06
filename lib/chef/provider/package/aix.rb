#
# Author:: Deepali Jagtap
# Copyright:: Copyright (c) 2013 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
require 'chef/provider/package'
require 'chef/mixin/command'
require 'chef/resource/package'
require 'chef/mixin/get_source_from_package'

class Chef
  class Provider
    class Package
      class Aix < Chef::Provider::Package

        include Chef::Mixin::GetSourceFromPackage

        def define_resource_requirements
          super
          requirements.assert(:install) do |a|
            a.assertion { @new_resource.source }
            a.failure_message Chef::Exceptions::Package, "Source for package #{@new_resource.name} required for action install"
          end
          requirements.assert(:all_actions) do |a|
            a.assertion { !@new_resource.source || @package_source_found }
            a.failure_message Chef::Exceptions::Package, "Package #{@new_resource.name} not found: #{@new_resource.source}"
            a.whyrun "would assume #{@new_resource.source} would be have previously been made available"
          end
        end

        def load_current_resource
          @current_resource = Chef::Resource::Package.new(@new_resource.name)
          @current_resource.package_name(@new_resource.package_name)
          @new_resource.version(nil)

          if @new_resource.source
            @package_source_found = ::File.exists?(@new_resource.source)
            if @package_source_found
              Chef::Log.debug("#{@new_resource} checking pkg status")
              status = popen4("installp -L -d #{@new_resource.source}") do |pid, stdin, stdout, stderr|
                package_found = false
                stdout.each do |line|
                  case line
                  when /#{@new_resource.package_name}:/
                    package_found = true
                    fields = line.split(":")
                    @new_resource.version(fields[2])
                  end
                end
              end
            end
          end

          Chef::Log.debug("#{@new_resource} checking install state")
          status = popen4("lslpp -lcq #{@current_resource.package_name}") do |pid, stdin, stdout, stderr|
            stdout.each do |line|
              case line
              when /#{@current_resource.package_name}/
                fields = line.split(":")
                Chef::Log.debug("#{@new_resource} version #{fields[2]} is already installed")
                @current_resource.version(fields[2])
              end
            end
          end

          unless status.exitstatus == 0 || status.exitstatus == 1
            raise Chef::Exceptions::Package, "lslpp failed - #{status.inspect}!"
          end

          @current_resource
        end

        def candidate_version
          return @candidate_version if @candidate_version
          status = popen4("installp -L -d #{@new_resource.source}") do |pid, stdin, stdout, stderr|
            stdout.each_line do |line|
              case line
              when /\w:{Regexp.escape(@new_resource.package_name)}:(.*)/
                fields = line.split(":")
                @candidate_version = fields[2]
                @new_resource.version(fields[2])
                Chef::Log.debug("#{@new_resource} setting install candidate version to #{@candidate_version}")
              end
            end
          end
          unless status.exitstatus == 0
            raise Chef::Exceptions::Package, "installp -L -d #{@new_resource.source} - #{status.inspect}!"
          end
          @candidate_version
        end

        #
        # The install/update action needs to be tested with various kinds of packages
        # on AIX viz. packages with or without licensing file dependencies, packages
        # with dependencies on other packages which will help to test additional
        # options of installp.
        # So far, the code has been tested only with standalone packages.
        #
        def install_package(name, version)
          Chef::Log.debug("#{@new_resource} package install options: #{@new_resource.options}")
          if @new_resource.options.nil?
            run_command_with_systems_locale(
                    :command => "installp -aYF -d #{@new_resource.source} #{@new_resource.package_name}"
                  )
            Chef::Log.debug("#{@new_resource} installed version #{@new_resource.version} from: #{@new_resource.source}")
          else
            run_command_with_systems_locale(
              :command => "installp -aYF #{expand_options(@new_resource.options)} -d #{@new_resource.source} #{@new_resource.package_name}"
            )
            Chef::Log.debug("#{@new_resource} installed version #{@new_resource.version} from: #{@new_resource.source}")
          end
        end

        alias_method :upgrade_package, :install_package

        def remove_package(name, version)
          if @new_resource.options.nil?
            run_command_with_systems_locale(
                    :command => "installp -u #{name}"
                  )
            Chef::Log.debug("#{@new_resource} removed version #{@new_resource.version}")
          else
            run_command_with_systems_locale(
              :command => "installp -u #{expand_options(@new_resource.options)} #{name}"
            )
            Chef::Log.debug("#{@new_resource} removed version #{@new_resource.version}")
          end
        end

      end
    end
  end
end