import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  CompiledEndpoint,
  DeliveryFailure,
  DeliveryRequest,
  DeliveryResponse,
  DeliveryTransport,
  EndpointRefresher,
  EndpointRefreshRequest,
  TransportFailure,
} from '../domain/index.ts';

export type ScriptedTransportResult = Readonly<{ status: number }> | Readonly<{ error: TransportFailure }>;

export class ScriptedDeliveryTransport implements DeliveryTransport {
  readonly requests: DeliveryRequest[] = [];
  readonly scripts = new Map<string, ScriptedTransportResult[]>();

  set(url: string, results: readonly ScriptedTransportResult[]): void {
    this.scripts.set(url, [...results]);
  }

  async send(request: DeliveryRequest): Promise<Result<DeliveryResponse, TransportFailure>> {
    this.requests.push({
      ...request,
      body: request.body.slice(),
      headers: { ...request.headers },
    });
    const result = this.scripts.get(request.url)?.shift() ?? { status: 200 };
    return 'error' in result ? Err(result.error) : Ok({ status: result.status, headers: {} });
  }
}

export class ScriptedEndpointRefresher implements EndpointRefresher {
  readonly requests: EndpointRefreshRequest[] = [];
  public endpoint: CompiledEndpoint;
  public failure: DeliveryFailure | null = null;

  constructor(endpoint: CompiledEndpoint) {
    this.endpoint = endpoint;
  }

  async refreshEndpoint(request: EndpointRefreshRequest): Promise<Result<CompiledEndpoint, DeliveryFailure>> {
    this.requests.push(request);
    return this.failure === null ? Ok(this.endpoint) : Err(this.failure);
  }
}
