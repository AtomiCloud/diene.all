export interface IKeyValueStore {
  set(key: string, value: string): Promise<void>;
  get(key: string): Promise<string | null>;
  close(): Promise<void>;
}

export interface RedisConnection {
  readonly host: string;
  readonly port: number;
}
