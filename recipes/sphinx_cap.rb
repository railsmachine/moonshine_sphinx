namespace :sphinx do
  task :start do
    sudo "god start #{application}-sphinx || true"
  end

  task :stop do
    sudo "god stop #{application}-sphinx || true"
  end

  task :index do
    run "rake -f #{current_path}/Rakefile ts:in RAILS_ENV=#{fetch(:rails_env, 'production')}"
  end

  task :index_only do
    run "rake -f #{current_path}/Rakefile ts:in INDEX_ONLY=true RAILS_ENV=#{fetch(:rails_env, 'production')}"
  end

  task :configure do
    run "rake -f #{current_path}/Rakefile ts:config RAILS_ENV=#{fetch(:rails_env, 'production')}"
  end

  task :symlink_db do
    run "mkdir -p #{shared_path}/sphinx"
    run "ln -nfs #{shared_path}/sphinx #{release_path}/db/sphinx"
  end

  desc "Reconfigures sphinx, and then restarts"
  task :restart do
    sphinx.configure
    sudo "god restart #{application}-sphinx || true"
  end

end

after :deploy do
  sphinx.symlink_db
  sphinx.restart
end