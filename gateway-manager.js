const config = require('./config');
const { spawn } = require('child_process');

for(var i = config.shardIndex; i < config.shardIndex + config.shardInit; i++)
{
    // let child = spawn('node',    
    // child.stdout.on('data', (data) => {
    //     console.log(`child stdout:\n${data}`);
    // });
    
    // child.stderr.on('data', (data) => {
    // console.error(`child stderr:\n${data}`);
    // });
}