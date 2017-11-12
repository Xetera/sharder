def initialize_redis
  host = ENV.has_key?("REDIS_HOST") ? ENV["REDIS_HOST"] : "127.0.0.1"
  port = ENV.has_key?("REDIS_PORT") ? ENV["REDIS_PORT"].to_i32 : 6379

  Redis.new host: host, port: port
end
