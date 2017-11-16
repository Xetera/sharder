require "dotenv"

begin
  Dotenv.load!
rescue
  puts "No .env file found"

  sleep
end

require "amqp"
require "discordcr"
require "json"
require "http"
require "redis"
require "./sharder/Shard"

client_id = ENV["DISCORD_CLIENT_ID"].to_u64

private def shard_variables_present
  ENV.has_key?("DISCORD_SHARD_INDEX") &&
    ENV.has_key?("DISCORD_SHARD_TOTAL") &&
    ENV.has_key?("DISCORD_SHARD_INITIALIZE")
end

token = ENV["DISCORD_TOKEN"]

if !token.starts_with? "Bot "
  token = "Bot #{token}"
end

shard_index, shard_total, shard_init = if shard_variables_present
  [
    ENV["DISCORD_SHARD_INDEX"].to_i32,
    ENV["DISCORD_SHARD_TOTAL"].to_i32,
    ENV["DISCORD_SHARD_INITIALIZE"].to_i32,
  ]
else
  response = HTTP::Client.get("https://discordapp.com/api/v6/gateway/bot",
    headers: HTTP::Headers{"Authorization" => token})
  if response.status_code == 200
    shards = JSON.parse(response.body)["shards"].as_i

    [0, shards, shards]
  else
    [0, 1, 1]
  end
end

shard_init.times do |shard_id|
  shard_id_current = shard_index + shard_id

  spawn do
    shard = Shard.new token, client_id, shard_id_current, shard_total

    shard.run
  end

  sleep 10.seconds
end

sleep
