require "amqp"
require "discordcr/*"
require "discordcr"
require "json"
require "redis"
require "./connector/*"

enum Opcode
  ChannelCreate = 0,
  ChannelDelete = 1,
  ChannelUpdate = 2,
  GuildBanAdd = 3,
  GuildBanRemove = 4,
  GuildCreate = 5,
  GuildDelete = 6,
  GuildEmojiUpdate = 7,
  GuildIntegrationsUpdate = 22,
  GuildMemberAdd = 8,
  GuildMemberRemove = 9,
  GuildMemberUpdate = 10,
  GuildMembersChunk = 23,
  GuildRoleCreate = 11,
  GuildRoleDelete = 12,
  GuildRoleUpdate = 13,
  GuildUpdate = 14,
  MessageCreate = 15,
  MessageDelete = 24,
  MessageDeleteBulk = 25,
  MessageUpdate = 26,
  PresenceUpdate = 16,
  Ready = 17,
  Resumed = 27,
  TypingStart = 18,
  UserUpdate = 19,
  VoiceServerUpdate = 20,
  VoiceStateUpdate = 21,
end

class Shard
  @amqp : AMQP::Connection
  @channel : AMQP::Channel
  @client : Discord::Client
  @exchange : AMQP::Exchange
  @redis : Redis
  @shard_id : Int32

  def initialize(token, client_id, shard_id, shard_total)
    @amqp = initialize_amqp
    @channel = @amqp.channel
    @exchange = @channel.default_exchange
    @shard_id = shard_id

    @amqp.on_close do |code, msg|
      puts "amqp closed: #{code}: #{msg}"

      @amqp = initialize_amqp
    end

    @redis = initialize_redis

    client = Discord::Client.new token: token, client_id: client_id, shard: {
      shard_id: shard_id.as(Int32),
      num_shards: shard_total.as(Int32),
    }

    # (Rust's serde JSON serialization story is infinitely better btw.)
    #
    # So what we do here is serialize the resultant JSON object to string form,
    # and then we insert the string `"d": {` at position 1 of the string and
    # insert `}` at the second-to-last position. This is probably more efficient
    # but for the most part this is done because I'm incredibly lazy and working
    # with JSON is annoying.
    #
    # If any Crystal core devs are there: please look at rust's `serde` library.
    # It is an inspiration to us all.

    client.on_channel_create do |payload|
      dispatch payload, Opcode::ChannelCreate
    end

    client.on_channel_delete do |payload|
      dispatch payload, Opcode::ChannelDelete
    end

    client.on_channel_update do |payload|
      dispatch payload, Opcode::ChannelUpdate
    end

    client.on_guild_ban_add do |payload|
      dispatch payload, Opcode::GuildBanAdd
    end

    client.on_guild_ban_remove do |payload|
      dispatch payload, Opcode::GuildBanRemove
    end

    client.on_guild_create do |payload|
      dispatch payload, Opcode::GuildCreate
    end

    client.on_guild_delete do |payload|
      dispatch payload, Opcode::GuildDelete
    end

    client.on_guild_emoji_update do |payload|
      dispatch payload, Opcode::GuildEmojiUpdate
    end

    client.on_guild_integrations_update do |payload|
      dispatch payload, Opcode::GuildIntegrationsUpdate
    end

    client.on_guild_member_add do |payload|
      dispatch payload, Opcode::GuildMemberAdd
    end

    client.on_guild_member_remove do |payload|
      dispatch payload, Opcode::GuildMemberRemove
    end

    client.on_guild_member_update do |payload|
      dispatch payload, Opcode::GuildMemberUpdate
    end

    client.on_guild_members_chunk do |payload|
      dispatch payload, Opcode::GuildMembersChunk
    end

    client.on_guild_role_create do |payload|
      dispatch payload, Opcode::GuildRoleCreate
    end

    client.on_guild_role_delete do |payload|
      dispatch payload, Opcode::GuildRoleDelete
    end

    client.on_guild_role_update do |payload|
      dispatch payload, Opcode::GuildRoleUpdate
    end

    client.on_guild_update do |payload|
      dispatch payload, Opcode::GuildUpdate
    end

    client.on_message_create do |payload|
      dispatch payload, Opcode::MessageCreate
    end

    client.on_message_delete do |payload|
      dispatch payload, Opcode::MessageDelete
    end

    client.on_message_delete_bulk do |payload|
      dispatch payload, Opcode::MessageDeleteBulk
    end

    client.on_message_update do |payload|
      dispatch payload, Opcode::MessageUpdate
    end

    client.on_presence_update do |payload|
      dispatch payload, Opcode::PresenceUpdate
    end

    client.on_ready do |payload|
      puts "ready as #{payload.user.username} on shard #{@shard_id}"

      dispatch payload, Opcode::Ready
    end

    client.on_resumed do |payload|
      dispatch payload, Opcode::Resumed
    end

    client.on_typing_start do |payload|
      dispatch payload, Opcode::TypingStart
    end

    client.on_user_update do |payload|
      dispatch payload, Opcode::UserUpdate
    end

    client.on_voice_server_update do |payload|
      dispatch payload, Opcode::VoiceServerUpdate
    end

    client.on_voice_state_update do |payload|
      dispatch payload, Opcode::VoiceStateUpdate
    end

    @client = client
  end

  def counter(opcode)
    @redis.incr "event_counter:all:#{opcode.value}"
  end

  def dispatch(payload, opcode)
    counter opcode

    # nice.
    #
    # Result:
    #
    # {
    #   "d": payload,
    #   "meta": {
    #     "op": 7, # ex.
    #     "shard_id": 0 # ex.
    #   }
    # }
    json = "{\"d\":#{payload.to_json}},\"meta\":{\"op\":#{opcode.value},\"shard_id\":#{@shard_id}}"
    msg = AMQP::Message.new json

    @exchange.publish msg, ENV["AMQP_EXCHANGE"]
  end

  def run
    @client.run
  end
end
