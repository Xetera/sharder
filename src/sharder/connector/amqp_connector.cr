def initialize_amqp
  host = ENV["AMQP_HOST"]
  port = ENV["AMQP_PORT"].to_i32
  user = ENV["AMQP_USER"]
  pass = ENV["AMQP_PASS"]

  conn = AMQP::Connection.new AMQP::Config.new host, port, user, pass

  conn.on_close do |code, msg|
    puts "amqp closed: #{code}: #{msg}"

    conn = initialize_amqp
  end

  conn
end
