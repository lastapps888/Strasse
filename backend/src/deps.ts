import type {
  AbuseCounter,
  KeyValueCache,
  RefreshTokenRepository,
  ReportRepository,
  SyncRepository,
  UserRepository,
} from './repositories/interfaces.js';
import type { TrafficProvider } from './traffic/provider.js';

/** Dépendances injectées dans l'application (dépôts réels ou en mémoire pour les tests). */
export interface Deps {
  users: UserRepository;
  refreshTokens: RefreshTokenRepository;
  sync: SyncRepository;
  reports: ReportRepository;
  counters: AbuseCounter;
  cache: KeyValueCache;
  traffic: TrafficProvider;
  now: () => Date;
}
