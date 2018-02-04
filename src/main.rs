#![feature(proc_macro, conservative_impl_trait, generators)]
#![feature(alloc_system)]
#![feature(global_allocator, allocator_api)]

extern crate alloc_system;

use alloc_system::System;

#[global_allocator]
static A: System = System;

#[macro_use] extern crate log;
#[macro_use] extern crate redis_async as redis;

extern crate env_logger;
extern crate futures_await as futures;
extern crate kankyo;
extern crate serenity;
extern crate tokio_core;
extern crate tungstenite;

use futures::prelude::*;
use redis::client::paired_connect;
use redis::resp::{FromResp, RespValue};
use serenity::gateway::Shard;
use std::cell::RefCell;
use std::error::Error;
use std::rc::Rc;
use std::env;
use tokio_core::reactor::{Core, Handle};
use tungstenite::Message as TungsteniteMessage;

fn main() {
    kankyo::load().expect("Error loading kankyo");
    env_logger::init();

    let mut core = Core::new().expect("Error creating event loop");
    let future = try_main(core.handle());

    core.run(future).expect("Error running event loop");
}

#[async]
fn try_main(handle: Handle) -> Result<(), Box<Error + 'static>> {
    // Configure the client with your Discord bot token in the environment.
    let token = env::var("DISCORD_TOKEN")?;
    let redis_addr = env::var("REDIS_ADDR")?.parse()?;

    let redis = await!(paired_connect(&redis_addr, &handle))?;

    // Create a new shard, specifying the token, the ID of the shard (0 of 1),
    // and a handle to the event loop
    let mut shard = Rc::new(RefCell::new(await!(Shard::new(token, [0, 1], handle.clone()))?));
    let shard_id = 0;

    let h2 = handle.clone();

    handle.spawn(background(h2, Rc::clone(&shard), shard_id));

    let messages = shard.borrow_mut().messages();

    // Loop over websocket messages.
    #[async]
    for message in messages {
        let mut bytes = match message {
            TungsteniteMessage::Binary(v) => v,
            TungsteniteMessage::Text(v) => v.into_bytes(),
            _ => continue,
        };

        bytes.push(shard_id);

        let cmd = resp_array!["RPUSH", "exchange:gateway_events", bytes];
        let done = redis.send(cmd)
            .map(|_: RespValue| ())
            .map_err(|why| {
                warn!("Err sending to redis: {:?}", why);
            });

        handle.spawn(done);
    }

    Ok(())
}

#[async]
fn background(handle: Handle, shard: Rc<RefCell<Shard>>, shard_id: u8)
    -> Result<(), ()> {
    let key = format!("exchange:sharder:{}", shard_id);
    let addr = env::var("REDIS_ADDR").unwrap().parse().unwrap();
    let redis = await!(paired_connect(&addr, &handle)).unwrap();

    loop {
        let mut parts: Vec<RespValue> = match await!(redis.send(resp_array!["BLPOP", &key, 0])) {
            Ok(parts) => parts,
            Err(why) => {
                warn!("Err sending blpop cmd: {:?}", why);

                continue;
            },
        };
        let part = if parts.len() == 2 {
            parts.remove(1)
        } else {
            warn!("blpop result part count != 2: {:?}", parts);

            continue;
        };

        let mut message: Vec<u8> = match FromResp::from_resp(part) {
            Ok(message) => message,
            Err(why) => {
                warn!("Err parsing part to bytes: {:?}", why);

                continue;
            },
        };

        let mut shard = shard.borrow_mut();
        let event = shard.parse(TungsteniteMessage::Binary(message)).unwrap();

        shard.process(&event);
    }
}
