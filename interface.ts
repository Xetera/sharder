export interface IConfig {
    ignorePackets: string[];
    rabbitUrl: string;
    rabbitExchange: string;
    rabbitChannel: string;
    shardIndex: number;
    shardInit: number;
    shardCount: number;
    token: string;
}
