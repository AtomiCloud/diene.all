# Flutter variant

- Start with Material 3 `ColorScheme.fromSeed`, then apply identity tokens.
- Centralize `ThemeData`, component themes, typography, radii, and transitions.
- Ship `ThemeMode.light`, `dark`, and `system`; runtime token changes must
  rebuild live `ThemeData`.
- Prefer native Material/Cupertino behavior while retaining the app's visual
  signature. Do not reproduce web hover-only interactions on touch devices.
