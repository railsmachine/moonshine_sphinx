namespace :sphinx do
  task :start, :roles => [:sphinx] do
    sudo "god start #{application}-sphinx || true"
  end

  task :stop, :roles => [:sphinx] do
    sudo "god stop #{application}-sphinx || true"
  end

  task :index, :roles => [:sphinx] do
    run "rake -f #{current_path}/Rakefile ts:in RAILS_ENV=#{fetch(:rails_env, 'production')}"
  end

  task :index_only, :roles => [:sphinx] do
    run "rake -f #{current_path}/Rakefile ts:in INDEX_ONLY=true RAILS_ENV=#{fetch(:rails_env, 'production')}"
  end

  task :configure, :roles => [:sphinx] do
    run "rake -f #{current_path}/Rakefile ts:config RAILS_ENV=#{fetch(:rails_env, 'production')}"
  end

  desc "Reconfigures sphinx, and then restarts"
  task :restart, :roles => [:sphinx] do
    sudo "god restart #{application}-sphinx || true"
  end

  desc "Symlink Sphinx indexes"
  task :symlink_indexes, :roles => [:sphinx] do
    run "ln -nfs #{shared_path}/sphinx/#{rails_env} #{release_path}/db/sphinx"
  end

end

before 'deploy' do
  # do the sphinx things moonshine would normally do
  if ! fetch(:moonshine_apply, true)
    after 'deploy:finalize_update', 'sphinx:symlink_indexes'
    before 'god:restart', 'sphinx:configure'
    before 'god:restart', 'sphinx:stop'
  end
end
