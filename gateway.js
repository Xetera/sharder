const { Client } = require('@spectacles/gateway');
const rabbitmq   = require('amqplib');
const config     = require("./config");
const util       = require('util');

const debug = true;

const client = new Client(config.token, {
    reconnect: true,
});

client.gateway = {
    url: "wss://gateway.discord.gg/",
    shards: config.shardCount,
};

var conn = null;

var gatewayChannel = null;

var commandChannel = null;

client.on('receive', async (shard, packet) => 
{
    if(packet.op != 0)
    {
        return;
    }

    if(packet.t == "PRESENCE_UPDATE")
    {
        if(Object.keys(packet.d.user).length > 1)
        {
            packet.t = "USER_UPDATE";
            packet.d = packet.d.user;
        }
    }

    if(config.ignorePackets.includes(packet.t))
    {
        return;
    }

    if(debug)
    {
        console.log(`[${packet.t}]`)
    }

    await gatewayChannel.sendToQueue(config.rabbitChannel, Buffer.from(JSON.stringify(packet)));   
    return;
});

async function main()
{   
    conn = await getConnection();

    gatewayChannel = await createPushChannel(config.rabbitChannel);
}

async function initConnection()
{
    try
    {
        let newConn = await rabbitmq.connect(config.rabbitUrl, {
            defaultExchangeName: config.rabbitExchange
        });

        newConn.on('error', async (err) => {
            console.log("[CRIT] CN " + err);
            conn = getConnection();
        });

        conn = newConn;

        commandChannel = await conn.createChannel();
        await commandChannel.assertExchange(config.rabbitExchange + "-command", 'fanout', {durable: true});

        await commandChannel.assertQueue("gateway-command")
        await commandChannel.consume("gateway-command", async (msg) => {

            console.log("message receieved");

            let packet = JSON.parse(msg.content.toString());

            console.log(JSON.stringify(packet));

            if(client.connections.has(packet.shard_id))
            {
                let shard = client.connections.get(packet.shard_id);
                await shard.send(packet.opcode, packet.data);   
            }
        }, {noAck: true});
        return newConn;
    }
    catch(err)
    {
        console.log("[WARN] >> " + err);
        return null;
    }
}

async function createPushChannel(channelName)
{
    var channel = await conn.createChannel();
     
    channel.on('error', function(err) {
        console.log("[CRIT] CH " + err);
    });

    assert = await channel.assertQueue(channelName, {durable: true});

    return channel;
}

async function getConnection()
{
    while(true)
    {
        conn = await initConnection();

        if(conn == null)
        {
            console.log("[WARN] >> connection failed, retrying..")
            setTimeout(() => {}, 1000);
            continue;
        }

        break;
    }

    console.log("[ OK ] >> (re)connected")
    return conn;
}

var shardsToInit = [];
for(var i = config.shardIndex; i < config.shardIndex + config.shardInit; i++)
{
    shardsToInit.push(i);
}

main();
client.spawn(shardsToInit);