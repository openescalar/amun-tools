#!/opt/ruby/bin/ruby
require 'zmq'
require 'syslog'
require 'yaml'

class Coordinator

  def initialize
    @loop = true
  end

  def log(message)
    Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.warning self.class.to_s + " - " + message }
  end

  def start
    begin
      @loop = true
      mainListen
      log("STARTING")
    rescue
      log("Error while trying to reserver ports")
    end
  end

  def stop
    @loop = false
    @t.join
    log("SHUTTING DOWN")
  end 

  def mainListen
    @t = Thread.new do 
      begin
        contxt = ZMQ::Context.new
        fromEveryone = contxt.socket(ZMQ::UPSTREAM)
        toWorker     = contxt.socket(ZMQ::DOWNSTREAM)
        fromEveryone.bind("tcp://*:12345")
        toWorker.bind("tcp://*:12346")   
      rescue
        log("Error reserving ports")
      end
      while @loop
	begin
	  msg = fromEveryone.recv(ZMQ::NOBLOCK)
          if msg
	   log("receive msg " + msg)
	    m = YAML.load(msg)
	    if m[:action] == "POWEROFF" 
              @loop = false
            else
              toWorker.send(msg)
            end
            #send message to workers
          end
        rescue => e
	  log("Error while sending message to Workers #{msg} - " + e.inspect)
        end
        sleep 1
      end
      begin
        fromEveryone.close
        toWorker.close
      rescue => e
        log("Error while releasing ports - " + e.inspect)
      end
    end
  end

end
