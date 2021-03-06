module Rwepay::Common

  require 'digest/sha1'
  require 'digest/md5'
  require 'securerandom'
  require 'uri'
  require 'faraday'

  def self.configs_check(configs = {}, requires = [])
    requires.each do |require|
      unless configs.include? require
        raise "Rwepay Error, configs required hash symbol :#{require}"
      end
    end
    configs
  end

  def self.get_nonce_str
    SecureRandom.hex 16
  end

  def self.create_sign_string(sign_params = {}, sort = true)
    #对原串进行签名，注意这里不要对任何字段进行编码。这里是将参数按照key=value进行字典排序后组成下面的字符串,在这个字符串最后拼接上key=XXXX。由于这里的字段固定，因此只需要按照这个顺序进行排序即可。

    result_string = ''
    key = sign_params[:key]
    #是否排序
    if sort
      sign_params = sign_params.sort
    end

    sign_params.each{|key,value|
      result_string += (key.to_s + '=' + value.to_s + '&') if key.to_s != 'key'
    }

    "#{result_string}key=#{key}"
  end

  def self.create_pay_sign_string(sign_params = {}, sort = true)
    result_string = ''
    key = sign_params[:key]
    #是否排序
    if sort
      sign_params = sign_params.sort
    end

    sign_params.each{|key,value|
      result_string += (key.to_s + '=' + value.to_s + '&')
    }

    result_string[0, result_string.length - 1]
  end

  def self.md5_sign(for_sign_string)
    Digest::MD5.hexdigest(for_sign_string).upcase
  end

  def self.sha1_sign(for_sign_string)
    Digest::SHA1.hexdigest(for_sign_string)
  end

  def self.result_params_filter(sign_params, sort = true)
    result_string = ''
    #是否排序
    if sort
      sign_params = sign_params.sort
    end

    sign_params.each{|key,value|
      encode_value = URI.escape(value.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
      result_string += (key.to_s + '=' + encode_value + '&') if key.to_s != 'key'
    }
    #去掉末尾的&
    result_string = result_string[0, result_string.length - 1]
    return result_string
  end

  #get_package :bank_type, :body, :fee_type, :input_charset, :notify_url, :out_trade_no, :partner, :spbill_create_ip, :total_fee, :key
  def self.get_package(sign_params = {})
    for_sign_string   = create_sign_string sign_params
    md5_signed_string = md5_sign for_sign_string
    result_params     = result_params_filter sign_params

    "#{result_params}&sign=#{md5_signed_string}"
  end

  #sign_string :appid, :appkey, :noncestr, :package, :timestamp
  def self.pay_sign(sign_params = {})
    for_sign_string    = create_pay_sign_string sign_params
    sha1_signed_string = sha1_sign for_sign_string
    sha1_signed_string
  end

  def self.get_timestamps
    Time.now.to_i.to_s
  end

  def self.creat_notify_sign_string(params = {})
    key = params['key']
    result_string = ''
    sign_params = params.sort
    sign_params.each do |key, value|
      unless value.nil? or value == '' or key.to_s == 'key' or key.to_s == 'xml' or key.to_s == 'sign' or key.to_s == 'action'or key.to_s == 'controller'
        result_string += (key.to_s + '=' + value.to_s + '&')
      end
    end

    "#{result_string}key=#{key}"
  end

  def self.notify_sign(sign_params = {})
    for_sign_string = creat_notify_sign_string sign_params
    md5_signed_string = md5_sign for_sign_string

    md5_signed_string
  end

  def self.send_deliver_notify(options = {}, access_token = '')
    for_sign_data = {
        :appid             => options[:app_id],
        :appkey            => options[:app_key],
        :openid            => options[:open_id],
        :transid           => options[:trans_id],
        :out_trade_no      => options[:out_trade_no],
        :deliver_timestamp => options[:deliver_timestamp],
        :deliver_status    => options[:deliver_status],
        :deliver_msg       => options[:deliver_msg]
    }

    result_string = ''
    sign_params = for_sign_data.sort

    sign_params.each{|key,value|
      result_string += (key.to_s + '=' + value.to_s + '&')
    }
    result_string = result_string[0, result_string.length - 1]

    for_sign_data[:app_signature] = sha1_sign result_string
    for_sign_data[:sign_method]   = 'sha1'

    for_sign_data.delete :appkey

    begin
      conn = Faraday.new(:url => "https://api.weixin.qq.com/pay/delivernotify?access_token=#{access_token}")
      response = conn.post do |req|
        req.body = for_sign_data.to_json.gsub(/\\u([0-9a-z]{4})/) {|s| [$1.to_i(16)].pack("U")}
      end
      response = JSON.parse response.body
      if response['errcode'] == 0
        return true, nil
      else
        return false, response
      end
    rescue => err
      return false, err
    end

  end

  def self.get_order_query(options = {}, access_token = '')
    package = "out_trade_no=#{options[:out_trade_no]}&partner=#{options[:partner_id]}"
    md5_package_sign = md5_sign "#{package}&key=#{options[:partner_key]}"
    for_sign_data = {
        :appid     => options[:app_id],
        :appkey    => options[:app_key],
        :package   => "#{package}&sign=#{md5_package_sign}",
        :timestamp => get_timestamps
    }

    result_string = ''
    sign_params = for_sign_data.sort

    sign_params.each{|key,value|
      result_string += (key.to_s + '=' + value.to_s + '&')
    }
    result_string = result_string[0, result_string.length - 1]

    for_sign_data[:app_signature] = sha1_sign result_string
    for_sign_data[:sign_method]   = 'sha1'

    for_sign_data.delete :appkey

    begin
      conn = Faraday.new(:url => "https://api.weixin.qq.com/pay/orderquery?access_token=#{access_token}")
      response = conn.post do |req|
        req.body = for_sign_data.to_json.gsub(/\\u([0-9a-z]{4})/) {|s| [$1.to_i(16)].pack("U")}
      end
      response = JSON.parse response.body
      if response['errcode'] == 0
        return true, response
      else
        return false, response
      end
    rescue => err
      return false, err
    end
  end

end
