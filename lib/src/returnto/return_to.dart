import '../contracts/problem.dart';
import '../contracts/result.dart';

/// returnTo deeplink continuation (goals/lib/dart-family.md auth-engine row).
///
/// A deeplink into a protected screen → login → resume the EXACT target route
/// with path AND query preserved. Only same-origin RELATIVE targets are legal;
/// any absolute URL / protocol-relative `//host` / back-slash trick is rejected
/// as an open redirect.
abstract final class ReturnTo {
  /// The query parameter name carrying the encoded target.
  static const String queryKey = 'returnTo';

  /// Validates [target] as a safe relative route and returns its canonical
  /// `path[?query][#fragment]` string. Rejects open-redirect inputs.
  static Result<String> capture(Uri target) {
    if (target.hasScheme || target.hasAuthority) {
      return _reject('returnTo target must be relative (no scheme/authority)');
    }
    final String path = target.path;
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.startsWith('/\\')) {
      return _reject('returnTo path must begin with a single "/"');
    }
    return Success<String>(_render(target));
  }

  /// Builds the login redirect [loginBase] carrying the validated returnTo.
  static Result<Uri> buildLoginRedirect(Uri loginBase, Uri target) =>
      capture(target).map(
        (String encoded) => loginBase.replace(
          queryParameters: <String, String>{
            ...loginBase.queryParameters,
            queryKey: encoded,
          },
        ),
      );

  /// Resolves a captured returnTo string back to the EXACT relative target,
  /// re-validating the open-redirect guard on the way out (a tampered value is
  /// rejected, not followed).
  static Result<Uri> resolve(String raw) {
    if (raw.isEmpty) {
      return _reject('returnTo is empty');
    }
    final Uri parsed;
    try {
      parsed = Uri.parse(raw);
    } on FormatException {
      return _reject('returnTo is not a valid URI reference');
    }
    if (parsed.hasScheme || parsed.hasAuthority) {
      return _reject('returnTo must not carry a scheme/authority');
    }
    if (!parsed.path.startsWith('/') ||
        parsed.path.startsWith('//') ||
        raw.startsWith('//') ||
        raw.startsWith('/\\')) {
      return _reject('returnTo must be a single-slash relative path');
    }
    return Success<Uri>(Uri.parse(_render(parsed)));
  }

  /// Extracts and resolves the returnTo from a post-login callback URL, or
  /// falls back to [fallback] when absent/invalid.
  static Uri continueFrom(Uri callback, {required Uri fallback}) {
    final String? raw = callback.queryParameters[queryKey];
    if (raw == null) {
      return fallback;
    }
    return resolve(raw).unwrapOr(fallback);
  }

  static String _render(Uri target) {
    final String query = target.hasQuery ? '?${target.query}' : '';
    final String fragment = target.hasFragment ? '#${target.fragment}' : '';
    return '${target.path}$query$fragment';
  }

  static Result<R> _reject<R>(String detail) => Failure<R>(
    Problem(
      type: 'urn:diene:problem:return-to',
      title: 'Invalid returnTo target',
      status: 400,
      detail: detail,
    ),
  );
}
