module AgCalDAV
  class Client
    include Icalendar
    attr_accessor :host, :port, :url, :user, :password, :ssl

    def format=( fmt )
      @format = fmt
    end

    def format
      @format ||= Format::Debug.new
    end

    def initialize( data )
      unless data[:proxy_uri].nil?
        proxy_uri   = URI(data[:proxy_uri])
        @proxy_host = proxy_uri.host
        @proxy_port = proxy_uri.port.to_i
      end
      uri = URI(data[:uri])
      @host     = uri.host
      @port     = uri.port.to_i
      @url      = uri.path
      @user     = data[:user]
      @password = data[:password]
      @ssl      = uri.scheme == 'https'
    end

    def __create_http
      if @proxy_uri.nil?
        http = Net::HTTP.new(@host, @port)
      else
        http = Net::HTTP.new(@host, @port, @proxy_host, @proxy_port)
      end
      if @ssl
        http.use_ssl = @ssl
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http
    end

    def find_events data
      result = ""
      events = []
      res = nil
      __create_http.start {|http|
        req = Net::HTTP::Report.new(@url, initheader = {'Content-Type'=>'application/xml'} )
        req.basic_auth @user, @password
        req.body = AgCalDAV::Request::ReportVEVENT.new(DateTime.parse(data[:start]).strftime("%Y%m%dT%H%M"), 
                                                       DateTime.parse(data[:end]).strftime("%Y%m%dT%H%M") ).to_xml
        res = http.request(req)
      } 
        errorhandling res
        result = ""
        xml = REXML::Document.new(res.body)
        REXML::XPath.each( xml, '//c:calendar-data/', {"c"=>"urn:ietf:params:xml:ns:caldav"} ){|c| result << c.text}
        r = Icalendar.parse(result)      
        unless r.empty?
          r.each do |calendar|
            calendar.events.each do |event|
              events << event
            end
          end
          events
        else
          return false
        end
    end

    def find_event uuid
      res = nil
      __create_http.start {|http|
        req = Net::HTTP::Get.new("#{@url}/#{uuid}.ics")
        req.basic_auth @user, @password
        res = http.request( req )
      }  
      errorhandling res
      r = Icalendar.parse(res.body)
      unless r.empty?
        r.first.events.first 
      else
        return false
      end

      
    end

    def delete_event uuid
      res = nil
      __create_http.start {|http|
        req = Net::HTTP::Delete.new("#{@url}/#{uuid}.ics")
        req.basic_auth @user, @password
        res = http.request( req )
      }
      errorhandling res
      if res.code.to_i == 200
        return true
      else
        return false
      end
    end

    def create_event event
      c = Calendar.new
      c.events = []
      uuid = UUID.new.generate
      raise DuplicateError if entry_with_uuid_exists?(uuid)
      c.event do
        uid           uuid 
        dtstart       DateTime.parse(event[:start])
        dtend         DateTime.parse(event[:end])
        categories    event[:categories]# Array
        contacts       event[:contacts] # Array
        attendees      event[:attendees]# Array
        duration      event[:duration]
        summary       event[:title]
        description   event[:description]
        klass         event[:accessibility] #PUBLIC, PRIVATE, CONFIDENTIAL
        location      event[:location]
        geo_location  event[:geo_location]
        status        event[:status]
      end
      cstring = c.to_ical
      res = nil
      http = Net::HTTP.new(@host, @port)
      __create_http.start { |http|
        req = Net::HTTP::Put.new("#{@url}/#{uuid}.ics")
        req['Content-Type'] = 'text/calendar'
        req.basic_auth @user, @password
        req.body = cstring
        res = http.request( req )
      }
      errorhandling res
      find_event uuid
    end

    def update_event uuid, event
      #TODO... fix me
      if delete_event uuid
        create_event event
      else
        return false
      end
    end

    def add_alarm tevent, altCal="Calendar"
    
    end

   







    def find_todo uuid
      res = nil
      __create_http.start {|http|
        req = Net::HTTP::Get.new("#{@url}/#{uuid}.ics")
        req.basic_auth @user, @password
        res = http.request( req )
      }  
      errorhandling res
      r = Icalendar.parse(res.body)
      r.first.todos.first
    end





    def create_todo todo
      c = Calendar.new
      uuid = UUID.new.generate
      raise DuplicateError if entry_with_uuid_exists?(uuid)
      c.todo do
        uid           uuid 
        start         DateTime.parse(todo[:start])
        duration      todo[:duration]
        summary       todo[:title]
        description   todo[:description]
        klass         todo[:accessibility] #PUBLIC, PRIVATE, CONFIDENTIAL
        location      todo[:location]
        percent       todo[:percent]
        priority      todo[:priority]
        url           todo[:url]
        geo           todo[:geo_location]
        status        todo[:status]
      end
      c.todo.uid = uuid
      cstring = c.to_ical
      res = nil
      http = Net::HTTP.new(@host, @port)
      __create_http.start { |http|
        req = Net::HTTP::Put.new("#{@url}/#{uuid}.ics")
        req['Content-Type'] = 'text/calendar'
        req.basic_auth @user, @password
        req.body = cstring
        res = http.request( req )
      }
      errorhandling res
      find_todo uuid
    end

    def create_todo
      res = nil
      raise DuplicateError if entry_with_uuid_exists?(uuid)

      __create_http.start {|http|
        req = Net::HTTP::Report.new(@url, initheader = {'Content-Type'=>'application/xml'} )
        req.basic_auth @user, @password
        req.body = AgCalDAV::Request::ReportVTODO.new.to_xml
        res = http.request( req )
      }
      errorhandling res 
      format.parse_todo( res.body )
    end

    private
    def entry_with_uuid_exists? uuid
      res = nil
      __create_http.start {|http|
        req = Net::HTTP::Get.new("#{@url}/#{uuid}.ics")
        req.basic_auth @user, @password
        res = http.request( req )
      }      
      if res.body.empty?
        return false
      else
        return true
      end
    end

    def  errorhandling response   
      raise AuthenticationError if response.code.to_i == 401
      raise NotExistError if response.code.to_i == 410 
      raise APIError if response.code.to_i >= 500
    end
  end





  class AgCalDAVError < StandardError
  end
  class AuthenticationError < AgCalDAVError; end
  class DuplicateError      < AgCalDAVError; end
  class APIError            < AgCalDAVError; end
  class NotExistError       < AgCalDAVError; end
end
