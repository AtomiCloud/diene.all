# Flutter variant

Drive the flow through `SingleRegionHomePicker`, `OnboardingCoordinator`, and
typed `OnboardingPhase` values. Never infer the build landscape at runtime.
Represent each async phase explicitly so routing cannot skip the home check or
run synchronization before the user probe.
