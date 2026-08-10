# Dart stateless OOP and DI variant

Make services stateless where possible and inject clocks, clients, stores, and sinks through constructors. Stateful Flutter controllers expose immutable observations and own lifecycle cleanup. Avoid ambient singletons except framework-required registration points.
