def initialize_amqp
  host = ENV["AMQP_HOST"]
  port = ENV["AMQP_PORT"].to_i32
  user = ENV["AMQP_USER"]
  pass = ENV["AMQP_PASS"]

  AMQP::Connection.new AMQP::Config.new host, port, user, pass
end
