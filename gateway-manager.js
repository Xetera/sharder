const config = require('./manager.config');
const childProcess = require('child_process');

function spawnGateway(index)
{
    let child = childProcess.spawn("node", ['gateway'], {
        env: {
            SHARD: index,
            SHARDCOUNT: config.shardCount
        }
    })    

    child.stdout.on('data', (data) => {
        process.stdout.write(`[SHARD_${index}]: ${data}`);
    });
    
    child.stderr.on('data', (data) => {
        process.stderr.write(`[SHARD_${index}]: ${data}`);
    });

    child.on('exit', (num, signal) => {
        console.log(`[SHARD_${index}] has closed unexpectingly, reconnecting...`);
        spawnGateway(index);
    });
}

for(var i = config.shardIndex; i < config.shardIndex + config.shardInit; i++)
{
    spawnGateway(i);
}