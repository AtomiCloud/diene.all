import { loadLedger } from './ledger';

// The unit ledger is the domain tier: every file under src/lib is measured, tested or not.
await loadLedger('src/lib');
