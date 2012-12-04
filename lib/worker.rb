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
             when "get"
                get(m)
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

#   def import(y)
#    case y[:object]
#     when "zone"
#	z = Zone.find(y[:objectid])
#        cloud = Oecloud.new(:zone => z, :key => z.key, :secret => z.secret)
#
#        i = cloud.describeimages
#        i.each { |img| Image.create(:serial => img[:id], :description => img[:description], :arch => img[:arch], :zone_id => z.id, :account_id => z.account_id) } if i
#
#        f = cloud.describesecuritygroups
#        f.each { |fw| fw1 = Firewall.create(:serial => fw[:id], :description => fw[:description], :name => fw[:name], :zone_id => z.id, :account_id => z.account_id)
#	  r = cloud.describerules(fw1.serial)
#          r.each { |r1|
#              Rule.create(:fromport => r1[:fromport], :toport => r1[:toport], :source => r1[:source], :protocol => r1[:protocol], :firewall_id => fw1.id, :account_id => z.account_id) if not r1[:source].nil? 
#  	    } if r
#          } if f
#
#        #l = cloud.describeloadbalancers
#        #l.each do |lb|
#        #  Loadbalancer.create(:serial => lb["id"], :description => lb["description"], :port => lb["port"], :serverport => lb["serverport"], :protocol => lb["protocol"], :zone_id => z.id, :azone_id => lb["availability"], :account_id => z.account_id)
#        #end
#
#        #s = z.describeinstances
#        #s.each do |serv|
##	#  img = Image.where("serial = ? and account_id = ?", serv["image"],z.account_id)
##	#  lb = Loadbalancer.where("serial = ? and account_id = ?", serv["loadbalancer"], z.account_id)
#        #  fw = Firewall.where("serial = ? and account_id = ?", serv["firewall"],z.account_id)
#        #  Server.create(:serial => serv["id"], :fqdn => serv["fqdn"], :ip => serv["public"], :pip => serv["private"], :zone_id => z.id, :azone_id => serv["availability"], :offer_id  => serv["offer"], :image_id => img.id, :loadbalancer_id => lb.id, :firewall_id => fw.id)
#        #end
#
#        v = cloud.describevolumes
##        v.each { |vol| Volume.create(:serial => vol[:id], :description => vol[:description], :size => vol[:size], :zone_id => z.id, :azone_id => vol[:availability], :account_id => z.account_id) } if v
#    end
#  end

  def create(y)
    log("Creating " + y[:object].to_s ) if @dg
    case y[:object]
      when "server"
        s = db { Server.find(y[:objectid]) }
        scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :image => s.image, :offer => s.offer, :firewall => s.firewall, :keypair => s.keypair, :server => s)
        s.serial = scloud.runinstances
        if s.serial 
          log("saving " + y[:object].to_s + " " + s.serial.to_s ) if @dg
          db { s.save }
        else
          log("destroying " + s.id.to_s)
          db { s.destroy }
        end
      when "firewall"
        f = db { Firewall.find(y[:objectid]) }
        fcloud = Oecloud.new(:zone => f.zone, :key => f.zone.key, :secret => f.zone.secret, :firewall => f)
        f.serial = fcloud.createsecuritygroup
        if f.serial
          log("saving " + y[:object].to_s + " " + f.serial.to_s ) if @dg
          db { f.save }
        else
          log("destroying " + f.id.to_s)
          db { f.destroy }
        end
      when "volume"
        v = db { Volume.find(y[:objectid]) }
        vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v)
        v.serial = vcloud.createvolume
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
        rcloud = Oecloud.new(:zone => r.firewall.zone, :key => r.firewall.zone.key, :secret => r.firewall.zone.secret, :firewall => r.firewall, :rule => r)
        rserial = rcloud.authorizedsecuritygroupingress
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
         kcloud = Oecloud.new(:zone => k.zone, :key => k.zone.key, :secret => k.zone.secret, :keypair => k)
         k.private = kcloud.createkeypair
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
         i.keypairs.each do |k|
           kcloud = Oecloud.new(:zone => k.zone, :key => k.zone.key, :secret => k.zone.secret, :keypair => k)
           k.private = kcloud.createkeypair
           DB { k.save }
         end
         i.firewalls.each do |f|
           fcloud = Oecloud.new(:zone => f.zone, :key => f.zone.key, :secret => f.zone.secret, :firewall => f)
           f.serial = fcloud.createsecuritygroup
           db { f.save }
         end
         i.rules.each do |r|
           rcloud = Oecloud.new(:zone => r.firewall.zone, :key => r.firewall.zone.key, :secret => r.firewall.zone.secret, :firewall => r.firewall, :rule => r)
           db { r.destroy } if not rcloud.authorizedsecuritygroupingress
         end
         i.volumes.each do |v|
           vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v)
           v.serial = vcloud.createvolume
           db { v.save } if v.serial
         end
         i.servers.each do |s|
           scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :image => s.image, :offer => s.offer, :firewall => s.firewall, :keypair => s.keypair, :server => s)
           s.serial = scloud.runinstances
           db { s.save } if s.serial
         end
    end
  end

  def update(y)
    log("Updating " + y[:object].to_s ) if @dg
    case y[:object]
      when "server"
        s = db { Server.find(y[:objectid]) }
        scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :server => s)
        case y[:actobject]
          when "start"
              status = scloud.startinstances
          when "stop"
	      status = scloud.stopinstances
        end
        if status
           s.status = status
           db { s.save }
        end
      when "volume"
          v = db { Volume.find(y[:objectid]) }
        vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v, :server => v.server )
        case y[:actobject]
          when "attach"
             vol = vcloud.attachevolume
          when "dettach"
             vol = vcloud.detachvolume
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
        scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :server => s)
        if scloud.terminateinstances
          log("destroying " + s.id.to_s)
          db { s.destroy }
        end
      when "firewall"
        f = db { Firewall.find(y[:objectid]) }
        fcloud = Oecloud.new(:zone => f.zone, :key => f.zone.key, :secret => f.zone.secret, :firewall => f)
        if fcloud.deletesecuritygroup
          log("destroying " + f.id.to_s)
          db { f.destroy }
        end
      when "volume"
        v = db { Volume.find(y[:objectid]) } 
        vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v)
        if vcloud.deletevolume
          log("destroying " + v.id.to_s)
           db { v.destroy }
        end
      when "loadbalancer"
        l = db { Loadbalancer.find(y[:objectid]) }
        lcloud = Oecloud.new(:zone => l.zone, :key => l.zone.key, :secret => l.zone.secret, :loadbalancer => l)
        if lcloud.deleteloadbalancer
          db { l.destroy }
        end
      when "rule"
        r = db { Rule.find(y[:objectid]) }
        rcloud = Oecloud.new(:zone => r.firewall.zone, :key => r.firewall.zone.key, :secret => r.firewall.zone.secret, :firewall => r.firewall, :rule => r)
        if rcloud.revokesecuritygroupingress
          log("destroying " + r.id.to_s)
                db { r.destroy }
        else 
          log("rule remained " + r.id.to_s)
        end
      when "keypair"
         k = db { Keypair.find(y[:objectid]) }
         kcloud = Oecloud.new(:zone => k.zone, :key => k.zone.key, :secret => k.zone.secret, :keypair => k)
         if kcloud.deletekeypair
           log("destroying " + y[:object].to_s + " " + k.name.to_s ) if @dg
           db { k.destroy }
         else
           log("key remained" + k.id.to_s)
         end

      when "ips"
      when "infrastructure"
         i = db { Infrastructure.find(y[:objectid]) }
         i.servers.each do |s|
           scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :image => s.image, :offer => s.offer, :firewall => s.firewall)
           scloud.terminateinstances
           db { s.destroy } 
         end
         i.volumes.each do |v|
           vcloud = Oecloud.new(:zone => v.zone, :key => v.zone.key, :secret => v.zone.secret, :volume => v)
           vcloud.deletevolume
           db { v.destroy }
         end
         i.firewalls.each do |f|
           fcloud = Oecloud.new(:zone => f.zone, :key => f.zone.key, :secret => f.zone.secret, :firewall => f)
           fcloud.deletesecuritygroup
           db { f.destroy }
         end
         i.keypairs.each do |k|
           kcloud = Oecloud.new(:zone => k.zone, :key => k.zone.key, :secret => k.zone.secret, :keypair => k)
           kcloud.deletekeypair
           db { k.destroy }
         end
    end
  end
  
  def get(y)
    case y[:object].to_s
      when "server"
        s = db { Server.find(y[:objectid]) }
        scloud = Oecloud.new(:zone => s.zone, :key => s.zone.key, :secret => s.zone.secret, :server => s)
        s.ip, s.status, s.fqdn = scloud.describeinstances()
        db { s.save }
    end
  end

end
