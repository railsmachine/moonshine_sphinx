require 'pathname'

module Sphinx

  def self.included(manifest)
    manifest.class_eval do
      extend ClassMethods

      configure :sphinx => { :version => '0.9.8.1' }
      configure :rails_logrotate => {}

      # We need god in our lives to start/stop/monitor searchd
      recipe :god
    end
  end

  module ClassMethods
    def sphinx_yml
      @sphinx_yml ||= Pathname.new(configuration[:deploy_to]) + 'shared/config/sphinx.yml'
      #rails_root.join('config', 'sphinx.yml')
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
    configure :sphinx => YAML::load(template(sphinx_template_dir + 'sphinx.yml', binding))

    [:searchd_files, :searchd_file_path].each do |config|
      dir = sphinx_configuration[config]
      raise "Expected #{sphinx_yml} to set '#{config}' for '#{rails_env}', but it did not. A decent value to set it to is: #{configuration[:deploy_to]}/shared/sphinx/#{rails_env}" unless dir
      file dir,
        :ensure => :directory,
        :recurse => true,
        :owner => configuration[:user],
        :group => configuration[:group] || configuration[:user],
        :mode => '775'
    end

    file rails_root + 'db/sphinx',
      :ensure => sphinx_configuration[:searchd_files] ,
      :force => true

    file sphinx_yml.to_s,
      :content => template(sphinx_template_dir.join('sphinx.yml')),
      :ensure => :file,
      :owner => configuration[:user],
      :group => configuration[:group] || configuration[:user],
      :mode => '664'

    file rails_root + 'config/sphinx.yml',
      :ensure => sphinx_yml.to_s,
      :require => file(sphinx_yml.to_s)

    rake "thinking_sphinx:configure",
      :refreshonly => true,
      :subscribe => file(sphinx_yml),
      :require => exec('sphinx')

    file sphinx_configuration[:config_file],
      :ensure => :file,
      :owner => configuration[:user],
      :group => configuration[:group] || configuration[:user],
      :mode => '664'

    rake "thinking_sphinx:index",
      :require => [
        file(sphinx_configuration[:searchd_files]),
        exec('rake thinking_sphinx:configure'),
        exec('rake db:migrate'),
        exec('sphinx')
      ],
      :subscribe => file(sphinx_configuration[:config_file])

    exec "god restart #{configuration[:application]}-sphinx",
      :require => exec("rake thinking_sphinx:index")

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

     # Set default here instead of in included so that :minute doesn't get deep_merged with user settings
     configuration[:sphinx][:index_cron] ||= { :minute => 9 }
     current_rails_root = "#{configuration[:deploy_to]}/current"
     thinking_sphinx_index = "(date && cd #{current_rails_root} && RAILS_ENV=#{rails_env} rake thinking_sphinx:index) >> #{current_rails_root}/log/cron-thinking_sphinx-index.log 2>&1"
     cron_options = {
       :command => thinking_sphinx_index,
       :user => configuration[:user]
     }.merge(configuration[:sphinx][:index_cron])

     cron "thinking_sphinx:index", cron_options
  end

end
