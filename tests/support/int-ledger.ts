import { loadLedger } from './ledger';

// The integration ledger is the adapter tier: every file under src/adapters is measured.
await loadLedger('src/adapters');
