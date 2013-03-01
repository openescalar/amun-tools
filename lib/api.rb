#!/opt/ruby/bin/ruby
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

##### All are crud operations
# /task
# /ping
# /olb
# /ovpn
# /odns
# /metadata
# /event
# /escalar


def log(message)
  Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.warning self.class.to_s + " -  " + message }
end


ActiveRecord::Base.establish_connection(YAML.load_file('/opt/openescalar/amun-tools/conf/api.conf')["database"])

def db(&block)
  ActiveRecord::Base.connection_pool.with_connection &block
end

def checkKey(p)
  log("API - Looking for key " + p[:key])
  if params[:key]
    db { Account.find_by_key(URI.unescape(p[:key])) }
  else
    false
  end
end

get '/' do
  404
end

get '/task' do
  if checkKey(p)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "get"
          db { act.roletasks.find_by_serial(params[:task]).content }
        when "create"
        when "update"
        when "delete"
        when "build"
      end
    else
      log("Error on encryption")
    end
  end
end

get '/ping' do
  if checkKey(p)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "get"
        when "create"
        when "update"
        db { act.servers.find_by_serial(params[:server]).touch } 
        db { act.servers.find_by_serial(params[:server]).send_get } 
        when "delete"
      end
    else
      log("Error on encryption")
    end
  end
end

get '/olb' do
  if checkKey(p)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "get"
        when "create"
        when "update"
        when "delete"
      end
    else
      log("Error on encryption")
    end
  end
end

get '/ovpn' do
  if checkKey(p)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "get"
        when "create"
        when "update"
        when "delete"
      end
    else
      log("Error on encryption")
    end
  end
end

get '/odns' do
  if checkKey(p)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "get"
        when "create"
        when "update"
        when "delete"
      end
    else
      log("Error on encryption")
    end
  end
end

get '/metadata' do
  if checkKey(p)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "get"
          case URI.unescape(params[:type])
            when "server"
               db { act.servers.find_by_serial(params[:server]).metadata }
            when "role"
               db { act.servers.find_by_serial(params[:server]).roles.find_by_serial(params[:role]).metadata }
            when "deployment"
               db { act.servers.find_by_serial(params[:server]).deployments.find_by_serial(params[:deployment]).metadata }
          end
        when "create"
        when "update"
        when "delete"
      end
    else
      log("Error on encryption")
    end
  end
end

get '/event' do
  if checkKey(p)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "get"
        when "create"
        when "update"
          db { e = Event.find_by_ident(params[:ident]) 
               e.status = params[:code]
               e.output = URI.unescape(params[:output])
               e.save }
        when "delete"
      end
    else
      log("Error on encryption")
    end
  end
end

get '/escalar' do
  if checkKey(p)
    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
      case URI.unescape(params[:action])
        when "get"
        when "create"
        when "update"
        when "delete"
      end
    else
      log("Error on encryption")
    end
  end
end


#get '/builder' do
#  act = db { Account.find_by_key(URI.unescape(params[:key])) } if params[:key]
#  log("API - Looking for key " + params[:key])
#  if act
#    log("API - got key for account - " + act.id.to_s)
#    if db { Oeencrypt::decryptQuery(params,act.secret,act.key) }
#      case URI.unescape(params[:action])
#        when "build"
#          log("Building server")
#	  contxt = ZMQ::Context.new
#          toCoor = contxt.socket(ZMQ::DOWNSTREAM)
#          toCoor.connect("tcp://*:12345")
#          srvserial = db { act.servers.find_by_serial(params[:serial]).serial }
#          if srvserial
#            msg = {:action => "build", :object => "server", :serial => srvserial }.to_yaml
#            toCoor.send(msg)
#          end
#          toCoor.close
#      end
#    else
#      log("API - Error on encryption")
#    end
#  end
#end

get '*' do
  404
end



