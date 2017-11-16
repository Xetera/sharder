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

macro event(client, method, opcode)
  {{client}}.{{method}} do |payload|
    dispatch payload, {{opcode}}
  end
end

class Shard
  @@amqp : AMQP::Connection = initialize_amqp
  @@channel : AMQP::Channel = @@amqp.channel
  @@exchange : AMQP::Exchange = @@channel.default_exchange
  @@redis : Redis = initialize_redis

  @client : Discord::Client
  @shard_id : Int32

  def initialize(token, client_id, shard_id, shard_total)
    @shard_id = shard_id

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

    event client, on_channel_create, Opcode::ChannelCreate
    event client, on_channel_delete, Opcode::ChannelDelete
    event client, on_channel_update, Opcode::ChannelUpdate
    event client, on_guild_ban_add, Opcode::GuildBanAdd
    event client, on_guild_ban_remove, Opcode::GuildBanRemove
    event client, on_guild_create, Opcode::GuildCreate
    event client, on_guild_delete, Opcode::GuildDelete
    event client, on_guild_emoji_update, Opcode::GuildEmojiUpdate
    event client, on_guild_integrations_update, Opcode::GuildIntegrationsUpdate
    event client, on_guild_member_add, Opcode::GuildMemberAdd
    event client, on_guild_member_remove, Opcode::GuildMemberRemove
    event client, on_guild_member_update, Opcode::GuildMemberUpdate
    event client, on_guild_members_chunk, Opcode::GuildMembersChunk
    event client, on_guild_role_create, Opcode::GuildRoleCreate
    event client, on_guild_role_delete, Opcode::GuildRoleDelete
    event client, on_guild_role_update, Opcode::GuildRoleUpdate
    event client, on_guild_update, Opcode::GuildUpdate
    event client, on_message_create, Opcode::MessageCreate
    event client, on_message_delete, Opcode::MessageDelete
    event client, on_message_delete_bulk, Opcode::MessageDeleteBulk
    event client, on_message_update, Opcode::MessageUpdate
    event client, on_presence_update, Opcode::PresenceUpdate
    event client, on_ready, Opcode::Ready
    event client, on_resumed, Opcode::Resumed
    event client, on_typing_start, Opcode::TypingStart
    event client, on_user_update, Opcode::UserUpdate
    event client, on_voice_server_update, Opcode::VoiceServerUpdate
    event client, on_voice_state_update, Opcode::VoiceStateUpdate

    @client = client
  end

  def counter(opcode)
    @@redis.incr "event_counter:all:#{opcode.value}"
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

    @@exchange.publish msg, ENV["AMQP_EXCHANGE"]
  end

  def run
    @client.run
  end
end
