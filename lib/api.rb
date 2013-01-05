#!/opt/ruby/bin/ruby
#require '/opt/openescalar/amun-tools/lib/amun/config/environment.rb'
require 'zmq'
require 'yaml'
require 'syslog'
require 'sinatra'
require 'active_record'
require 'uri'
gem 'multi_json', '1.0.3'
#Loading libs
%w{ oecompiler oedist oedsl oeencrypt awsapi osapi eucaapi hpos rsapi }.each { |x| require "/opt/openescalar/amun-tools/lib/amun/lib/#{x}.rb" }
#Loading models
Dir["/opt/openescalar/amun-tools/lib/amun/app/models/*.rb"].each {|file| require file }


def log(message)
  Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.warning self.class.to_s + " -  " + message }
end


ActiveRecord::Base.establish_connection(YAML.load_file('/opt/openescalar/amun-tools/conf/api.conf')["database"])

def db(&block)
  ActiveRecord::Base.connection_pool.with_connection &block
end

get '/' do
  404
end

get '/task' do
  act = db { Account.find_by_key(URI.unescape(params[:key])) } if params[:key]
  log("API - Looking for key " + params[:key])
  if act
    log("API - got key for account - " + act.id.to_s)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "gettask"
          log("Getting tasks " + params[:task].to_s )
          db { act.roletasks.find_by_serial(params[:task]).content }
        when "updatetask"
	  log("Updating Event Task")
          db { e = Event.find_by_ident(params[:ident]) 
               e.status = params[:code]
               e.output = URI.unescape(params[:output])
               e.save }
      end
    else
      log("error on encryption")
    end
  end
end

get '/builder' do
  act = db { Account.find_by_key(URI.unescape(params[:key])) } if params[:key]
  log("API - Looking for key " + params[:key])
  if act
    log("API - got key for account - " + act.id.to_s)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "build"
          log("Building server")
	  contxt = ZMQ::Context.new
          toCoor = contxt.socket(ZMQ::DOWNSTREAM)
          toCoor.connect("tcp://*:12345")
          srvserial = db { act.servers.find_by_serial(params[:serial]).serial }
          if srvserial
            msg = {:action => "build", :object => "server", :serial => srvserial }.to_yaml
            toCoor.send(msg)
          end
          toCoor.close
      end
    else
      log("API - Error on encryption")
    end
  end
end

get '/pingme' do
  act = db { Account.find_by_key(URI.unescape(params[:key])) } if params[:key]
  log("API - Looking for key " + params[:key])
  if act
    log("API - got key for account - " + act.id.to_s)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "ping"
        log "Ping from server #{params[:server]}"
        db { act.servers.find_by_serial(params[:server]).touch } 
        db { act.servers.find_by_serial(params[:server]).send_get } 
      end
    else
      log("error on encryption")
    end
  end
end

get '/bridge' do
  act = Account.find_by_key(URI.unescape(params[:key])) if params[:key]
  if act
    if Oeencrypt::decryptQuery(params,act.secret,act.key)
      case URI.unescape(params[:action])
        when "register"
        when "connect"
        when "disconnect"
        when "status"
      end
    end
  end
end

get '/escalar' do
  act = Account.find_by_key(URI.unescape(params[:key])) if params[:key]
  if act
    if Oeencrypt::decryptQuery(params,act.secret,act.key)
      case URI.unescape(params[:action])
        when ""
        when ""
      end
    end
  end
end

get '/metadata' do
  act = db { Account.find_by_key(URI.unescape(params[:key])) } if params[:key]
  log("API - Looking for key " + params[:key])
  if act
    log("API - got key for account - " + act.id.to_s)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) } and params[:action] == "download"
      if params[:action] == "download"
        case URI.unescape(params[:type])
          when "server"
             db { act.servers.find_by_serial(params[:server]).metadata }
          when "role"
             db { act.servers.find_by_serial(params[:server]).roles.find_by_serial(params[:role]).metadata }
          when "deployment"
             db { act.servers.find_by_serial(params[:server]).deployments.find_by_serial(params[:deployment]).metadata }
        end
      end
    else
      log("error on encryption")
    end
  end
end

get '/dns' do
  act = Account.find_by_key(URI.unescape(params[:key])) if params[:key]
  if act
    if Oeencrypt::decryptQuery(params,act.secret,act.key) 
    end
  end
end

get '*' do
  404
end



