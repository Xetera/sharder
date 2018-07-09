#![feature(catch_expr, proc_macro, generators)]

extern crate env_logger;
extern crate futures_await as futures;
extern crate kankyo;
extern crate lapin_futures as lapin;
extern crate serde_json;
extern crate serenity;
extern crate tokio;
extern crate tungstenite;

use futures::prelude::{async, await};
use lapin::types::FieldTable;
use lapin::client::ConnectionOptions;
use lapin::channel::{BasicPublishOptions,BasicProperties,ConfirmSelectOptions,ExchangeDeclareOptions,QueueBindOptions,QueueDeclareOptions};
use serde_json::Error as JsonError;
use serenity::gateway::Shard;
use serenity::Error as SerenityError;
use std::env;
use std::env::VarError;
use std::io::Error as IOError;
use std::rc::Rc;
use tokio::executor::current_thread;
use tokio::net::TcpStream;
use tungstenite::Error as TungsteniteError;
use tungstenite::Message as TungsteniteMessage;

#[derive(Debug)]
enum Error {
    Json(JsonError),
    Serenity(SerenityError),
    Tungstenite(TungsteniteError),
    IO(IOError),
    Var(VarError),
}

impl From<JsonError> for Error {
    fn from(err: JsonError) -> Self {
        Error::Json(err)
    }
}

impl From<SerenityError> for Error {
    fn from(err: SerenityError) -> Self {
        Error::Serenity(err)
    }
}

impl From<TungsteniteError> for Error {
    fn from(err: TungsteniteError) -> Self {
        Error::Tungstenite(err)
    }
}

impl From<IOError> for Error {
    fn from(err: IOError) -> Self {
        Error::IO(err)
    }
}

impl From<VarError> for Error {
    fn from(err: VarError) -> Self {
        Error::Var(err)
    }
}

fn main() {
    kankyo::load().expect("Error loading kankyo");
    env_logger::init();
    current_thread::block_on_all(main_async()).expect("runtime exited with failure")
}

#[async]
fn main_async() -> Result<(), Error>
{
    let addr = std::env::var("AMQP_ADDR").unwrap_or_else(|_| "127.0.0.1:5672".to_string()).parse().unwrap();
    let token = Rc::new(env::var("DISCORD_TOKEN")
        .expect("Expected a token in the environment"));

    let password = std::env::var("AMQP_PASS")?;
    let username = std::env::var("AMQP_USER")?;

    let exchange = std::env::var("AMQP_EXCHANGE")?;
    let queue = std::env::var("AMQP_QUEUE")?;

    let shardcount = std::env::var("DISCORD_SHARD_COUNT")?.parse::<u64>().ok().expect("rip");
    let shardindex = std::env::var("DISCORD_SHARD_INDEX")?.parse::<u64>().ok().expect("rip");

    let stream = await!(TcpStream::connect(&addr))?;
    let client = await!(lapin::client::Client::connect(stream, ConnectionOptions {
        password: password,
        username: username,
        frame_max: 65535,
        ..Default::default()
    }))?;

    let channel = await!(client.0.create_confirm_channel(ConfirmSelectOptions::default()))?;
    let id = channel.id;
    println!("created channel with id: {}", id);

    await!(channel.queue_declare(&queue, QueueDeclareOptions::default(), FieldTable::new()))?;
    println!("channel {} declared queue {}", id, "queue");

    await!(channel.exchange_declare(&exchange, "direct", ExchangeDeclareOptions::default(), FieldTable::new()))?;
    await!(channel.queue_bind(&queue, &exchange, "*", QueueBindOptions::default(), FieldTable::new()))?;

    let mut shard = await!(Shard::new(Rc::clone(&token), [shardindex, shardcount]))?;

    loop 
    {
        let result: Result<_, Error> = do catch 
        {
            #[async]
            for message in shard.messages() 
            {
                
                let msg = message.clone();

                let mut bytes = match message 
                {
                    TungsteniteMessage::Binary(v) => v,
                    TungsteniteMessage::Text(v) => v.into_bytes(),
                    _ => continue,
                };

                let event = shard.parse(msg).unwrap();
                shard.process(&event);

                await!(     
                    channel.basic_publish(
                        &exchange,
                        &queue,
                        &bytes,
                        BasicPublishOptions::default(),
                        BasicProperties::default()
                    )
                )?;
            
                println!("message processed!");
            }
            
            ()
        };

        if let Err(why) = result 
        {
            println!("Error with loop occurred: {:?}", why);

            match why 
            {
                Error::Tungstenite(TungsteniteError::ConnectionClosed(Some(close))) => 
                {
                    println!(
                        "Close: code: {}; reason: {}",
                        close.code,
                        close.reason,
                    );
                },
                other => 
                {
                    println!("Shard error: {:?}", other);

                    continue;
                },
            }

            println!("trying to autoreconnect...");

            await!(shard.autoreconnect()?);

            println!("hello");
        }
    }
}