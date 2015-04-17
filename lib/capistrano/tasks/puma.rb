
Capistrano::Configuration.instance.load do
  _cset(:puma_default_hooks, true)
  _cset(:puma_role, :app)
  _cset(:puma_env, -> { fetch(:rails_env) })
  # Configure "min" to be the minimum number of threads to use to answer
  # requests and "max" the maximum.
  _cset(:puma_threads, [0, 16])
  _cset(:puma_workers, 0)
  _cset(:puma_worker_timeout, nil)
  _cset(:puma_rackup, -> { File.join(current_path, 'config.ru') })
  _cset(:puma_state, -> { File.join(shared_path, 'tmp', 'pids', 'puma.state') })
  _cset(:puma_pid, -> { File.join(shared_path, 'tmp', 'pids', 'puma.pid') })
  _cset(:puma_bind, -> { File.join("unix://#{shared_path}", 'tmp', 'sockets', 'puma.sock') })
  _cset(:puma_conf, -> { File.join(shared_path, 'puma.rb') })
  _cset(:puma_access_log, -> { File.join(shared_path, 'log', 'puma_access.log') })
  _cset(:puma_error_log, -> { File.join(shared_path, 'log', 'puma_error.log') })
  _cset(:puma_init_active_record, false)
  _cset(:puma_preload_app, true)

  # Rbenv and RVM integration
  # _cset(:rbenv_map_bins, fetch(:rbenv_map_bins).to_a.concat(%w{ puma pumactl }))

  # Nginx and puma configuration
  _cset(:nginx_config_name, -> { "#{fetch(:application)}_#{fetch(:stage)}" })
  _cset(:nginx_sites_available_path, -> { '/etc/nginx/sites-available' })
  _cset(:nginx_sites_enabled_path, -> { '/etc/nginx/sites-enabled' })
  _cset(:nginx_server_name, -> { "localhost #{fetch(:application)}.local" })
  _cset(:nginx_flags, -> { 'fail_timeout=0' })
  _cset(:nginx_http_flags, -> { fetch(:nginx_flags) })
  _cset(:nginx_socket_flags, -> { fetch(:nginx_flags) })

  namespace :deploy do
    task :check_puma_hooks do
      if fetch(:puma_default_hooks)
        after 'deploy:check', 'puma:check'
        after 'deploy:finished', 'puma:smart_restart'
      end
    end
    before 'deploy:starting', 'deploy:check_puma_hooks'

    # Puma commands
    %w[start stop upgrade restart].each do |command|
      desc "#{command} puma server"
      task command, roles: :app, except: {no_release: true} do
        after "deploy:#{command}", "puma:#{command}"
      end
    end

    task :symlink_puma_pids, roles: :app do
      run "ln -nfs #{release_path}/tmp/pids #{shared_path}/tmp/pids"
      run "ln -nfs #{release_path}/tmp/sockets #{shared_path}/tmp/sockets"
    end
    after "deploy:finalize_update", "deploy:symlink_puma_pids"
  end

  namespace :puma do
    desc "Setup Nginx config"
    task :nginx_config, roles: fetch(:puma_nginx, :web)  do
      template_puma("nginx_conf", "/tmp/nginx_#{fetch(:nginx_config_name)}")
      run "#{sudo} mv /tmp/nginx_#{fetch(:nginx_config_name)} #{fetch(:nginx_sites_available_path)}/#{fetch(:nginx_config_name)}"
      run "#{sudo} ln -fs #{fetch(:nginx_sites_available_path)}/#{fetch(:nginx_config_name)} #{fetch(:nginx_sites_enabled_path)}/#{fetch(:nginx_config_name)}"
    end

    desc 'Setup Puma config file'
    task :config, roles: fetch(:puma_role) do
      template_puma 'puma', puma_conf
    end

    desc 'Start puma'
    task :start, roles: fetch(:puma_role) do
      if run "test -f #{puma_conf}"
        info "using conf file #{puma_conf}"
      else
        puma.config
      end
      run "cd #{current_path} && RAILS_ENV=#{fetch(:puma_env)} bundle exec puma -C #{fetch(:puma_conf)} --daemon"
    end

    %w[halt stop status].each do |command|
      desc "#{command} puma"
      task command, roles: fetch(:puma_role) do
        begin
          running = true
          run "test -f #{fetch(:puma_pid)}"
        rescue
          #pid file not found, so puma is probably not running or it using another pidfile
          warn '  * Puma not running'
          running = false
        end
        if running == true && run("kill -0 $( cat #{fetch(:puma_pid)} )")
          run "cd #{current_path} && RAILS_ENV=#{fetch(:puma_env)} bundle exec pumactl -S #{fetch(:puma_state)} #{command}"
          running = false
        elsif running == true
          # delete invalid pid file , process is not running.
          run "rm #{fetch(:puma_pid)} "
        end
      end
    end

    %w[phased-restart restart].map do |command|
      desc "#{command} puma"
      task command, roles: fetch(:puma_role) do
        if (run("test -f #{fetch(:puma_pid)}") rescue false) && (run("test kill -0 $( cat #{fetch(:puma_pid)} )") rescue false)
          # NOTE pid exist but state file is nonsense, so ignore that case
          run "cd #{current_path} && RAILS_ENV=#{fetch(:puma_env)} bundle exec pumactl -S #{fetch(:puma_state)} #{command}"
        else
          # Puma is not running or state file is not present : Run it
          puma.start
        end
      end
    end

    task :check do
      #Create puma.rb for new deployments
      unless run "test -f #{fetch(:puma_conf)}"
        logger.important 'puma.rb NOT FOUND!'
        #TODO DRY
        template_puma 'puma', fetch(:puma_conf)
        logger.important 'puma.rb generated'
      end
    end


    task :smart_restart do
      if !puma_preload_app? && puma_workers.to_i > 1
        puma.phased-restart
      else
        puma.restart
      end
    end



    def puma_workers
      fetch(:puma_workers, 0)
    end

    def puma_preload_app?
      fetch(:puma_preload_app)
    end

    def puma_bind
      Array(fetch(:puma_bind)).collect do |bind|
        "bind '#{bind}'"
      end.join("\n")
    end

    def template_puma(from, to)
      [
          "lib/capistrano/templates/#{from}-#{fetch(:stage)}.rb",
          "lib/capistrano/templates/#{from}.rb.erb",
          "lib/capistrano/templates/#{from}.rb",
          "lib/capistrano/templates/#{from}.erb",
          "config/receipes/templates/#{from}.rb.erb",
          "config/receipes/templates/#{from}.rb",
          "config/receipes/templates/#{from}.erb",
          File.expand_path("../../templates/#{from}.rb.erb", __FILE__),
          File.expand_path("../../templates/#{from}.erb", __FILE__)
      ].each do |path|
        if File.file?(path)
          erb = File.read(path)
          #upload! StringIO.new(ERB.new(erb).result(binding)), to
          data = StringIO.new(ERB.new(erb).result(binding))
          transfer :up, data, to#, via: :scp
          break
        end
      end
    end

  end
end