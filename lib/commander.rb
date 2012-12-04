#!/opt/ruby/bin/ruby
#require '/opt/openescalar/amun-tools/lib/amun/config/environment.rb'
require 'zmq'
require 'yaml'
require 'syslog'
require 'active_record'
gem 'multi_json', '1.0.3'
#Loading libs
%w{ oecompiler oedist oedsl oeencrypt awsapi osapi eucaapi hpos rsapi }.each { |x| require "/opt/openescalar/amun-tools/lib/amun/lib/#{x}.rb" }
#Dir["/opt/openescalar/amun-tools/lib/amun/lib/*.rb"].each {|file| require file }
#Loading models
Dir["/opt/openescalar/amun-tools/lib/amun/app/models/*.rb"].each {|file| require file }

class Commander
  
  def initialize
     @loop = true 
     ActiveRecord::Base.establish_connection(YAML.load_file('/opt/openescalar/amun-tools/conf/commander.conf')["database"])
  end

  def log(message)
    Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.warning self.class.to_s + " - " + message }
  end


  def start
    begin
      @loop = true
      reducer
      mainListen
      log("STARTING")
    rescue 
      log("Error Connection to coordinator")
    end    
  end

  def stop
    @loop = false
    @t.join
    @t2.join
    log("SHUTING DOWN")
  end

  def mainListen
    @t2 = Thread.new do 
      begin 
         contxt = ZMQ::Context.new
         fromCollect = contxt.socket(ZMQ::UPSTREAM)
         fromCollect.bind("tcp://*:22347")
	 toCoor = contxt.socket(ZMQ::DOWNSTREAM)
	 toCoor.connect("tcp://*:12345")
      rescue
	log("Error reserving port")
      end
      while @loop
        begin
	  msg = fromCollect.recv(ZMQ::NOBLOCK)
          if msg
	    log("received alert " + msg)
            m = YAML.load(msg)
            if m[:action] != "POWEROFF"
	      objectid = m[:serial]
	      vtarget = Server.where("serial = ?", objectid)[0]
              nvote = 999999
              iescala = ""
              if not vtarget.nil?
	         iescala = vtarget.infraescala_id
                 nvote = Vote.where("serial = ? and infraescala_id = ?", objectid, iescala).size
	      end
	      if nvote == 0
	        Vote.create(:serial => objectid, :infraescala_id => iescala)
                sca = Infraescala.find(iescala)
	        sca.ivote += 1
	        sca.save
	        if sca.ivote >= sca.iescalar and sca.iactive <= sca.imax
		  msg = {:action => "create", :object => "server", :serial => vtarget.serial}.to_yaml
		  log("sending scale " + msg)
	          toCoor.send(msg)
	          sca.ivote = 0
		  sca.iactive += 1
	          sca.save
		  Vote.where(:infraescala_id => iescala).destroy_all
	        end
              end
            end
          end
          sleep 1
        rescue ZMQ::Error => e
	   log(e.inspect)
        rescue => e
           log(e.inspect)
        end
      end
      begin
	fromCollect.close
        toCoor.close
      rescue
        log("Error while closing zmq socket")
      end
    end
  end

  def reducer
           @t = Thread.new do
	     begin
                contxt = ZMQ::Context.new
		toCoordinator = contxt.socket(ZMQ::DOWNSTREAM)
		toCoordinator.connect("tcp://*:12345")
             rescue
		log("error while connecting to coordinator")
             end
             while @loop
                 rescale = Infraescala.where("updated_at < ?", Time.now.utc - 600)
                 rescale.each do |v|
                   if v.iorig < v.iactive
		     ##### Por el momento solo vamos a tener scale en servers
		     serial = Server.find(:all, :select => 'serial', :conditions => ['infraescala_id = ?',v.id], :limit => 1)[0]["serial"]
		     msg = {:action => "delete", :object => "server", :serial => serial}.to_yaml
		     log("sending reduce " + msg)
		     toCoordinator.send(msg)
                     v.iactive = v.iactive - 1
                     v.ivote = 0
                     v.save
		     Vote.where(:infraescala_id => v.id).destroy_all
		   else
		     v.ivote = 0
                     v.save
                     Vote.where(:infraescala_id => v.id).destroy_all
                   end
                 end
                 sleep(60)
             end
	     begin
		toCoordinator.close
	     rescue
		log("error shutingdown redurcer socket to coordinator")
	     end
           end
  end

#### NOte
# Ahorita todo va a kedar atorado en la cola asi k vamos a hacer k al mismo tiempo k voten entonces busquen si tienen k escalar o no de otra forma no tiene sentido ya que necesi
#otro thread para k este agarrando los votos y otro para k este monitoreando si tiene k escalar o no, kisas esa sea una mejor forma de escalar esto pero por ahora vamos a dejarl
#asi para poder hacerlo funcionar y luego vemos el hecho de tener varios corriendo al mismo tiempo, aun tengo que probar que ZMQ no blooquee el segundo thread mientras esta escu
#          sca = Infraescala.where("updated_at > ?", Time.now.utc - 600) #Looks for escalars that were updated in the last 10 mins)
 #        sca.each do |v|
 #           if v.ivote => v.iescalar and v.iactive <= v.imax
#       ### send msg to scale
#               v.ivote = 0
#               v.save
#            end
#         end


end
