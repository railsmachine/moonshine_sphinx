require 'pathname'

module Sphinx

  def self.included(manifest)
    manifest.class_eval do
      extend ClassMethods

      configure :sphinx => { :version => '0.9.8.1' }
      configure :rails_logrotate => {}

      # We need god in our lives to start/stop/monitor searchd
      recipe :god

      if sphinx_yml.exist?
        configure :sphinx => YAML::load(template(sphinx_yml, binding))
      end

    end
  end

  module ClassMethods
    def sphinx_yml
      rails_root.join('config', 'sphinx.yml')
    end

    def sphinx_configuration
      configuration[:sphinx][rails_env.to_sym]
    end

    def sphinx_template_dir
      @sphinx_template_dir ||= Pathname.new(__FILE__).dirname.dirname.join('templates')
    end
  end

  # Define options for this plugin via the <tt>configure</tt> method
  # in your application manifest:
  #
  #   configure(:sphinx => {:foo => true})
  #
  # Then include the plugin and call the recipe(s) you need:
  #
  #  plugin :sphinx
  #  recipe :sphinx
  def sphinx(options = {})
    if ! sphinx_yml.exist?
      raise <<END
Expected #{sphinx_yml} to exist and be a YAML file containing a stanza for #{rails_env} like:

searchd_file_path: #{configuration[:deploy_to]}/shared/sphinx/#{rails_env}
searchd_files: #{configuration[:deploy_to]}/shared/sphinx/#{rails_env}
config_file: #{configuration[:deploy_to]}/shared/shared/sphinx.conf
bin_path: /usr/local/bin
END
    end

    if sphinx_configuration
      if sphinx_configuration[:bin_path] != '/usr/local/bin'
        raise "Expected #{sphinx_yml} to set 'bin_path' for '#{rails_env}' to  '/usr/local/bin', but was #{sphinx_configuration[:bin_path].inspect}" 
      end

      unless sphinx_configuration[:config_file]
        raise "Expected #{sphinx_yml} to set 'config_file' for '#{rails_env}', but it did not. A decent value to set it to is: #{configuration[:deploy_to]}/shared/config/#{rails_env}.sphinx.conf"
      end

      [:searchd_files, :searchd_file_path].each do |config|
        dir = sphinx_configuration[config]
        raise "Expected #{sphinx_yml} to set '#{config}' for '#{rails_env}', but it did not. A decent value to set it to is: #{configuration[:deploy_to]}/shared/sphinx/#{rails_env}" unless dir
        file dir,
          :ensure => :directory,
          :owner => configuration[:user],
          :group => configuration[:group] || configuration[:user],
          :mode => '775'
      end


    else
      raise "#{sphinx_yml} existed, but didn't define configuration for #{rails_env}"
    end

    package 'wget', :ensure => :installed

    exec 'sphinx',
      :command => [
        "wget http://sphinxsearch.com/downloads/sphinx-#{options[:version]}.tar.gz",
        "tar xzf sphinx-#{options[:version]}.tar.gz",
        "cd sphinx-#{options[:version]}",
        './configure',
        'make',
        'make install'
      ].join(' && '),
      :cwd => '/tmp',
      :require => package('wget'),
      :unless => "test -f /usr/local/bin/searchd && test #{options[:version]} = `searchd --help | grep Sphinx | awk '{print $2}' | awk -F- '{print $1}'`"

    postrotate = configuration[:rails_logrotate][:postrotate] || "touch #{configuration[:deploy_to]}/current/tmp/restart.txt"
    configure(:rails_logrotate => {
      :postrotate => "#{postrotate}\n    pkill -USR1 searchd"
     })

     file "/etc/god/#{configuration[:application]}-sphinx.god",
       :require => file('/etc/god/god.conf'),
       :content => template(sphinx_template_dir.join('sphinx.god')),
       :notify => exec('restart_god')

     if configuration[:sphinx][:index_cron]
       current_rails_root = "#{configuration[:deploy_to]}/current"
       thinking_sphinx_index = "(date && cd #{current_rails_root} && RAILS_ENV=#{rails_env} rake thinking_sphinx:index) >> #{current_rails_root}/log/cron-thinking_sphinx-index.log 2>&1"
       cron_options = {
         :command => thinking_sphinx_index,
         :user => configuration[:user]
       }.merge(configuration[:sphinx][:index_cron])

       cron "thinking_sphinx:index", cron_options
     end
  end

end
