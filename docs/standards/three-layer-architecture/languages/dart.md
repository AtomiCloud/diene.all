# Dart three-layer architecture variant

Separate domain values and policies, application coordinators/controllers, and infrastructure/UI adapters. Generated OA3 DTOs remain transport-layer types. Widgets consume application state and never call store/auth/network SDKs directly.
