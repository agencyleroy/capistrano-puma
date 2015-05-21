Capistrano::Configuration.instance.load do
  namespace :puma do
    namespace :workers do
      desc 'Add a worker'
      task :count, roles: fetch(:puma_role) do
        #TODO
        # cleanup
        # add host name/ip
        workers_count = capture("ps ax | grep -c 'puma: cluster worker [0-9]: `cat  #{fetch(:puma_pid)}`'").to_i
        logger.info  "Workers count : #{workers_count}"
      end

      # TODO
      # Add/remove workers to specific host/s
      # Define  # of workers to add/remove
      # Refactor
      desc 'Worker++'
      task :more, roles: fetch(:puma_role) do
          run("kill -TTIN `cat  #{fetch(:puma_pid)}`")
      end

      desc 'Worker--'
      task :less, roles: fetch(:puma_role) do
        run("kill -TTOU `cat  #{fetch(:puma_pid)}`")
      end


    end
  end
end