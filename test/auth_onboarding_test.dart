import 'package:diene_flutter_base/auth/session_controller.dart';
import 'package:diene_flutter_base/onboarding/onboarding.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter_test/flutter_test.dart';

final class _CountingHomeGateway implements HomeClaimGateway {
  String? claim;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> readHomeClaim() async {
    reads += 1;
    return claim;
  }

  @override
  Future<void> writeHomeClaim(String landscape) async {
    writes += 1;
    claim = landscape;
  }
}

final class _OnboardingGateway implements OnboardingGateway {
  UserProbeResult result = UserProbeResult.absent;
  int probes = 0;
  int synchronizations = 0;

  @override
  Future<UserProbeResult> probeCurrentUser(String backendId) async {
    probes += 1;
    return result;
  }

  @override
  Future<void> synchronizeCurrentUser(String backendId) async {
    synchronizations += 1;
    result = UserProbeResult.present;
  }
}

final class _AuthGateway implements AuthGateway {
  _AuthGateway(this.now);

  final DateTime now;
  int signIns = 0;
  int refreshes = 0;
  int reMints = 0;
  int signOuts = 0;
  bool reuseRefreshToken = false;

  @override
  Future<SessionTokens> signIn() async {
    signIns += 1;
    return _tokens(rotation: signIns);
  }

  @override
  Future<SessionTokens> refresh(SessionTokens current) async {
    refreshes += 1;
    return SessionTokens(
      accessToken: 'access-refresh-$refreshes',
      refreshToken: reuseRefreshToken
          ? current.refreshToken
          : 'refresh-rotated-$refreshes',
      refreshFamily: current.refreshFamily,
      accessExpiresAt: now.add(const Duration(minutes: 10)),
      refreshExpiresAt: now.add(const Duration(days: 14)),
    );
  }

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) async {
    reMints += 1;
    return SessionTokens(
      accessToken: 'access-open-$reMints',
      refreshToken: current.refreshToken,
      refreshFamily: current.refreshFamily,
      accessExpiresAt: now.add(const Duration(minutes: 10)),
      refreshExpiresAt: current.refreshExpiresAt,
    );
  }

  @override
  Future<void> signOut() async => signOuts += 1;

  SessionTokens _tokens({required int rotation}) => SessionTokens(
    accessToken: 'access-$rotation',
    refreshToken: 'refresh-$rotation',
    refreshFamily: 'family-one',
    accessExpiresAt: now.add(const Duration(minutes: 10)),
    refreshExpiresAt: now.add(const Duration(days: 14)),
  );
}

void main() {
  final DateTime now = DateTime.utc(2026, 7, 18, 1);

  test(
    'single-region picker writes once and always reads the home claim',
    () async {
      final _CountingHomeGateway home = _CountingHomeGateway();
      final SingleRegionHomePicker picker = SingleRegionHomePicker(
        gateway: home,
        landscape: 'pichu',
      );

      expect((await picker.resolve()).isOk, isTrue);
      expect((await picker.resolve()).isOk, isTrue);
      expect(home.reads, 2);
      expect(home.writes, 1);
      expect(home.claim, 'pichu');
    },
  );

  test(
    'onboarding probes first and synchronizes only an absent user',
    () async {
      final _CountingHomeGateway home = _CountingHomeGateway();
      final _OnboardingGateway backend = _OnboardingGateway();
      final OnboardingCoordinator coordinator = OnboardingCoordinator(
        homePicker: SingleRegionHomePicker(gateway: home, landscape: 'lapras'),
        gateway: backend,
        backendId: 'primary',
      );

      final Result<OnboardingPhase> first = await coordinator.runAfterSignIn();
      final Result<OnboardingPhase> second = await coordinator.runAfterSignIn();

      expect(first.isOk, isTrue);
      expect(second.isOk, isTrue);
      expect(coordinator.phase, OnboardingPhase.ready);
      expect(backend.probes, 2);
      expect(backend.synchronizations, 1);
      expect(home.reads, 2);
    },
  );

  test(
    'session enforces lifetimes, rotates refresh, and re-mints on open',
    () async {
      final _AuthGateway auth = _AuthGateway(now);
      final _CountingHomeGateway home = _CountingHomeGateway();
      final SessionController session = _session(
        auth: auth,
        home: home,
        now: now,
      );

      expect((await session.signIn()).isOk, isTrue);
      expect(
        session.tokens!.accessExpiresAt.difference(now),
        const Duration(minutes: 10),
      );
      expect(
        session.tokens!.refreshExpiresAt.difference(now),
        const Duration(days: 14),
      );
      final String initialRefresh = session.tokens!.refreshToken;

      expect((await session.refresh()).isOk, isTrue);
      expect(session.tokens!.refreshToken, isNot(initialRefresh));
      expect((await session.onAppOpen()).isOk, isTrue);
      expect(auth.reMints, 1);
      expect(session.tokens!.accessToken, 'access-open-1');
    },
  );

  test('refresh token reuse signs out the whole session', () async {
    final _AuthGateway auth = _AuthGateway(now)..reuseRefreshToken = true;
    final SessionController session = _session(
      auth: auth,
      home: _CountingHomeGateway(),
      now: now,
    );
    await session.signIn();

    final Result<SessionTokens> result = await session.refresh();

    expect(result, isA<Err<SessionTokens>>());
    expect(session.status, SessionStatus.unauthenticated);
    expect(session.tokens, isNull);
    expect(auth.signOuts, 1);
  });

  test('home claim is checked on every sign-in', () async {
    final _AuthGateway auth = _AuthGateway(now);
    final _CountingHomeGateway home = _CountingHomeGateway();
    final SessionController session = _session(
      auth: auth,
      home: home,
      now: now,
    );

    await session.signIn();
    await session.signOut();
    await session.signIn();

    expect(home.reads, 2);
    expect(auth.signIns, 2);
  });
}

SessionController _session({
  required _AuthGateway auth,
  required _CountingHomeGateway home,
  required DateTime now,
}) => SessionController(
  gateway: auth,
  onboarding: OnboardingCoordinator(
    homePicker: SingleRegionHomePicker(gateway: home, landscape: 'lapras'),
    gateway: _OnboardingGateway()..result = UserProbeResult.present,
    backendId: 'primary',
  ),
  accessLifetime: const Duration(minutes: 10),
  refreshLifetime: const Duration(days: 14),
  now: () => now,
);
