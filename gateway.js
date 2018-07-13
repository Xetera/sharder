const Discord    = require('discord.js');
const rabbitmq   = require('amqplib');
const config     = require("./config");
const statsd     = require("hot-shots");
const datadog    = new statsd();

const client = new Discord.Client({
    shardCount: parseInt(process.env.SHARDCOUNT),
    shardId: parseInt(process.env.SHARD)
});

var conn = null;
var channel = null;

client.on('raw', async (p) => 
{
    if(p.op != 0)
    {
        return;
    }

    datadog.increment('webhooks.received', 1, 1, { "webhook-id": p.t, "shard-id": p.s });

    if(config.ignorePackets.includes(p.t))
    {
        return;
    }
    
    console.log(`[SENT] => ${p.t}`)
    await channel.sendToQueue("gateway", Buffer.from(JSON.stringify(p)));   
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

main();
client.login(config.token);
