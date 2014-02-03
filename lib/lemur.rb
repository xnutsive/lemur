require "lemur/version"

require 'digest/md5'
require 'multi_json'

module Lemur
  class ApiError < StandardError
	  attr_reader :data

	  def error_code
		  @data['error_code']
	  end

	  def error_data
		  @data['error_data']
	  end

	  def error_msg
		  @data['error_msg']
	  end

	  def initialize(data)
			@data = data
			message = "#{error_code}: #{error_msg}"
		  super(message)
	  end
  end

  class ApiParsingError < StandardError
	  attr_reader :url
	  attr_reader :body

		def initialize(responce)
			@url = responce.env[:url].to_s
			@body = responce.body
			message = "Wrong JSON at #{url}: #{body}"
			super(message)
		end
  end

  ODNOKLASSNIKI_API_URL = 'http://api.odnoklassniki.ru/fb.do'
  ODNOKLASSNIKI_NEW_TOKEN_URL = 'http://api.odnoklassniki.ru/oauth/token.do'

  class API
    
    def initialize(application_secret_key, application_key,  access_token, application_id = nil, refresh_token = nil)
      start_faraday
      @security_options = {
        application_secret_key: application_secret_key,
        application_key: application_key, access_token: access_token,
        application_id: application_id, refresh_token: refresh_token
      }
    end

    attr_reader :security_options, :request_options, :response, :connection

    def get_new_token
      if @security_options[:application_id].blank? || @security_options[:refresh_token].blank?
        raise ArgumentError, 'wrong number of arguments'
      end
      faraday_options = {
            :headers['Content-Type'] => 'application/json',
            :url => Lemur::ODNOKLASSNIKI_NEW_TOKEN_URL
          }
      conn = init_faraday(faraday_options)
      new_token_response = conn.post do |req|
                          req.params = { 
                                        refresh_token: @security_options[:refresh_token], grant_type: 'refresh_token',
                                        client_id: @security_options[:application_id],
                                        client_secret: @security_options[:application_secret_key]
                                       }
                        end
       new_token_response = MultiJson.load(new_token_response.body)
       @security_options[:access_token] = new_token_response['access_token']
       new_token_response['access_token']
    end

    def get_request(request_params)
      @request_options = request_params
      @response = @connection.get do |request|
                    request.params = final_request_params(@request_options.merge(application_key: security_options[:application_key]),
                                              security_options[:access_token])
     end
   end

    def get(request_params)
      @response = get_request(request_params)
      json_data = nil
      begin
        json_data = MultiJson.load(response.body)
      rescue MultiJson::DecodeError
	      json_data = MultiJson.load(response.body.gsub(/[^"]}/, '"}').gsub(/([^"}]),"/, '\1","')) #Есть случаи отдачи кривого JSON от одноклассников
			end
      if json_data.is_a? Hash
        if json_data['error_code']
          raise ApiError, json_data
        end
      end
      json_data
    rescue MultiJson::DecodeError
      raise ApiParsingError, @response
    end

    private

    def final_request_params(request_params, access_token)
      request_params.merge(sig: odnoklassniki_signature(request_params, access_token, security_options[:application_secret_key]),
                           access_token: security_options[:access_token],
                           application_key: security_options[:application_key])
    end

    def odnoklassniki_signature(request_params, access_token, application_secret_key)
      sorted_params_string = ""
      request_params = Hash[request_params.sort]
      request_params.each {|key, value| sorted_params_string += "#{key}=#{value}"}
      secret_part = Digest::MD5.hexdigest("#{access_token}#{application_secret_key}")
      Digest::MD5.hexdigest("#{sorted_params_string}#{secret_part}")
    end

    def start_faraday
      faraday_options = {
            :headers['Content-Type'] => 'application/json',
            :url => Lemur::ODNOKLASSNIKI_API_URL
          }
      @connection = init_faraday(faraday_options)
    end


    def init_faraday(faraday_options)
      Faraday.new(faraday_options) do |faraday|
            faraday.request  :url_encoded 
            faraday.response :logger
            faraday.adapter  Faraday.default_adapter
      end
    end


  end
  
end
