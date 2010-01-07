module Sphinx

  # Define options for this plugin via the <tt>configure</tt> method
  # in your application manifest:
  #
  #   configure(:sphinx => {:foo => true})
  #
  # Then include the plugin and call the recipe(s) you need:
  #
  #  plugin :sphinx
  #  recipe :sphinx
  def sphinx(hash = {})
    options = {
      :version => '0.9.8.1'
    }.merge(hash)
    
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

    configure(:rails_logrotate => {})
    postrotate = configuration[:rails_logrotate][:postrotate] || "touch #{configuration[:deploy_to]}/current/tmp/restart.txt"
    configure(:rails_logrotate => {
      :postrotate => "#{postrotate}\n    pkill -USR1 searchd"
     })
  end
  
end
