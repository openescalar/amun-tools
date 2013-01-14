#!/opt/ruby/bin/ruby
#require '/opt/openescalar/amun-tools/lib/amun/config/environment.rb'
require 'zmq'
require 'yaml'
require 'syslog'
require 'active_record'
gem 'multi_json', '1.0.3'
#Loading libs
%w{ oecompiler oedist oedsl oeencrypt awsapi osapi eucaapi hpos rsapi rsosapi }.each { |x| require "/opt/openescalar/amun-tools/lib/amun/lib/#{x}.rb" }
#Dir["/opt/openescalar/amun-tools/lib/amun/lib/*.rb"].each {|file| require file }
#Loading models
Dir["/opt/openescalar/amun-tools/lib/amun/app/models/*.rb"].each {|file| require file }

#### Message v1 format action|object|caracteristicas
#### Message v2 yaml including
# action: create|delete|update - required
# object: server|image|firewall|volume|etc - required
# serial: imageserial, serverserial, firewallserial - optional
# characteristicas: - optional

class Worker

  attr_accessor :dg   
  
  def initialize
    @loop = true
    ActiveRecord::Base.establish_connection(YAML.load_file('/opt/openescalar/amun-tools/conf/worker.conf')["database"])
  end

  def log(message)
    Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.warning self.class.to_s + " -  " + message }
  end
  
  def db(&block)
    ActiveRecord::Base.connection_pool.with_connection &block
  end

  def start
    begin
      @loop = true
      mainListen
      if @dg 
        log("STARTING IN DEBUG") 
      else
        log("STARTING")
      end
    rescue 
      log("Error Connection to coordinator")
    end    
  end

  def stop
    @loop = false
    @t.join
    log("SHUTINGDOWN")
  end

  def mainListen
    @t = Thread.new do 
     begin
       contxt = ZMQ::Context.new
       worker = contxt.socket(ZMQ::UPSTREAM)
       worker.connect("tcp://*:12346")
     rescue
	log("Error Connecting to coordinator")
     end
     while @loop
      begin 
	msg = worker.recv(ZMQ::NOBLOCK)
        if msg
          log("received msg " + msg )
	  m = YAML.load(msg)
          if m["action"] == "POWEROFF"
            @loop = false
          end
          log(m[:action].to_s + " " + m[:object].to_s) if @dg
	  case m[:action]
	     when "create"
	        create(m)
             when "delete"
                delete(m)
             when "update"
                update(m)
	     when "status"
	        status(m)
             when "build"
                sendtask(m) 
             when "get"
                get(m)
	     when "installclient"
	        installclient(m)
          end
        end
        sleep 1
      rescue => e
        log("Error " + e.inspect )
      end
     end
     begin
       worker.close
     rescue
       log("Error releasing socket")
     end
    end
  end

  def create(y)
    log("Creating " + y[:object].to_s ) if @dg
    case y[:object]
      when "server"
        s = db { Server.find(y[:objectid]) }
        again = true
        begin
          scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :image => s.image, :offer => s.offer, :firewall => s.firewall, :keypair => s.keypair, :server => s)
          s.serial = scloud.runinstances
        rescue => e
          if again 
             s.serial = nil
             again = false
             sleep 3
             retry
          end
        end
        if s.serial 
          log("saving " + y[:object].to_s + " " + s.serial.to_s ) if @dg
          db { s.save }
        else
          log("destroying " + s.id.to_s)
          db { s.destroy }
        end
      when "firewall"
        f = db { Firewall.find(y[:objectid]) }
        again = true
        begin 
          fcloud = Oecloud.new(:zone => f.zone, :key => f.zone.key, :secret => f.zone.secret, :firewall => f)
          f.serial = fcloud.createsecuritygroup
        rescue => e
          if again
             f.serial = nil
             again = false
             sleep 3
             retry
          end
        end
        if f.serial
          log("saving " + y[:object].to_s + " " + f.serial.to_s ) if @dg
          db { f.save }
        else
          log("destroying " + f.id.to_s)
          db { f.destroy }
        end
      when "volume"
        v = db { Volume.find(y[:objectid]) }
        again = true
        begin
          vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v)
          v.serial = vcloud.createvolume
        rescue => e
          if again
             v.serial = nil
             again = false
             sleep 3
             retry
          end
        end
        if v.serial
          log("saving " + y[:object].to_s + " " + v.serial.to_s ) if @dg
          db { v.save }
        else
          log("destroying " + v.id.to_s)
          db { v.destroy }
        end
      when "loadbalancer"
        l = db { Loadbalancer.find(y[:objectid]) }
        lcloud = Oecloud.new(:zone => l.zone, :key => l.key, :secret => l.secret, :loadbalancer => l)
        l.serial = lcloud.createloadbalancer
        db { l.save }
      when "rule"
        r = db { Rule.find(y[:objectid]) }
        again = true
        begin
          rcloud = Oecloud.new(:zone => r.firewall.zone, :key => r.firewall.zone.key, :secret => r.firewall.zone.secret, :firewall => r.firewall, :rule => r)
          rserial = rcloud.authorizedsecuritygroupingress
        rescue => e
          if again
             rserial = false
             again = false
             sleep 3 
             retry
          end
        end
        if not rserial
                log("destroying " + y[:object].to_s + " " + r.id.to_s )
                db { r.destroy }
        else   
                log("rule created " + r.id.to_s )
                r.serial = rserial 
                db { r.save }
        end
      when "keypair"
         k = db { Keypair.find(y[:objectid]) }
         again = true
         begin
           kcloud = Oecloud.new(:zone => k.zone, :key => k.zone.key, :secret => k.zone.secret, :keypair => k)
           k.private = kcloud.createkeypair
         rescue => e
           if again
              k.private = nil
              again = false
              sleep 3
              retry 
           end
         end
         if k.private 
           log("saving " + y[:object].to_s + " " + k.name.to_s ) if @dg
           db { k.save } 
         else
           log("destroying key " + k.id.to_s)
           db { k.destroy }
         end
      when "ips"

      when "infrastructure"
         i = db { Infrastructure.find(y[:objectid]) }
	 log("Creating infrastructure #{i.name}")
         i.keypairs.each do |k|
           again = true
           begin
             kcloud = Oecloud.new(:zone => k.zone, :key => k.zone.key, :secret => k.zone.secret, :keypair => k)
             k.private = kcloud.createkeypair
           rescue => e
             if again
                k.private = nil
                again = false
		sleep 3
		retry
	     end
           end
	   if k.private 
             db { k.save }
	     log("Creating keypair under infrastructure #{i.name}")
           else
	     db { k.destroy }
	     log("Couldn't create keypair, removing record from database ")
 	   end
	   sleep 1
         end
         i.firewalls.each do |f|
	   again = true
	   begin
             fcloud = Oecloud.new(:zone => f.zone, :key => f.zone.key, :secret => f.zone.secret, :firewall => f)
             f.serial = fcloud.createsecuritygroup
           rescue => e
	     if again
		f.serial = nil
		again = false
		sleep 3
		retry
	     end
	   end
	   if f.serial
	     db { f.save }
	     log("Creating firewall under infrastructure #{i.name}")
	   else
	     db { f.destroy }
	     log("Couldn't create firewall, removing record from the databse ")
	   end
	   sleep 1
         end
         i.rules.each do |r|
	   again = true
	   begin
             rcloud = Oecloud.new(:zone => r.firewall.zone, :key => r.firewall.zone.key, :secret => r.firewall.zone.secret, :firewall => r.firewall, :rule => r)
	     rl = rcloud.authorizedsecuritygroupingress
 	   rescue => e
	     if again
		rl = false
		again = false
		sleep 3
		retry
	     end
	   end
	   if rl
	     db { r.save } 
	     log("Creating rule under infrastructure #{i.name}")
	   else
	     db { r.destroy }
	     log("Couldn't create rule, removing record from database ")
	   end
	   sleep 1
         end
         i.volumes.each do |v|
	   again = true
	   begin
             vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v)
             v.serial = vcloud.createvolume
	   rescue => e
	     if again
		v.serial = nil
		again = false
		sleep 3
		retry
	     end
	   end
	   if v.serial
	      db { v.save }
	      log("Creating volume under infrastructure #{i.name}")
	   else
	      db { v.destroy }
	      log("Couldn't create volume, removing record from database")
	   end
	   sleep 1
         end
         i.servers.each do |s|
	   again = true
	   begin
             scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :image => s.image, :offer => s.offer, :firewall => s.firewall, :keypair => s.keypair, :server => s)
             s.serial = scloud.runinstances
	   rescue => e
	     if again
		s.serial = nil
		again = false
		sleep 3
		retry
	     end
	   end
	   if s.serial
	     db { s.save }
	     log("Creating server under infrastructure #{i.name}")
	   else
	     db { s.destroy }
	     log("Counldn't create server, removing record from database")
	   end
	   sleep 1
         end
    end
  end

  def update(y)
    log("Updating " + y[:object].to_s ) if @dg
    case y[:object]
      when "server"
        s = db { Server.find(y[:objectid]) }
	again = true
        preStat = s.status
        begin
          scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :server => s)
          case y[:actobject]
            when "start"
                status = scloud.startinstances
            when "stop"
	        status = scloud.stopinstances
          end
        rescue => e
	  if again
	     status = nil
	     again = false
	     sleep 3
	     retry
	  end
	end
        if status
           s.status = status
           db { s.save }
           log("Moving instance from status #{preStat} to #{status}")
        else
           s.status = preStat
           db { s.save }
           log("Couldn't move instance to new status leaving in old #{preStat}")
        end
      when "volume"
          v = db { Volume.find(y[:objectid]) }
        again = true
	begin
          vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v, :server => v.server )
          case y[:actobject]
            when "attach"
               vol = vcloud.attachevolume
            when "dettach"
               vol = vcloud.detachvolume
          end
	rescue => e
	  if again
	     again = false
	     sleep 3
	     retry
	  end
        end
        if vol 
           db { v.save }
        else
           v.server = nil
           db { v.save }
        end
      when "loadbalancer"
        l = Loadbalancer.find(y[:objectid])
        lcloud = Oecloud.new(:zone => l.zone, :key => l.zone.key, :secret => l.zone.secret, :loadbalancer => l)
      when "ips"
    end
  end

  def delete(y)
    log("Delete " + y[:object].to_s ) if @dg
    case y[:object]
      when "server"
        s = db { Server.find(y[:objectid]) }
        again = true
	begin
          scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :server => s)
          if scloud.terminateinstances
            log("destroying " + s.id.to_s)
            db { s.destroy }
          end
	rescue => e
	   if again
	      again = false
	      sleep 3 
	      retry
	   end
	end

      when "firewall"
        f = db { Firewall.find(y[:objectid]) }
        again = true
        begin 
          fcloud = Oecloud.new(:zone => f.zone, :key => f.zone.key, :secret => f.zone.secret, :firewall => f)
          if fcloud.deletesecuritygroup
            log("destroying " + f.id.to_s)
            db { f.destroy }
          end
        rescue => e
          if again
             again = false
             sleep 3
             retry
          end
        end
      when "volume"
        v = db { Volume.find(y[:objectid]) } 
        again = true
        begin
          vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v)
          if vcloud.deletevolume
            log("destroying " + v.id.to_s)
             db { v.destroy }
          end
        rescue => e
          if again
             again = false
             sleep 3
             retry
          end
        end
      when "loadbalancer"
        l = db { Loadbalancer.find(y[:objectid]) }
        again = true
        begin
          lcloud = Oecloud.new(:zone => l.zone, :key => l.zone.key, :secret => l.zone.secret, :loadbalancer => l)
          if lcloud.deleteloadbalancer
            db { l.destroy }
          end
        rescue => e
          if again
	     again = false
	     sleep 3
	     retry
          end
	end
      when "rule"
        r = db { Rule.find(y[:objectid]) }
        again = true
        begin
          rcloud = Oecloud.new(:zone => r.firewall.zone, :key => r.firewall.zone.key, :secret => r.firewall.zone.secret, :firewall => r.firewall, :rule => r)
          if rcloud.revokesecuritygroupingress
            log("destroying " + r.id.to_s)
                db { r.destroy }
          end
        rescue => e
          if again
	     again = false
	     sleep 3
	     retry
	  end
	end
      when "keypair"
         k = db { Keypair.find(y[:objectid]) }
	 again = true
	 begin
           kcloud = Oecloud.new(:zone => k.zone, :key => k.zone.key, :secret => k.zone.secret, :keypair => k)
           if kcloud.deletekeypair
             log("destroying " + y[:object].to_s + " " + k.name.to_s ) if @dg
             db { k.destroy }
           end
	 rescue => e
	   if again 
	      again = false
	      sleep 3
	      retry
	   end
	 end

      when "ips"
      when "infrastructure"
         i = db { Infrastructure.find(y[:objectid]) }
	 log("Destroying resources of infrastructre #{i.name}")
         i.servers.each do |s|
 	   again = true
	   begin
             scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :image => s.image, :offer => s.offer, :firewall => s.firewall, :server => s)
             if scloud.terminateinstances
               db { s.destroy } 
	       log("Destroying servers resources of infrastructre #{i.name}")
	     end
	   rescue => e
	     if again
	  	again = false
	  	sleep 3
		retry
	     end
	   end
	   sleep 1
         end
         i.volumes.each do |v|
	   again = true
	   begin
             vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v)
             if vcloud.deletevolume
               db { v.destroy }
	       log("Destroying volumes resources of infrastructre #{i.name}")
	     end
	   rescue => e
	     if again
		again = false
		sleep 3
		retry
	     end
	   end
	   sleep 1
         end
         i.firewalls.each do |f|
	   again = true
	   begin
             fcloud = Oecloud.new(:zone => f.zone, :key => f.zone.key, :secret => f.zone.secret, :firewall => f)
             if fcloud.deletesecuritygroup
               db { f.destroy }
	       log("Destroying firewalls resources of infrastructre #{i.name}")
	     end
	   rescue => e
	     if again
		again = false
	 	sleep 3
		retry
	     end
	   end
	   sleep 1
         end
         i.keypairs.each do |k|
	   again = true
	   begin
             kcloud = Oecloud.new(:zone => k.zone, :key => k.zone.key, :secret => k.zone.secret, :keypair => k)
             if kcloud.deletekeypair
               db { k.destroy }
	       log("Destroying keypair resources of infrastructre #{i.name}")
	     end
	   rescue => e
	     if again
		again = false
	  	sleep 3
		retry
	     end
	   end
	   sleep 1
         end
    end
  end

  def sendtask(y)
      case y[:object].to_s
        when "server"
        when "task"
        when "role"
        when "workflow"
        when "deployment"
      end
  end
  
  def get(y)
    case y[:object].to_s
      when "server"
        s = db { Server.find(y[:objectid]) }
	again = true
	begin
          scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :server => s)
          s.ip, s.status, s.fqdn = scloud.getserverstatus()
          db { s.save }
	rescue => e
	  if again
	     again = false
	     sleep 3
	     retry
	  end
	end
    end
  end

  def installclient(y)
    s = db { Server.find(y[:objectid]) }
    again = true
    begin
      scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :server => s)
      ip, status, fqdn = scloud.getserverstatus()
      case status.to_s.downcase
        when "running", "active"
           %x[echo "#{s.keypair.private}" > /tmp/#{fqdn}-#{ip} ; chmod 400 /tmp/#{fqdn}-#{ip} ; ]
           %x[ssh -i /tmp/#{fqdn}-#{ip} root@#{ip} "wget -O /tmp/install.sh http://www.openescalar.org/download/install.sh ; sh /tmp/install.sh" ]
           sleep 120
           again = false
        when "pending", "build"
           sleep 120
           retry
        else
           again = false
      end
    rescue => e
      if again
        sleep 3
        retry
      else
        again = false
      end
    end
  end

end
