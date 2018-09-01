import { Client } from "@spectacles/gateway";
import * as rabbitmq from "amqplib";
import config from "./config";

const client: Client = new Client(config.token, {
    reconnect: true
});

client.gateway = {
    url: "wss://gateway.discord.gg/",
    shards: config.shardCount
};
const debug = true;

// inconsistent typings from rabbitmq here
let conn: rabbitmq.Connection | null;

let gatewayChannel: rabbitmq.Channel | undefined;

let commandChannel: rabbitmq.Channel | undefined;

client.on("receive", async (shard, packet) => {
    if (packet.op != 0) {
        return;
    }

    if (packet.t == "PRESENCE_UPDATE") {
        if (Object.keys(packet.d.user).length > 1) {
            packet.t = "USER_UPDATE";
            packet.d = packet.d.user;
        }
    }

    if (config.ignorePackets.includes(packet.t)) {
        return;
    }

    if (debug) {
        console.log(`[${packet.t}]`);
    }

    if (!gatewayChannel) {
        return void console.log(
            "[WARN] Received a packet but gateway channel is not set."
        );
    }

    await gatewayChannel.sendToQueue(
        config.rabbitChannel,
        Buffer.from(JSON.stringify(packet))
    );
    return;
});

async function initConnection() {
    try {
        let newConn = await rabbitmq.connect(
            config.rabbitUrl,
            {
                defaultExchangeName: config.rabbitExchange
            }
        );

        newConn.on("error", async err => {
            console.error("[CRIT] CN " + err);
            conn = await getConnection();
        });

        conn = newConn;

        commandChannel = await conn.createChannel();
        await commandChannel.assertExchange(
            config.rabbitExchange + "-command",
            "fanout",
            { durable: true }
        );

        await commandChannel.assertQueue("gateway-command");
        await commandChannel.consume(
            "gateway-command",
            async (msg: rabbitmq.Message | null) => {
                console.log("message receieved");
                if (!msg) {
                    return console.log(
                        "[WARN] Cannot consume message beacuse it is empty."
                    );
                }
                let packet = JSON.parse(msg.content.toString());

                console.log(JSON.stringify(packet));

                if (client.connections.has(packet.shard_id)) {
                    let shard = client.connections.get(packet.shard_id);
                    // shard is already asserted to exist
                    await shard!.send(packet.opcode, packet.data);
                }
            },
            { noAck: true }
        );
        return newConn;
    } catch (err) {
        console.log("[WARN] >> " + err);
        return null;
    }
}

async function createPushChannel(
    channelName: string
): Promise<rabbitmq.Channel | undefined> {
    if (!conn) {
        return void console.log(
            "[WARN] Could not create push channel, missing connection."
        );
    }
    const channel: rabbitmq.Channel = await conn.createChannel();

    channel.on("error", function(err) {
        console.error("[CRIT] CH " + err);
    });
    try {
        await channel.assertQueue(channelName, { durable: true });
    } catch (err) {
        console.error(`[ERROR] Failed to assert queue`);
        console.error(err);
    }

    return channel;
}

async function getConnection() {
    while (true) {
        conn = await initConnection();

        if (conn == null) {
            console.log("[WARN] >> connection failed, retrying..");
            setTimeout(() => {}, 1000);
            continue;
        }

        break;
    }

    console.log("[ OK ] >> (re)connected");
    return conn;
}

const shardsToInit: number[] = [];
for (let i = config.shardIndex; i < config.shardIndex + config.shardInit; i++) {
    shardsToInit.push(i);
}

(async function main() {
    conn = await getConnection();

    gatewayChannel = await createPushChannel(config.rabbitChannel);
})();

client.spawn(shardsToInit);
