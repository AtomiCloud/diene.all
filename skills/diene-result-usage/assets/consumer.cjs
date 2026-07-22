const { Option, Result } = require('@atomicloud/diene.result');

module.exports.doubled = Result.ok(21)
  .map(value => value * 2)
  .unwrap();

module.exports.present = Option.fromNullable('value').isSome;
