import { Container } from '@cloudflare/containers';
import { engineGateway } from './gateway.ts';

export class NzRoutingContainer extends Container {
  defaultPort = 8002;
  sleepAfter = '2m';
  enableInternet = false;
}

interface Env {
  NZ_ROUTING: DurableObjectNamespace<NzRoutingContainer>;
  ROUTING_TOKEN?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // One stable instance prevents a container being started per user or trip.
    // Oceania is a placement hint, not a guarantee of a particular city.
    return engineGateway(request, env.ROUTING_TOKEN, (engineRequest) => {
      const engine = env.NZ_ROUTING.get(env.NZ_ROUTING.idFromName('nz'), { locationHint: 'oc' });
      return engine.fetch(engineRequest);
    });
  },
};
