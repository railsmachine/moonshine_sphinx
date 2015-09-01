require 'pathname'

module Sphinx

  def self.included(manifest)
    manifest.class_eval do
      extend ClassMethods

      configure :sphinx => { :version => '0.9.8.1', :extra => {}, :use_god => true, :sphinx_yml => 'thinking_sphinx.yml' }
      configure :rails_logrotate => {}

    end
  end

  module ClassMethods
    def sphinx_yml
      @sphinx_yml ||= Pathname.new(configuration[:deploy_to]) + "shared/config/#{configuration[:sphinx][:sphinx_yml]}"
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
    if configuration[:sphinx][:use_god]
      if respond_to?(:god)
        # We need god in our lives to start/stop/monitor searchd
        recipe :god unless self.class.recipes.any? {|(recipe, options)| recipe == :god }
      else
        raise "Could not find god recipe, aborting. Please install moonshine_god recipe: script/plugin install  git://github.com/railsmachine/moonshine_god.git and redeploy"
      end
    end

    configure :sphinx => YAML::load(template(sphinx_template_dir + 'thinking_sphinx.yml', binding))
    sphinx_config_only

    [:searchd_files, :searchd_file_path].each do |config|
      dir = sphinx_configuration[config]
      raise "Expected #{sphinx_yml} to set '#{config}' for '#{rails_env}', but it did not. A decent value to set it to is: #{configuration[:deploy_to]}/shared/sphinx/#{rails_env}" unless dir
      file dir,
        :ensure => :directory,
        :owner => configuration[:user],
        :group => configuration[:group] || configuration[:user]
    end

    file rails_root + 'db/sphinx',
      :ensure => sphinx_configuration[:searchd_files] ,
      :force => true

    file configuration[:deploy_to] + '/shared/sphinx',
      :ensure => :directory,
      :owner => configuration[:user],
      :group => configuration[:group] || configuration[:user],
      :mode => '664',
      :alias => 'searchd shared files'

    rake "ts:configure",
      :refreshonly => true,
      :subscribe => file(sphinx_yml),
      :require => [
        exec('sphinx'),
        exec('rails_gems'),
        file('searchd shared files')
      ]

    file sphinx_configuration[:configuration_file],
      :ensure => :file,
      :owner => configuration[:user],
      :group => configuration[:group] || configuration[:user],
      :mode => '664'

    unless configuration[:sphinx][:index_on_deploy] == false
      rake "ts:index",
        :require => [
          file(sphinx_configuration[:searchd_files]),
          exec('rake ts:configure'),
          exec('rake db:migrate'),
          exec('sphinx'),
          exec('rails_gems')
        ],
        :subscribe => file(sphinx_configuration[:configuration_file])
    end

    package 'wget', :ensure => :installed

    version = configuration[:sphinx][:version]
    file_version = "#{version}"
    if file_version =~ /beta/
      version = file_version.split("-").first
    else
      file_version = "#{version}-release" if version =~ /^2/
    end

    libstemmer = configuration[:sphinx][:libstemmer] || false

    sphinx_version = Gem::Version.new(version)
    ver2 = Gem::Version.new('2.0')
    exec 'download sphinx',
      :command => "wget http://sphinxsearch.com/files#{'/archive' if sphinx_version < ver2 }/sphinx-#{file_version}.tar.gz",
      :cwd => '/tmp',
      :require => package('wget'),
      :unless => "test -f /usr/local/bin/searchd && test #{version} = `searchd --help | head -n1 | awk '{print $2}' | awk -F- '{print $1}'`"

    exec 'extract sphinx',
      :command => "tar xzf sphinx-#{file_version}.tar.gz",
      :cwd => '/tmp',
      :require => exec('download sphinx'),
      :unless => "test -f /usr/local/bin/searchd && test #{version} = `searchd --help | head -n1 | awk '{print $2}' | awk -F- '{print $1}'`"

    if libstemmer
      exec 'download and extract libstemmer',
        :command => [
          "wget http://snowball.tartarus.org/dist/libstemmer_c.tgz",
          "tar xzf libstemmer_c.tgz",
          "cp -R libstemmer_c/* sphinx-#{file_version}/libstemmer_c/"
        ].join(' && '),
        :cwd => '/tmp',
        :require => exec('extract sphinx'),
        :unless => "test -f /usr/local/bin/searchd && test #{version} = `searchd --help | head -n1 | awk '{print $2}' | awk -F- '{print $1}'`"
    else
      exec 'download and extract libstemmer',
        :command => 'true',
        :require => exec('extract sphinx'),
        :unless => "test -f /usr/local/bin/searchd && test #{version} = `searchd --help | head -n1 | awk '{print $2}' | awk -F- '{print $1}'`"
    end

    exec 'sphinx',
      :command => [
        "./configure #{ '--with-libstemmer' if libstemmer}",
        'make',
        'make install'
      ].join(' && '),
      :cwd => "/tmp/sphinx-#{file_version}",
      :require => [exec('extract sphinx'), exec('download and extract libstemmer')],
      :unless => "test -f /usr/local/bin/searchd && test #{version} = `searchd --help | head -n1 | awk '{print $2}' | awk -F- '{print $1}'`"

    postrotate = configuration[:rails_logrotate][:postrotate] || "touch #{configuration[:deploy_to]}/current/tmp/restart.txt"
    configure(:rails_logrotate => {
      :postrotate => "#{postrotate}\n    pkill -USR1 searchd"
     })

    if configuration[:sphinx][:use_god]
      file "/etc/god/#{configuration[:application]}-sphinx.god",
        :ensure => :present,
        :require => file('/etc/god/god.conf'),
        :content => template(sphinx_template_dir.join('sphinx.god'))
    end

    unless configuration[:sphinx][:index_cron] == false
      current_rails_root = "#{configuration[:deploy_to]}/current"
      thinking_sphinx_index = "(date && cd #{current_rails_root} && RAILS_ENV=#{rails_env} bundle exec rake ts:index) >> #{current_rails_root}/log/cron-thinking_sphinx-index.log 2>&1"
      cron_options = {
        :command => thinking_sphinx_index,
        :user => configuration[:user]
      }.merge(configuration[:sphinx][:index_cron] || {:minute => 9}) # Set default here instead of in included so that :minute doesn't get deep_merged with user settings

      cron "ts:index", cron_options
    end
  end

  # Just configure thinking_sphinx.yml. Useful on app servers when sphinx is on a shared
  # server
  def sphinx_config_only
    file sphinx_yml.to_s,
      :content => template(sphinx_template_dir.join('thinking_sphinx.yml')),
      :ensure => :file,
      :owner => configuration[:user],
      :group => configuration[:group] || configuration[:user],
      :mode => '664'

    file rails_root + "config/#{configuration[:sphinx][:sphinx_yml]}",
      :ensure => sphinx_yml.to_s,
      :require => file(sphinx_yml.to_s),
      :before => exec('rake tasks')
  end

end
