import { artifactPresence } from './lib/cli-contract.ts';

export default artifactPresence('cli-probe-inventory', ['probes/features.json', 'probes/cli-*.ts']);
