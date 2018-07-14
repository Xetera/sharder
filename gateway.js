const { Client } = require('@spectacles/gateway');
const rabbitmq   = require('amqplib');
const config     = require("./config");
const statsd     = require("hot-shots");
const datadog    = new statsd();

const client = new Client(config.token, {
    reconnect: true,
});

client.gateway = {
    url: "wss://gateway.discord.gg/",
    shards: config.shardCount,
};

var conn = null;
var channel = null;

client.on('receive', async (shard, packet) => 
{
    if(packet.op != 0)
    {
        return;
    }

    datadog.increment('gateway.packets.received', 1, 1, { "webhook-id": packet.t, "shard-id": packet.s });

    if(config.ignorePackets.includes(packet.t))
    {
        return;
    }
    
    console.log(`[SH#${shard}] => ${packet.t}`)
    await channel.sendToQueue("gateway", Buffer.from(JSON.stringify(packet)));   
    return;
});

async function main()
{   
    conn = getConnection();
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
            datadog.check('gateway.status.amqp', datadog.CHECKS.CRITICAL);
            conn = getConnection();
        });

        conn = newConn;
        channel = await conn.createChannel();
     
        channel.on('error', function(err) {
            console.log("[CRIT] CH " + err);
        });

        assert = await channel.assertQueue("gateway", {durable: true});

        return newConn;
    }
    catch(err)
    {
        console.log("[WARN] >> " + err);
        return null;
    }
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
    datadog.check('gateway.status.amqp', datadog.CHECKS.OK);
    return conn;
}

var shardsToInit = [];
for(var i = config.shardIndex; i < config.shardIndex + config.shardInit; i++)
{
    shardsToInit.push(i);
}

main();
client.spawn(shardsToInit);