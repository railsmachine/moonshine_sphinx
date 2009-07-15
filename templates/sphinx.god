# Replace YOURAPP with the name of your application
# Edit the location of the sphinx.conf file if necessary
God.watch do |w|
  w.group = "YOURAPP-sphinx"
  w.name  = w.group + "-1"

  w.interval = 30.seconds

  w.uid = 'rails'
  w.gid = 'rails'

  w.start         = "searchd --config /srv/YOURAPP/current/config/production.sphinx.conf"
  w.start_grace   = 10.seconds
  w.stop          = "searchd --config /srv/YOURAPP/current/config/production.sphinx.conf --stop"
  w.stop_grace    = 10.seconds
  w.restart       = w.stop + " && " + w.start
  w.restart_grace = 15.seconds

  w.pid_file = "/srv/YOURAPP/current/tmp/pids/sphinx.pid"

  w.behavior(:clean_pid_file)

  w.start_if do |start|
    start.condition(:process_running) do |c|
      c.interval  = 5.seconds
      c.running   = false
    end
  end

  w.restart_if do |restart|
    restart.condition(:memory_usage) do |c|
      c.above = 100.megabytes
      c.times = [3, 5] # 3 out of 5 intervals
    end
  end

  w.lifecycle do |on|
    on.condition(:flapping) do |c|
      c.to_state      = [:start, :restart]
      c.times         = 5
      c.within        = 5.minutes
      c.transition    = :unmonitored
      c.retry_in      = 10.minutes
      c.retry_times   = 5
      c.retry_within  = 2.hours
    end
  end
end