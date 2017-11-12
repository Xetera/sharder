# yuki-sharder

Sharder is a bridge between the Discord gateway and our choice of message
broker.

This is used to design an architecture for an application where the bot itself
retains a theoretical uptime of 100% (sans ISP issues, Discord issues, etc.).
The messages can be passed to a message broker which _should_ round-robin the
messages to consumers to handle them. This creates an architecture where
everything can be updated, restarted, and/or re-provisioned with zero downtime.

### Self-hosting

Self-hosting is not supported.

### License

All rights reserved.
