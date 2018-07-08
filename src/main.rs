#![feature(catch_expr, proc_macro, generators)]

extern crate kankyo;
extern crate lapin_futures as lapin;
extern crate futures_await as futures;
extern crate tokio;
extern crate env_logger;
extern crate serenity;
extern crate tungstenite;

use futures::prelude::{async, await};
use tokio::net::TcpStream;
use lapin::types::FieldTable;
use lapin::client::ConnectionOptions;
use lapin::channel::{BasicPublishOptions,BasicProperties,ConfirmSelectOptions,ExchangeDeclareOptions,QueueBindOptions,QueueDeclareOptions};
use std::error::Error;
use tokio::executor::current_thread;
use serenity::gateway::Shard;
use std::env;
use std::rc::Rc;
use tungstenite::Message as TungsteniteMessage;

fn main() {
    kankyo::load().expect("Error loading kankyo");
    env_logger::init();
    current_thread::block_on_all(main_async()).expect("runtime exited with failure")
}

#[async]
fn main_async() -> Result<(), Box<Error + 'static>>
{
    let addr = std::env::var("AMQP_ADDR").unwrap_or_else(|_| "127.0.0.1:5672".to_string()).parse().unwrap();
    let token = Rc::new(env::var("DISCORD_TOKEN")
        .expect("Expected a token in the environment"));

    let stream = await!(TcpStream::connect(&addr))?;
    let client = await!(lapin::client::Client::connect(stream, ConnectionOptions {
        frame_max: 65535,
        ..Default::default()
    }))?;

   // tokio::spawn(client.1.map_err(|e| println!("{:?}", e)));

    let channel = await!(client.0.create_confirm_channel(ConfirmSelectOptions::default()))?;
    let id = channel.id;
    println!("created channel with id: {}", id);

    await!(channel.queue_declare("queue", QueueDeclareOptions::default(), FieldTable::new()))?;
    println!("channel {} declared queue {}", id, "queue");

    await!(channel.exchange_declare("exchange", "direct", ExchangeDeclareOptions::default(), FieldTable::new()))?;
    await!(channel.queue_bind("queue", "exchange", "queue2", QueueBindOptions::default(), FieldTable::new()))?;

    loop 
    {
        let mut shard = await!(Shard::new(Rc::clone(&token), [0, 1]))?;

        // Loop over websocket messages.
        let result: Result<_, Box<Error>> = do catch 
        {
            #[async]
            for message in shard.messages() {
                
                let msg = message.clone();

                let mut bytes = match message {
                    TungsteniteMessage::Binary(v) => v,
                    TungsteniteMessage::Text(v) => v.into_bytes(),
                    _ => continue,
                };

                let event = shard.parse(msg).unwrap();
                shard.process(&event);

                await!(     
                    channel.basic_publish(
                        "exchange",
                        "queue",
                        &bytes,
                        BasicPublishOptions::default(),
                        BasicProperties::default().with_user_id("guest".to_string()).with_reply_to("foobar".to_string())
                    )
                )?;
            
                println!("message processed!");
            }
            
            ()
        };

        if let Err(why) = result {
            println!("Error with loop occurred: {:?}", why);
            println!("Creating new shard");

            continue;
        }
    }
}